import ActivityKit
import Foundation

struct LockedInRunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distanceMeters: Double
        var paceSecondsPerKm: Double?
        var isPaused: Bool
        var speechEnabled: Bool
        var finishRequested: Bool
        var activeDurationSeconds: Int
        var timerAnchor: Date
        var controlRevision: Int
        var controlDate: Date?

        init(
            distanceMeters: Double,
            paceSecondsPerKm: Double?,
            isPaused: Bool,
            speechEnabled: Bool,
            finishRequested: Bool = false,
            activeDurationSeconds: Int,
            timerAnchor: Date,
            controlRevision: Int,
            controlDate: Date?
        ) {
            self.distanceMeters = distanceMeters
            self.paceSecondsPerKm = paceSecondsPerKm
            self.isPaused = isPaused
            self.speechEnabled = speechEnabled
            self.finishRequested = finishRequested
            self.activeDurationSeconds = activeDurationSeconds
            self.timerAnchor = timerAnchor
            self.controlRevision = controlRevision
            self.controlDate = controlDate
        }

        private enum CodingKeys: String, CodingKey {
            case distanceMeters
            case paceSecondsPerKm
            case isPaused
            case speechEnabled
            case finishRequested
            case activeDurationSeconds
            case timerAnchor
            case controlRevision
            case controlDate
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
            paceSecondsPerKm = try container.decodeIfPresent(Double.self, forKey: .paceSecondsPerKm)
            isPaused = try container.decode(Bool.self, forKey: .isPaused)
            speechEnabled = try container.decodeIfPresent(Bool.self, forKey: .speechEnabled) ?? true
            finishRequested = try container.decodeIfPresent(Bool.self, forKey: .finishRequested) ?? false
            activeDurationSeconds = try container.decode(Int.self, forKey: .activeDurationSeconds)
            timerAnchor = try container.decode(Date.self, forKey: .timerAnchor)
            controlRevision = try container.decode(Int.self, forKey: .controlRevision)
            controlDate = try container.decodeIfPresent(Date.self, forKey: .controlDate)
        }
    }

    let runID: UUID
    let startedAt: Date
}
