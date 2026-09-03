import Foundation
import OSLog
import SwiftData

@MainActor
enum PolarRunSync {
    private static let endpoint = URL(string: "https://locked-in-polar.dvget.workers.dev/runs")!
    private static let logger = Logger(subsystem: "app.lockedin.tracker", category: "PolarSync")

    @discardableResult
    static func sync(modelContext: ModelContext) async throws -> Int {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try PolarRunsResponse.decode(data)
        guard payload.ok else { throw URLError(.cannotParseResponse) }

        let existing = try modelContext.fetch(FetchDescriptor<RunRecord>())
        let knownPolarIds = Set(existing.compactMap { record -> String? in
            guard record.source.lowercased() == "polar" else { return nil }
            return record.externalId
        })
        let unseen = PolarRunPayload.unseen(
            payload.runs,
            existingPolarExternalIds: knownPolarIds
        )

        var insertedRecords: [RunRecord] = []
        for run in unseen {
            guard let startTime = run.parsedStartTime,
                  run.distanceKm > 0,
                  run.durationSeconds > 0 else {
                logger.warning("Polar run skipped because required values are invalid")
                continue
            }

            let record = RunRecord(
                date: startTime,
                distanceKm: run.distanceKm,
                durationSeconds: run.durationSeconds,
                source: "polar",
                externalId: run.externalId,
                startTime: startTime,
                importedPaceSecondsPerKm: run.paceSecondsPerKm,
                sportId: run.sportId,
                sourceName: run.name
            )
            modelContext.insert(record)
            insertedRecords.append(record)
        }

        if !insertedRecords.isEmpty {
            do {
                try modelContext.save()
            } catch {
                insertedRecords.forEach { modelContext.delete($0) }
                throw error
            }
            try? AutomaticBackup.backup(modelContext: modelContext)
        }
        return insertedRecords.count
    }
}
