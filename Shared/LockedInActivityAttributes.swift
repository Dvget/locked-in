import Foundation
import ActivityKit

struct LockedInActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var restEndDate: Date?
        var isPaused: Bool
        var pausedRemainingSeconds: Int

        init(restEndDate: Date?, isPaused: Bool = false, pausedRemainingSeconds: Int = 0) {
            self.restEndDate = restEndDate
            self.isPaused = isPaused
            self.pausedRemainingSeconds = pausedRemainingSeconds
        }
    }

    var workoutID: UUID
    var startedAt: Date
}
