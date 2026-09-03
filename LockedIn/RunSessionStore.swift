import Foundation

enum RunSessionStore {
    private static let fileName = "locked-in-active-run.json"

    private static var fileURL: URL? {
        guard let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }

    static func save(_ checkpoint: RunSessionCheckpoint) throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try RunArchiveCodec.encode(checkpoint)
        try data.write(to: fileURL, options: .atomic)
    }

    static func load(now: Date = Date()) -> RunSessionCheckpoint? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let checkpoint = try? RunArchiveCodec.decode(RunSessionCheckpoint.self, from: data),
              now.timeIntervalSince(checkpoint.savedAt) < 24 * 60 * 60,
              [.recording, .paused].contains(checkpoint.clock.phase) else {
            return nil
        }
        return checkpoint
    }

    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
