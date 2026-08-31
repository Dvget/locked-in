import Foundation
import CoreMotion
import SwiftData

enum CoreMotionStepError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Schrittzählung ist auf diesem iPhone nicht verfügbar."
        }
    }
}

enum CoreMotionStepSync {
    static let sourceID = "coremotion"
    private static let pedometer = CMPedometer()

    static var isAvailable: Bool {
        CMPedometer.isStepCountingAvailable()
    }

    static func query(from start: Date, to end: Date) async throws -> Int {
        guard isAvailable else {
            throw CoreMotionStepError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: data?.numberOfSteps.intValue ?? 0)
            }
        }
    }

    @MainActor
    static func syncLastSevenDays(modelContext: ModelContext) async throws -> Int {
        guard isAvailable else {
            throw CoreMotionStepError.unavailable
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let existing = try modelContext.fetch(FetchDescriptor<StepRecord>())

        for record in existing where record.source == sourceID {
            if record.date >= (calendar.date(byAdding: .day, value: -7, to: today) ?? .distantPast) {
                modelContext.delete(record)
            }
        }

        var importedDays = 0

        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                continue
            }

            let end = min(Date(), nextDay)
            let steps = try await query(from: day, to: end)

            modelContext.insert(
                StepRecord(
                    date: day,
                    steps: max(0, steps),
                    source: sourceID
                )
            )

            importedDays += 1
        }

        try modelContext.save()
        try? AutomaticBackup.backup(modelContext: modelContext)
        return importedDays
    }
}
