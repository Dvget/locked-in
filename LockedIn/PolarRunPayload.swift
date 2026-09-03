import Foundation

struct PolarRunsResponse: Decodable {
    let ok: Bool
    let source: String
    let count: Int
    let runs: [PolarRunPayload]

    static func decode(_ data: Data) throws -> PolarRunsResponse {
        try JSONDecoder().decode(PolarRunsResponse.self, from: data)
    }
}

struct PolarRunPayload: Decodable {
    let externalId: String
    let source: String
    let date: String
    let startTime: String
    let distanceKm: Double
    let durationSeconds: Double
    let paceSecondsPerKm: Double
    let sportId: Int?
    let name: String?

    var parsedStartTime: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        if let result = formatter.date(from: startTime) { return result }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        return formatter.date(from: startTime)
    }

    static func unseen(
        _ candidates: [PolarRunPayload],
        existingPolarExternalIds: Set<String>
    ) -> [PolarRunPayload] {
        var known = existingPolarExternalIds
        return candidates.filter { candidate in
            guard candidate.source.lowercased() == "polar",
                  !candidate.externalId.isEmpty,
                  !known.contains(candidate.externalId) else {
                return false
            }
            known.insert(candidate.externalId)
            return true
        }
    }
}
