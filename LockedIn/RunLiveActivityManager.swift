import ActivityKit
import Foundation

struct RunLiveActivityControlRequest {
    let shouldPause: Bool
    let requestedAt: Date
}

@MainActor
enum RunLiveActivityManager {
    private static var activity: Activity<LockedInRunActivityAttributes>?
    private static var lastUpdateAt = Date.distantPast
    private static var lastHandledControlRevision = 0
    private static var mutationTask: Task<Void, Never>?

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
            lastHandledControlRevision = 0
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
        guard current.content.state.controlRevision <= lastHandledControlRevision else { return }
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
        enqueueMutation {
            guard current.content.state.controlRevision == revision,
                  revision <= lastHandledControlRevision else { return }
            await current.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    static func consumePauseRequest(runID: UUID) -> RunLiveActivityControlRequest? {
        guard let state = matchingActivity(runID: runID)?.content.state,
              state.controlRevision > lastHandledControlRevision else {
            return nil
        }
        lastHandledControlRevision = state.controlRevision
        return RunLiveActivityControlRequest(
            shouldPause: state.isPaused,
            requestedAt: state.controlDate ?? Date()
        )
    }

    static func end(runID: UUID) {
        guard let current = matchingActivity(runID: runID) else { return }
        activity = nil
        lastHandledControlRevision = 0
        enqueueMutation {
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
            controlRevision: controlRevision,
            controlDate: nil
        )
    }

    private static func enqueueMutation(
        _ operation: @escaping @MainActor () async -> Void
    ) {
        let previous = mutationTask
        mutationTask = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }
}
