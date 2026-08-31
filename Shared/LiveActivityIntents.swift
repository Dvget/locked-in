import Foundation
import ActivityKit
import AppIntents

private enum LiveTimerIntentSupport {
    static func activity() -> Activity<LockedInActivityAttributes>? {
        Activity<LockedInActivityAttributes>.activities.max {
            $0.attributes.startedAt < $1.attributes.startedAt
        }
    }

    static func secondsRemaining(in state: LockedInActivityAttributes.ContentState) -> Int {
        if state.isPaused {
            return max(0, state.pausedRemainingSeconds)
        }
        guard let end = state.restEndDate else { return 0 }
        return max(0, Int(ceil(end.timeIntervalSinceNow)))
    }

    static func update(
        _ activity: Activity<LockedInActivityAttributes>,
        state: LockedInActivityAttributes.ContentState
    ) async {
        let staleDate: Date?
        if state.isPaused {
            staleDate = nil
        } else {
            staleDate = state.restEndDate
        }

        await activity.update(
            ActivityContent(
                state: state,
                staleDate: staleDate
            )
        )
    }
}

struct SubtractThirtySecondsIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "30 Sekunden abziehen"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        guard let activity = LiveTimerIntentSupport.activity() else { return .result() }
        var state = activity.content.state

        if state.isPaused {
            state.pausedRemainingSeconds = max(0, state.pausedRemainingSeconds - 30)
        } else if let end = state.restEndDate {
            let remaining = max(0, Int(ceil(end.timeIntervalSinceNow)) - 30)
            state.restEndDate = remaining > 0
                ? Date().addingTimeInterval(TimeInterval(remaining))
                : nil
        }

        await LiveTimerIntentSupport.update(activity, state: state)
        return .result()
    }
}

struct AddThirtySecondsIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "30 Sekunden hinzufügen"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        guard let activity = LiveTimerIntentSupport.activity() else { return .result() }
        var state = activity.content.state

        if state.isPaused {
            state.pausedRemainingSeconds = min(900, state.pausedRemainingSeconds + 30)
        } else {
            let remaining = LiveTimerIntentSupport.secondsRemaining(in: state)
            let updated = min(900, remaining + 30)
            state.restEndDate = Date().addingTimeInterval(TimeInterval(updated))
        }

        await LiveTimerIntentSupport.update(activity, state: state)
        return .result()
    }
}

struct ToggleRestTimerPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause umschalten"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        guard let activity = LiveTimerIntentSupport.activity() else { return .result() }
        var state = activity.content.state

        if state.isPaused {
            let remaining = max(0, state.pausedRemainingSeconds)
            state.isPaused = false
            state.pausedRemainingSeconds = 0
            state.restEndDate = remaining > 0
                ? Date().addingTimeInterval(TimeInterval(remaining))
                : nil
        } else {
            let remaining = LiveTimerIntentSupport.secondsRemaining(in: state)
            state.isPaused = true
            state.pausedRemainingSeconds = remaining
            state.restEndDate = nil
        }

        await LiveTimerIntentSupport.update(activity, state: state)
        return .result()
    }
}
