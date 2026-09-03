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
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
