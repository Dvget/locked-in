import ActivityKit
import AppIntents
import Foundation

private func latestRunActivity() -> Activity<LockedInRunActivityAttributes>? {
    Activity<LockedInRunActivityAttributes>.activities.max {
        $0.attributes.startedAt < $1.attributes.startedAt
    }
}

struct ToggleRunPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Lauf pausieren oder fortsetzen"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        guard let activity = latestRunActivity() else { return .result() }

        var state = activity.content.state
        guard !state.finishRequested else { return .result() }
        let now = Date()
        if state.isPaused {
            state.isPaused = false
            state.timerAnchor = now.addingTimeInterval(-TimeInterval(state.activeDurationSeconds))
        } else {
            let elapsed = max(0, Int(now.timeIntervalSince(state.timerAnchor)))
            state.activeDurationSeconds = max(state.activeDurationSeconds, elapsed)
            state.isPaused = true
        }
        state.controlRevision += 1
        state.controlDate = now

        await activity.update(ActivityContent(state: state, staleDate: nil))
        return .result()
    }
}

struct ToggleRunSpeechIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Kilometeransagen umschalten"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        guard let activity = latestRunActivity() else { return .result() }

        var state = activity.content.state
        guard !state.finishRequested else { return .result() }
        state.speechEnabled.toggle()
        state.controlRevision += 1
        state.controlDate = Date()

        await activity.update(ActivityContent(state: state, staleDate: nil))
        return .result()
    }
}

struct FinishRunIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Lauf beenden"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        guard let activity = latestRunActivity() else { return .result() }

        var state = activity.content.state
        guard state.isPaused, !state.finishRequested else { return .result() }
        state.finishRequested = true
        state.controlRevision += 1
        state.controlDate = Date()

        await activity.update(ActivityContent(state: state, staleDate: nil))
        return .result()
    }
}
