import Foundation
import SwiftData

@MainActor
enum SeedData {
    private static let key = "lockedIn.seed.v02.inserted"

    static func insertIfNeeded(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 29
        components.hour = 18
        let startedAt = Calendar.current.date(from: components) ?? Date().addingTimeInterval(-86400)

        let workout = WorkoutRecord(startedAt: startedAt)
        workout.endedAt = startedAt.addingTimeInterval(60 * 58)
        workout.isCompleted = true
        modelContext.insert(workout)

        let rows: [(String, String, Int, [(Double, Int)])] = [
            ("db_bench_flat", "Kurzhantelschrägbankdrücken", 1, [(28,8),(28,6),(28,5)]),
            ("barbell_squat", "Squats mit Langhantel", 2, [(50,8),(50,8),(50,8)]),
            ("pullup_straight", "Klimmzüge – gerade Stange", 3, [(0,4),(0,4),(0,3)]),
            ("rdl_barbell", "Rumänisches Kreuzheben – Langhantel", 4, [(50,8),(50,8),(50,6)]),
            ("row_narrow", "Enges Rudern", 5, [(70,8),(70,7),(70,6)]),
            ("lateral_cable", "Seitheben – Kabelzug", 6, [(5,16),(5,16)])
        ]

        for row in rows {
            for (index, value) in row.3.enumerated() {
                let set = SetRecord(
                    workoutID: workout.id,
                    exerciseID: row.0,
                    exerciseName: row.1,
                    planSlot: row.2,
                    setNumber: index + 1,
                    weight: value.0,
                    reps: value.1,
                    rir: nil,
                    completedAt: startedAt.addingTimeInterval(Double((row.2 * 10 + index) * 60))
                )
                modelContext.insert(set)
            }
        }

        do {
            try modelContext.save()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            // Try again on a later launch if the initial seed could not be saved.
        }
    }
}
