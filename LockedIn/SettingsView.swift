import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("heavyRestSeconds") private var heavyRestSeconds: Double = 150
    @AppStorage("lightRestSeconds") private var lightRestSeconds: Double = 120
    @AppStorage("coreMotionStepsEnabled") private var coreMotionStepsEnabled = false
    @AppStorage("lastAutomaticStepSync") private var lastAutomaticStepSync: Double = 0

    @State private var stepSyncStatus = ""
    @State private var isSyncingSteps = false
    @State private var exportDocument: LockedInBackupDocument?
    @State private var showExporter = false
    @State private var showFolderPicker = false
    @State private var showImporter = false
    @State private var backupStatus = ""
    @State private var pendingImport: BackupPayload?
    @State private var showImportConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Training") {
                    Stepper(value: $heavyRestSeconds, in: 60...300, step: 15) {
                        LabeledContent("Pause Übungen 1–4") {
                            Text("\(Int(heavyRestSeconds)) Sek.")
                        }
                    }

                    Stepper(value: $lightRestSeconds, in: 60...300, step: 15) {
                        LabeledContent("Pause Übungen 5–7") {
                            Text("\(Int(lightRestSeconds)) Sek.")
                        }
                    }
                }

                Section("Steps") {
                    Button {
                        Task { await syncSteps() }
                    } label: {
                        Label(
                            isSyncingSteps ? "Steps werden synchronisiert …" : "iPhone-Schritte synchronisieren",
                            systemImage: "shoeprints.fill"
                        )
                    }
                    .disabled(isSyncingSteps || !CoreMotionStepSync.isAvailable)

                    Text("Die iPhone-Schrittzählung kommt direkt aus Core Motion und benötigt kein Apple Health. Nach der ersten Freigabe aktualisiert LOCKED IN die Steps automatisch beim Öffnen bzw. Zurückkehren in die App und während längerer Nutzung ungefähr alle 30 Minuten.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !stepSyncStatus.isEmpty {
                        Text(stepSyncStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Automatisches Backup") {
                    Text(backupDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        showFolderPicker = true
                    } label: {
                        Label(
                            AutomaticBackup.hasBackupFolder ? "Backup-Ordner ändern" : "iCloud-Backup-Ordner wählen",
                            systemImage: "folder.badge.plus"
                        )
                    }

                    if AutomaticBackup.hasBackupFolder {
                        Button {
                            createBackupNow()
                        } label: {
                            Label("Backup jetzt erstellen", systemImage: "icloud.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            AutomaticBackup.clearFolder()
                            backupStatus = "Gespeicherter Backup-Ordner wurde entfernt."
                        } label: {
                            Label("Backup-Ordner vergessen", systemImage: "xmark.circle")
                        }
                    }

                    if !backupStatus.isEmpty {
                        Text(backupStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Running-Testphase") {
                    Button {
                        prepareExport()
                    } label: {
                        Label("Tracking-Daten exportieren", systemImage: "square.and.arrow.up")
                    }

                    Text("Exportiert alle Trainings- und Laufdaten einschließlich der GPS-Rohdaten nativer LOCKED-IN-Läufe. Damit lassen sich Messabweichungen später nachvollziehen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Datenbank") {

                    Button {
                        showImporter = true
                    } label: {
                        Label("JSON-Backup importieren", systemImage: "square.and.arrow.down")
                    }

                    Text("Beim Import wird der aktuelle Datenbestand durch das gewählte LOCKED-IN-Backup ersetzt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("LOCKED IN") {
                    LabeledContent("Version", value: "0.7.0")
                    Text("Trainingsdaten liegen primär lokal in SwiftData. JSON-Backups dienen als zusätzliche Sicherung und können wieder importiert werden.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Einstellungen")
        }

        .sheet(isPresented: $showFolderPicker) {
            FolderPicker { url in
                showFolderPicker = false
                guard let url else { return }
                do {
                    try AutomaticBackup.saveFolderBookmark(url)
                    backupStatus = "Backup-Ordner „\(url.lastPathComponent)“ gespeichert."
                    try AutomaticBackup.backup(modelContext: modelContext)
                    backupStatus = "Backup-Ordner gespeichert und Test-Backup erstellt."
                } catch {
                    AutomaticBackup.clearFolder()
                    backupStatus = "Ordner konnte nicht gespeichert werden: \(error.localizedDescription)"
                }
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            loadImport(result)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: defaultFilename
        ) { result in
            if case .failure(let error) = result {
                backupStatus = "Export fehlgeschlagen: \(error.localizedDescription)"
            }
        }
        .alert("Backup importieren?", isPresented: $showImportConfirmation) {
            Button("Abbrechen", role: .cancel) {
                pendingImport = nil
            }
            Button("Daten ersetzen", role: .destructive) {
                importPendingBackup()
            }
        } message: {
            Text("Alle aktuell gespeicherten Trainings werden durch die Daten aus dem Backup ersetzt.")
        }
    }

    @MainActor
    private func syncSteps() async {
        isSyncingSteps = true
        defer { isSyncingSteps = false }

        do {
            let days = try await CoreMotionStepSync.syncLastSevenDays(modelContext: modelContext)
            coreMotionStepsEnabled = true
            lastAutomaticStepSync = Date().timeIntervalSince1970
            stepSyncStatus = "\(days) Tage aus der iPhone-Schrittzählung synchronisiert. Automatische Aktualisierung ist aktiv."
        } catch {
            stepSyncStatus = "Steps konnten nicht synchronisiert werden: \(error.localizedDescription)"
        }
    }

    private var backupDescription: String {
        if let name = AutomaticBackup.backupFolderName {
            return "Aktiver Ordner: \(name). Nach jedem abgeschlossenen Training wird LockedIn-Latest.json aktualisiert; zusätzlich bleiben die letzten 7 Stände erhalten."
        }
        return "Wähle einmal einen Ordner in iCloud Drive. Danach sichert LOCKED IN nach jedem abgeschlossenen Training automatisch."
    }

    private var defaultFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "LockedIn-Tracking-\(formatter.string(from: Date()))"
    }

    private func createBackupNow() {
        do {
            try AutomaticBackup.backup(modelContext: modelContext)
            backupStatus = "Backup erfolgreich gespeichert."
        } catch {
            backupStatus = "Backup fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func prepareExport() {
        do {
            let payload = try BackupDatabase.payload(modelContext: modelContext)
            exportDocument = LockedInBackupDocument(data: try BackupDatabase.encode(payload))
            showExporter = true
        } catch {
            backupStatus = "Export konnte nicht vorbereitet werden: \(error.localizedDescription)"
        }
    }

    private func loadImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            pendingImport = try BackupDatabase.decode(data)
            showImportConfirmation = true
        } catch {
            backupStatus = "Backup konnte nicht gelesen werden: \(error.localizedDescription)"
        }
    }

    private func importPendingBackup() {
        guard let payload = pendingImport else { return }
        do {
            try BackupDatabase.replaceDatabase(with: payload, modelContext: modelContext)
            pendingImport = nil
            backupStatus = "Backup erfolgreich importiert."
            try? AutomaticBackup.backup(modelContext: modelContext)
        } catch {
            backupStatus = "Import fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

private struct FolderPicker: UIViewControllerRepresentable {
    let completion: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (URL?) -> Void

        init(completion: @escaping (URL?) -> Void) {
            self.completion = completion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(nil)
        }
    }
}
