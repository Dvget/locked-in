import ActivityKit
import AppIntents
import Foundation

struct ToggleRunPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Lauf pausieren oder fortsetzen"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        guard let activity = Activity<LockedInRunActivityAttributes>.activities.max(by: {
            $0.attributes.startedAt < $1.attributes.startedAt
        }) else {
            return .result()
        }

        var state = activity.content.state
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
