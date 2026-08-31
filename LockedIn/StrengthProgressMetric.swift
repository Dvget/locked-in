import Foundation

enum StrengthProgressMetric {
    static let fallbackBodyWeightKg: Double = 90
    private static let contributionCap: Double = 20

    static func workoutProgress(
        workout: WorkoutRecord,
        workouts: [WorkoutRecord],
        sets: [SetRecord]
    ) -> Double? {
        guard workout.isCompleted, !workout.isHidden else { return nil }

        let currentSets = validSets(for: workout.id, sets: sets)
        let grouped = Dictionary(grouping: currentSets, by: \.exerciseID)
        var deltas: [Double] = []

        for (exerciseID, values) in grouped {
            guard let currentPerformance = performance(
                exerciseID: exerciseID,
                values: values,
                bodyWeightKg: workout.bodyWeightSnapshot
            ), currentPerformance > 0 else { continue }

            let previousCandidates = workouts
                .filter { candidate in
                    candidate.isCompleted &&
                    !candidate.isHidden &&
                    candidate.id != workout.id &&
                    candidate.startedAt < workout.startedAt
                }
                .sorted { $0.startedAt > $1.startedAt }

            guard let previousWorkout = previousCandidates.first(where: { candidate in
                sets.contains {
                    $0.workoutID == candidate.id &&
                    $0.exerciseID == exerciseID &&
                    $0.reps > 0
                }
            }) else { continue }

            let previousValues = validSets(for: previousWorkout.id, sets: sets)
                .filter { $0.exerciseID == exerciseID }

            guard let previousPerformance = performance(
                exerciseID: exerciseID,
                values: previousValues,
                bodyWeightKg: previousWorkout.bodyWeightSnapshot
            ), previousPerformance > 0 else { continue }

            let rawDelta = ((currentPerformance - previousPerformance) / previousPerformance) * 100
            deltas.append(min(contributionCap, max(-contributionCap, rawDelta)))
        }

        guard !deltas.isEmpty else { return nil }
        return deltas.reduce(0, +) / Double(deltas.count)
    }

    static func exerciseProgress(
        exerciseID: String,
        workout: WorkoutRecord,
        workouts: [WorkoutRecord],
        sets: [SetRecord]
    ) -> Double? {
        let currentValues = validSets(for: workout.id, sets: sets).filter { $0.exerciseID == exerciseID }
        guard let current = performance(exerciseID: exerciseID, values: currentValues, bodyWeightKg: workout.bodyWeightSnapshot), current > 0 else { return nil }

        let previous = workouts
            .filter { $0.isCompleted && !$0.isHidden && $0.startedAt < workout.startedAt }
            .sorted { $0.startedAt > $1.startedAt }
            .first { candidate in
                sets.contains { $0.workoutID == candidate.id && $0.exerciseID == exerciseID && $0.reps > 0 }
            }

        guard let previous else { return nil }
        let previousValues = validSets(for: previous.id, sets: sets).filter { $0.exerciseID == exerciseID }
        guard let previousPerformance = performance(exerciseID: exerciseID, values: previousValues, bodyWeightKg: previous.bodyWeightSnapshot), previousPerformance > 0 else { return nil }

        let raw = ((current - previousPerformance) / previousPerformance) * 100
        return min(contributionCap, max(-contributionCap, raw))
    }

    static func weeklyProgress(
        workouts: [WorkoutRecord],
        sets: [SetRecord],
        referenceDate: Date = Date()
    ) -> Double? {
        let calendar = Calendar.current
        let thisWeek = workouts
            .filter {
                $0.isCompleted &&
                !$0.isHidden &&
                calendar.isDate($0.startedAt, equalTo: referenceDate, toGranularity: .weekOfYear)
            }
            .compactMap { workoutProgress(workout: $0, workouts: workouts, sets: sets) }

        guard !thisWeek.isEmpty else { return nil }
        return thisWeek.reduce(0, +) / Double(thisWeek.count)
    }

    static func text(_ value: Double?) -> String {
        guard let value else { return "—" }
        if abs(value) < 0.05 { return "0,0 %" }
        return String(format: "%+.1f %%", value)
            .replacingOccurrences(of: ".", with: ",")
    }

    private static func validSets(for workoutID: UUID, sets: [SetRecord]) -> [SetRecord] {
        sets.filter { $0.workoutID == workoutID && $0.reps > 0 }
    }

    private static func performance(
        exerciseID: String,
        values: [SetRecord],
        bodyWeightKg: Double
    ) -> Double? {
        guard !values.isEmpty else { return nil }
        let exercise = ExerciseCatalog.exercise(id: exerciseID)
        let isBodyweight = exercise?.repsOnly ?? false

        return values.compactMap { set -> Double? in
            guard set.reps > 0 else { return nil }
            let load: Double
            if isBodyweight {
                load = max(1, bodyWeightKg + max(0, set.weight))
            } else {
                guard set.weight > 0 else { return nil }
                load = set.weight
            }
            return load * (1 + Double(set.reps) / 30.0)
        }.max()
    }
}
