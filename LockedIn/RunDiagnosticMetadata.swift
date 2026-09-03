import Foundation

struct RunDiagnosticMetadata: Codable, Equatable {
    let appVersion: String
    let buildNumber: String
    let operatingSystem: String
    let deviceModel: String
    let recordedAt: Date
}

struct NativeRunArchive: Codable, Equatable {
    let algorithmVersion: String?
    let route: [RunLocationDecision]?
    let splits: [RunSplit]?
    let configuration: RunTrackingConfiguration?
    let metadata: RunDiagnosticMetadata?

    init(
        algorithmVersion: String? = nil,
        route: [RunLocationDecision]? = nil,
        splits: [RunSplit]? = nil,
        configuration: RunTrackingConfiguration? = nil,
        metadata: RunDiagnosticMetadata? = nil
    ) {
        self.algorithmVersion = algorithmVersion
        self.route = route
        self.splits = splits
        self.configuration = configuration
        self.metadata = metadata
    }
}

enum RunArchiveCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }

            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Ungültiger Zeitstempel: \(value)"
            )
        }
        return try decoder.decode(type, from: data)
    }
}
