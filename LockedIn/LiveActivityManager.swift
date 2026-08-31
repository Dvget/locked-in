import Foundation
import ActivityKit

@MainActor
enum LiveActivityManager {
    private static var activity: Activity<LockedInActivityAttributes>?

    static func startOrUpdate(
        workoutID: UUID,
        startedAt: Date,
        exerciseName: String,
        restEndDate: Date?
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = LockedInActivityAttributes.ContentState(
            restEndDate: restEndDate,
            isPaused: false,
            pausedRemainingSeconds: 0
        )

        if let current = activity {
            Task {
                await current.update(ActivityContent(state: state, staleDate: restEndDate))
            }
            return
        }

        let attributes = LockedInActivityAttributes(
            workoutID: workoutID,
            startedAt: startedAt
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: restEndDate),
                pushType: nil
            )
        } catch {
            // Live Activities are optional; the workout remains fully functional without one.
        }
    }

    static func timerState(workoutID: UUID) -> LockedInActivityAttributes.ContentState? {
        if let current = activity, current.attributes.workoutID == workoutID {
            return current.content.state
        }
        return Activity<LockedInActivityAttributes>.activities
            .first(where: { $0.attributes.workoutID == workoutID })?
            .content.state
    }

    static func end() {
        guard let current = activity else { return }
        activity = nil
        Task {
            await current.end(nil, dismissalPolicy: .immediate)
        }
    }
}
