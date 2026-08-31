import Foundation
import SwiftData

@MainActor
enum AutomaticBackup {
    private static let bookmarkKey = "lockedIn.backupFolderBookmark"
    private static let folderNameKey = "lockedIn.backupFolderName"

    static var hasBackupFolder: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    static var backupFolderName: String? {
        UserDefaults.standard.string(forKey: folderNameKey)
    }

    static func saveFolderBookmark(_ url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: [.nameKey, .isDirectoryKey],
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: folderNameKey)
    }

    static func clearFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: folderNameKey)
    }

    static func backup(modelContext: ModelContext) throws {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }

        var stale = false
        let folder = try URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )

        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: folder.path) else {
            clearFolder()
            throw CocoaError(.fileNoSuchFile)
        }

        if stale {
            try saveFolderBookmark(folder)
        }

        let json = try BackupDatabase.encode(BackupDatabase.payload(modelContext: modelContext))
        try json.write(to: folder.appendingPathComponent("LockedIn-Latest.json"), options: .atomic)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let snapshot = folder.appendingPathComponent("LockedIn-\(formatter.string(from: Date())).json")
        try json.write(to: snapshot, options: .atomic)
        try trimSnapshots(in: folder, keeping: 7)
    }

    private static func trimSnapshots(in folder: URL, keeping count: Int) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter {
            $0.lastPathComponent.hasPrefix("LockedIn-") &&
            $0.lastPathComponent != "LockedIn-Latest.json" &&
            $0.pathExtension == "json"
        }

        let sorted = try files.sorted {
            let a = try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let b = try $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return a > b
        }

        for file in sorted.dropFirst(count) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
