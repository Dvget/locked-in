import Foundation
import SwiftData

@Model
final class WorkoutRecord {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date? = nil
    var isCompleted: Bool = false
    var isHidden: Bool = false
    var bodyWeightSnapshot: Double = StrengthProgressMetric.fallbackBodyWeightKg

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        isHidden: Bool = false,
        bodyWeightSnapshot: Double = StrengthProgressMetric.fallbackBodyWeightKg
    ) {
        self.id = id
        self.startedAt = startedAt
        self.isHidden = isHidden
        self.bodyWeightSnapshot = bodyWeightSnapshot
    }

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

@Model
final class SetRecord {
    var id: UUID = UUID()
    var workoutID: UUID = UUID()
    var exerciseID: String = ""
    var exerciseName: String = ""
    var planSlot: Int = 0
    var setNumber: Int = 1
    var weight: Double = 0
    var reps: Int = 0
    var rir: Int? = nil
    var completedAt: Date = Date()

    init(
        id: UUID = UUID(),
        workoutID: UUID,
        exerciseID: String,
        exerciseName: String,
        planSlot: Int,
        setNumber: Int,
        weight: Double,
        reps: Int,
        rir: Int? = nil,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.workoutID = workoutID
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.planSlot = planSlot
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.rir = rir
        self.completedAt = completedAt
    }

    var volume: Double { weight * Double(reps) }
}
