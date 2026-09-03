import ActivityKit
import Foundation

struct LockedInRunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distanceMeters: Double
        var paceSecondsPerKm: Double?
        var isPaused: Bool
        var activeDurationSeconds: Int
        var timerAnchor: Date
        var controlRevision: Int
    }

    let runID: UUID
    let startedAt: Date
}
