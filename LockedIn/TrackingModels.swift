import Foundation
import SwiftData

@Model
final class RunRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var distanceKm: Double = 0
    var durationSeconds: Double = 0
    var source: String = "manual"

    init(id: UUID = UUID(), date: Date = Date(), distanceKm: Double, durationSeconds: Double, source: String = "manual") {
        self.id = id
        self.date = date
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.source = source
    }

    var paceSecondsPerKm: Double {
        guard distanceKm > 0 else { return 0 }
        return durationSeconds / distanceKm
    }
}

@Model
final class StepRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var steps: Int = 0
    var source: String = "manual"

    init(id: UUID = UUID(), date: Date = Date(), steps: Int, source: String = "manual") {
        self.id = id
        self.date = date
        self.steps = steps
        self.source = source
    }
}

@Model
final class WeightRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var weightKg: Double = 90
    var source: String = "manual"

    init(id: UUID = UUID(), date: Date = Date(), weightKg: Double, source: String = "manual") {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.source = source
    }
}
