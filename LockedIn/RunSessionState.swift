import Foundation

enum RunSessionPhase: String, Codable, Equatable {
    case preparing
    case countdown
    case recording
    case paused
    case finishing
    case saved
    case discarded
}

struct RunSessionClock: Codable, Equatable {
    private(set) var phase: RunSessionPhase = .preparing
    private(set) var startedAt: Date?
    private(set) var pausedAt: Date?
    private(set) var finishedAt: Date?
    private(set) var accumulatedPausedDuration: TimeInterval = 0

    mutating func beginCountdown() -> Bool {
        guard phase == .preparing else { return false }
        phase = .countdown
        return true
    }

    mutating func start(at date: Date) -> Bool {
        guard phase == .preparing || phase == .countdown else { return false }
        startedAt = date
        pausedAt = nil
        finishedAt = nil
        accumulatedPausedDuration = 0
        phase = .recording
        return true
    }

    mutating func pause(at date: Date) -> Bool {
        guard phase == .recording, let startedAt, date >= startedAt else { return false }
        pausedAt = date
        phase = .paused
        return true
    }

    mutating func resume(at date: Date) -> Bool {
        guard phase == .paused, let pausedAt, date >= pausedAt else { return false }
        accumulatedPausedDuration += date.timeIntervalSince(pausedAt)
        self.pausedAt = nil
        phase = .recording
        return true
    }

    mutating func finish(at date: Date) -> Bool {
        guard phase == .recording || phase == .paused,
              let startedAt,
              date >= startedAt else { return false }

        if let pausedAt {
            accumulatedPausedDuration += max(0, date.timeIntervalSince(pausedAt))
            self.pausedAt = nil
        }
        finishedAt = date
        phase = .finishing
        return true
    }

    mutating func markSaved() -> Bool {
        guard phase == .finishing else { return false }
        phase = .saved
        return true
    }

    mutating func discard() -> Bool {
        guard phase != .saved && phase != .discarded else { return false }
        phase = .discarded
        return true
    }

    func activeDuration(at date: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        let endpoint: Date
        if let finishedAt {
            endpoint = finishedAt
        } else if phase == .paused, let pausedAt {
            endpoint = pausedAt
        } else {
            endpoint = max(date, startedAt)
        }
        return max(0, endpoint.timeIntervalSince(startedAt) - accumulatedPausedDuration)
    }

    func pausedDuration(at date: Date) -> TimeInterval {
        guard phase == .paused, let pausedAt else {
            return accumulatedPausedDuration
        }
        return accumulatedPausedDuration + max(0, date.timeIntervalSince(pausedAt))
    }
}

struct RunSessionCheckpoint: Codable, Equatable {
    let runID: UUID
    let clock: RunSessionClock
    let metrics: RunMetricsSnapshot
    let speechEnabled: Bool
    let savedAt: Date

    func isRestorable(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(savedAt) < 24 * 60 * 60
            && [.recording, .paused, .finishing].contains(clock.phase)
    }
}
