import Foundation
import SwiftData

@Model
final class RunRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    var distanceKm: Double = 0
    var durationSeconds: Double = 0
    var source: String = "manual"
    var isHidden: Bool = false
    var externalId: String? = nil
    var startTime: Date? = nil
    var importedPaceSecondsPerKm: Double? = nil
    var sportId: Int? = nil
    var sourceName: String? = nil

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        distanceKm: Double,
        durationSeconds: Double,
        source: String = "manual",
        isHidden: Bool = false,
        externalId: String? = nil,
        startTime: Date? = nil,
        importedPaceSecondsPerKm: Double? = nil,
        sportId: Int? = nil,
        sourceName: String? = nil
    ) {
        self.id = id
        self.date = date
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.source = source
        self.isHidden = isHidden
        self.externalId = externalId
        self.startTime = startTime
        self.importedPaceSecondsPerKm = importedPaceSecondsPerKm
        self.sportId = sportId
        self.sourceName = sourceName
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
    var isHidden: Bool = false

    init(id: UUID = UUID(), date: Date = Date(), weightKg: Double, source: String = "manual", isHidden: Bool = false) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.source = source
        self.isHidden = isHidden
    }
}
