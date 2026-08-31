import Foundation

struct ExerciseDefinition: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let shortName: String
    let symbol: String

    var repsOnly: Bool {
        id.hasPrefix("pullup_") ||
        ["hyperextensions", "hanging_knee_raise", "plank"].contains(id)
    }

    var dumbbellIncrement: Bool {
        ["db_bench_flat", "goblet_squat", "rdl_dumbbell", "lateral_dumbbell"].contains(id)
    }
}

struct PlanSlotDefinition: Identifiable, Hashable {
    let id: Int
    let title: String
    let exercises: [ExerciseDefinition]
    let defaultExerciseID: String

    var defaultExercise: ExerciseDefinition {
        exercises.first(where: { $0.id == defaultExerciseID }) ?? exercises[0]
    }
}

enum ExerciseCatalog {
    static let slots: [PlanSlotDefinition] = [
        PlanSlotDefinition(
            id: 1,
            title: "Schrägbankdrücken",
            exercises: [
                .init(id: "db_bench_flat", name: "Kurzhantelschrägbankdrücken", shortName: "KH Schrägbank", symbol: "dumbbell.fill"),
                .init(id: "bb_bench_incline", name: "Langhantelschrägbankdrücken", shortName: "LH Schrägbank", symbol: "figure.strengthtraining.traditional"),
                .init(id: "bb_bench_flat", name: "Langhantelbankdrücken flach", shortName: "LH Bank flach", symbol: "figure.strengthtraining.traditional")
            ],
            defaultExerciseID: "db_bench_flat"
        ),
        PlanSlotDefinition(
            id: 2,
            title: "Squats",
            exercises: [
                .init(id: "barbell_squat", name: "Squats mit Langhantel", shortName: "LH Squats", symbol: "figure.strengthtraining.traditional"),
                .init(id: "leg_press", name: "Beinpresse", shortName: "Beinpresse", symbol: "figure.strengthtraining.functional"),
                .init(id: "goblet_squat", name: "Squats mit Kurzhantel", shortName: "KH Squats", symbol: "dumbbell.fill")
            ],
            defaultExerciseID: "barbell_squat"
        ),
        PlanSlotDefinition(
            id: 3,
            title: "Klimmzüge",
            exercises: [
                .init(id: "pullup_straight", name: "Klimmzüge – gerade Stange", shortName: "Standard", symbol: "figure.climbing"),
                .init(id: "pullup_wide_angle", name: "Klimmzüge – breiter schräger Griff", shortName: "Breit schräg", symbol: "figure.climbing"),
                .init(id: "pullup_narrow", name: "Klimmzüge – enger Griff", shortName: "Eng", symbol: "figure.climbing"),
                .init(id: "pullup_narrow_angle", name: "Klimmzüge – enger schräger Griff", shortName: "Eng schräg", symbol: "figure.climbing")
            ],
            defaultExerciseID: "pullup_straight"
        ),
        PlanSlotDefinition(
            id: 4,
            title: "Kreuzheben",
            exercises: [
                .init(id: "rdl_barbell", name: "Rumänisches Kreuzheben – Langhantel", shortName: "RDL Langhantel", symbol: "figure.strengthtraining.traditional"),
                .init(id: "rdl_dumbbell", name: "Rumänisches Kreuzheben – Kurzhanteln", shortName: "RDL Kurzhanteln", symbol: "dumbbell.fill")
            ],
            defaultExerciseID: "rdl_barbell"
        ),
        PlanSlotDefinition(
            id: 5,
            title: "Rudern",
            exercises: [
                .init(id: "row_narrow", name: "Enges Rudern", shortName: "Enges Rudern", symbol: "figure.rower"),
                .init(id: "row_wide", name: "Breites Rudern", shortName: "Breites Rudern", symbol: "figure.rower")
            ],
            defaultExerciseID: "row_narrow"
        ),
        PlanSlotDefinition(
            id: 6,
            title: "Seitheben",
            exercises: [
                .init(id: "lateral_dumbbell", name: "Seitheben – Kurzhanteln", shortName: "KH Seitheben", symbol: "dumbbell.fill"),
                .init(id: "lateral_cable", name: "Seitheben – Kabelzug", shortName: "Kabelzug", symbol: "figure.strengthtraining.functional")
            ],
            defaultExerciseID: "lateral_dumbbell"
        ),
        PlanSlotDefinition(
            id: 7,
            title: "Bonus",
            exercises: [
                .init(id: "hyperextensions", name: "Hyperextensions", shortName: "Hyperextensions", symbol: "figure.core.training"),
                .init(id: "cable_crunch", name: "Cable Crunch", shortName: "Cable Crunch", symbol: "figure.core.training"),
                .init(id: "hanging_knee_raise", name: "Hanging Knee Raises", shortName: "Knee Raises", symbol: "figure.core.training"),
                .init(id: "plank", name: "Plank", shortName: "Plank", symbol: "figure.core.training")
            ],
            defaultExerciseID: "hyperextensions"
        )
    ]

    static var allExercises: [ExerciseDefinition] { slots.flatMap(\.exercises) }

    static func exercise(id: String) -> ExerciseDefinition? {
        allExercises.first(where: { $0.id == id })
    }

    static func slot(id: Int) -> PlanSlotDefinition? {
        slots.first(where: { $0.id == id })
    }
}
