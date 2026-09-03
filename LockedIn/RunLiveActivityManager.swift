import ActivityKit
import Foundation

@MainActor
enum RunLiveActivityManager {
    private static var activity: Activity<LockedInRunActivityAttributes>?
    private static var lastUpdateAt = Date.distantPast
    private static var lastHandledControlRevision = 0

    static func start(runID: UUID, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = contentState(
            distanceMeters: 0,
            paceSecondsPerKm: nil,
            isPaused: false,
            activeDurationSeconds: 0,
            controlRevision: 0
        )

        if let existing = matchingActivity(runID: runID) {
            activity = existing
            lastHandledControlRevision = existing.content.state.controlRevision
            Task { await existing.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }

        do {
            activity = try Activity.request(
                attributes: LockedInRunActivityAttributes(runID: runID, startedAt: startedAt),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            lastHandledControlRevision = 0
        } catch {
            activity = nil
        }
    }

    static func update(
        runID: UUID,
        distanceMeters: Double,
        paceSecondsPerKm: Double?,
        isPaused: Bool,
        activeDurationSeconds: TimeInterval,
        force: Bool = false
    ) {
        guard let current = matchingActivity(runID: runID) else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastUpdateAt) >= 5 else { return }
        lastUpdateAt = now
        let revision = current.content.state.controlRevision
        let state = contentState(
            distanceMeters: distanceMeters,
            paceSecondsPerKm: paceSecondsPerKm,
            isPaused: isPaused,
            activeDurationSeconds: Int(activeDurationSeconds.rounded(.down)),
            controlRevision: revision
        )
        Task { await current.update(ActivityContent(state: state, staleDate: nil)) }
    }

    static func consumePauseRequest(runID: UUID) -> Bool? {
        guard let state = matchingActivity(runID: runID)?.content.state,
              state.controlRevision > lastHandledControlRevision else {
            return nil
        }
        lastHandledControlRevision = state.controlRevision
        return state.isPaused
    }

    static func end(runID: UUID) {
        guard let current = matchingActivity(runID: runID) else { return }
        activity = nil
        lastHandledControlRevision = 0
        Task {
            await current.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func matchingActivity(runID: UUID) -> Activity<LockedInRunActivityAttributes>? {
        if let activity, activity.attributes.runID == runID {
            return activity
        }
        let restored = Activity<LockedInRunActivityAttributes>.activities.first {
            $0.attributes.runID == runID
        }
        activity = restored
        return restored
    }

    private static func contentState(
        distanceMeters: Double,
        paceSecondsPerKm: Double?,
        isPaused: Bool,
        activeDurationSeconds: Int,
        controlRevision: Int
    ) -> LockedInRunActivityAttributes.ContentState {
        let now = Date()
        return LockedInRunActivityAttributes.ContentState(
            distanceMeters: distanceMeters,
            paceSecondsPerKm: paceSecondsPerKm,
            isPaused: isPaused,
            activeDurationSeconds: max(0, activeDurationSeconds),
            timerAnchor: now.addingTimeInterval(-TimeInterval(max(0, activeDurationSeconds))),
            controlRevision: controlRevision
        )
    }
}
