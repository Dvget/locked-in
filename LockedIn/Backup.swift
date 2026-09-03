import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupPayload: Codable {
    let exportedAt: Date
    let workouts: [BackupWorkout]
    let sets: [BackupSet]
    let runs: [BackupRun]?
    let steps: [BackupStep]?
    let weights: [BackupWeight]?
}

struct BackupRun: Codable {
    let id: UUID
    let date: Date
    let distanceKm: Double
    let durationSeconds: Double
    let source: String
    let isHidden: Bool?
    let externalId: String?
    let startTime: Date?
    let importedPaceSecondsPerKm: Double?
    let sportId: Int?
    let sourceName: String?
}

struct BackupStep: Codable {
    let id: UUID
    let date: Date
    let steps: Int
    let source: String
}

struct BackupWeight: Codable {
    let id: UUID
    let date: Date
    let weightKg: Double
    let source: String
    let isHidden: Bool?
}

struct BackupWorkout: Codable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let isCompleted: Bool
    let isHidden: Bool?
    let bodyWeightSnapshot: Double?
}

struct BackupSet: Codable {
    let id: UUID
    let workoutID: UUID
    let exerciseID: String
    let exerciseName: String
    let planSlot: Int
    let setNumber: Int
    let weight: Double
    let reps: Int
    let rir: Int?
    let completedAt: Date
}

struct LockedInBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
enum BackupDatabase {
    static func payload(modelContext: ModelContext) throws -> BackupPayload {
        let workouts = try modelContext.fetch(FetchDescriptor<WorkoutRecord>())
        let sets = try modelContext.fetch(FetchDescriptor<SetRecord>())
        let runs = try modelContext.fetch(FetchDescriptor<RunRecord>())
        let steps = try modelContext.fetch(FetchDescriptor<StepRecord>())
        let weights = try modelContext.fetch(FetchDescriptor<WeightRecord>())
        return BackupPayload(
            exportedAt: Date(),
            workouts: workouts.map {
                BackupWorkout(
                    id: $0.id,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    isCompleted: $0.isCompleted,
                    isHidden: $0.isHidden,
                    bodyWeightSnapshot: $0.bodyWeightSnapshot
                )
            },
            sets: sets.map {
                BackupSet(id: $0.id, workoutID: $0.workoutID, exerciseID: $0.exerciseID, exerciseName: $0.exerciseName, planSlot: $0.planSlot, setNumber: $0.setNumber, weight: $0.weight, reps: $0.reps, rir: $0.rir, completedAt: $0.completedAt)
            },
            runs: runs.map {
                BackupRun(
                    id: $0.id,
                    date: $0.date,
                    distanceKm: $0.distanceKm,
                    durationSeconds: $0.durationSeconds,
                    source: $0.source,
                    isHidden: $0.isHidden,
                    externalId: $0.externalId,
                    startTime: $0.startTime,
                    importedPaceSecondsPerKm: $0.importedPaceSecondsPerKm,
                    sportId: $0.sportId,
                    sourceName: $0.sourceName
                )
            },
            steps: steps.map {
                BackupStep(id: $0.id, date: $0.date, steps: $0.steps, source: $0.source)
            },
            weights: weights.map {
                BackupWeight(id: $0.id, date: $0.date, weightKg: $0.weightKg, source: $0.source, isHidden: $0.isHidden)
            }
        )
    }

    static func encode(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    static func decode(_ data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupPayload.self, from: data)
    }

    static func replaceDatabase(with payload: BackupPayload, modelContext: ModelContext) throws {
        let existingSets = try modelContext.fetch(FetchDescriptor<SetRecord>())
        existingSets.forEach { modelContext.delete($0) }

        let existingWorkouts = try modelContext.fetch(FetchDescriptor<WorkoutRecord>())
        existingWorkouts.forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<RunRecord>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<StepRecord>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<WeightRecord>()).forEach { modelContext.delete($0) }

        for item in payload.workouts {
            let workout = WorkoutRecord(
                id: item.id,
                startedAt: item.startedAt,
                isHidden: item.isHidden ?? false,
                bodyWeightSnapshot: item.bodyWeightSnapshot ?? StrengthProgressMetric.fallbackBodyWeightKg
            )
            workout.endedAt = item.endedAt
            workout.isCompleted = item.isCompleted
            modelContext.insert(workout)
        }

        for item in payload.sets {
            modelContext.insert(SetRecord(
                id: item.id,
                workoutID: item.workoutID,
                exerciseID: item.exerciseID,
                exerciseName: item.exerciseName,
                planSlot: item.planSlot,
                setNumber: item.setNumber,
                weight: item.weight,
                reps: item.reps,
                rir: item.rir,
                completedAt: item.completedAt
            ))
        }

        for item in payload.runs ?? [] {
            modelContext.insert(RunRecord(
                id: item.id,
                date: item.date,
                distanceKm: item.distanceKm,
                durationSeconds: item.durationSeconds,
                source: item.source,
                isHidden: item.isHidden ?? false,
                externalId: item.externalId,
                startTime: item.startTime,
                importedPaceSecondsPerKm: item.importedPaceSecondsPerKm,
                sportId: item.sportId,
                sourceName: item.sourceName
            ))
        }
        for item in payload.steps ?? [] {
            modelContext.insert(StepRecord(id: item.id, date: item.date, steps: item.steps, source: item.source))
        }
        for item in payload.weights ?? [] {
            modelContext.insert(WeightRecord(id: item.id, date: item.date, weightKg: item.weightKg, source: item.source, isHidden: item.isHidden ?? false))
        }

        try modelContext.save()
    }
}
