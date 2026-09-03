import SwiftData
import SwiftUI

@MainActor
struct ActiveRunView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var engine: RunTrackingEngine
    let onComplete: () -> Void

    @State private var showStopConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var saveError: String?
    @State private var pendingPayload: RunFinishedPayload?
    @State private var pendingRecord: RunRecord?

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 4) {
                Text(engine.phase == .paused ? "PAUSIERT" : "LAUFZEIT")
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(engine.phase == .paused ? Color.yellow : Color.secondary)
                Text(formatDuration(engine.activeDurationSeconds))
                    .font(.system(size: 62, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(engine.phase == .paused ? Color.yellow : Color.white)
                    .minimumScaleFactor(0.75)
            }
            .padding(.top, 26)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    metricCard(
                        title: "DISTANZ",
                        value: String(format: "%.2f", engine.metrics.distanceMeters / 1_000),
                        unit: "km",
                        accent: true
                    )
                    metricCard(
                        title: "AKTUELLE PACE",
                        value: formatPace(engine.currentPaceSecondsPerKm),
                        unit: "min/km",
                        accent: false
                    )
                }

                HStack(spacing: 12) {
                    metricCard(
                        title: "Ø PACE",
                        value: formatPace(engine.averagePaceSecondsPerKm),
                        unit: "min/km",
                        accent: false
                    )
                    metricCard(
                        title: "HÖHENMETER",
                        value: String(format: "%.0f", engine.metrics.elevationGainMeters),
                        unit: "m aufwärts",
                        accent: false
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)

            HStack(spacing: 7) {
                Circle()
                    .fill(engine.gpsReady ? Color.lockedGreen : Color.yellow)
                    .frame(width: 7, height: 7)
                Text(engine.gpsReady ? "GPS-Aufzeichnung aktiv" : "GPS-Signal unterbrochen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)

            Spacer(minLength: 20)

            HStack(spacing: 12) {
                Button {
                    if engine.phase == .paused {
                        _ = engine.resume()
                    } else {
                        _ = engine.pause()
                    }
                } label: {
                    Label(
                        engine.phase == .paused ? "Fortsetzen" : "Pause",
                        systemImage: engine.phase == .paused ? "play.fill" : "pause.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                }
                .buttonStyle(LockedActionButtonStyle(prominent: engine.phase == .paused))
                .accessibilityIdentifier("run-pause")

                Button {
                    showStopConfirmation = true
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(Color.red.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("run-stop")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .background(
            LinearGradient(
                colors: [Color.lockedGreen.opacity(0.06), Color.black, Color.black],
                startPoint: .topTrailing,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
        .confirmationDialog(
            "Lauf beenden?",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Beenden und speichern") { stopAndSave() }
            Button("Weiterlaufen", role: .cancel) {}
            Button("Lauf verwerfen", role: .destructive) {
                showDiscardConfirmation = true
            }
        } message: {
            Text("Der Lauf wird mit allen GPS- und Diagnosedaten gespeichert.")
        }
        .alert("Lauf wirklich verwerfen?", isPresented: $showDiscardConfirmation) {
            Button("Abbrechen", role: .cancel) {}
            Button("Verwerfen", role: .destructive) {
                engine.discard()
                onComplete()
            }
        } message: {
            Text("Die aufgezeichneten Daten dieses Laufs gehen verloren.")
        }
        .alert(
            "Lauf konnte nicht gespeichert werden",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("Erneut versuchen") { savePendingRun() }
            Button("Schließen", role: .cancel) {}
        } message: {
            Text(saveError ?? "Unbekannter Fehler")
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "figure.run")
                    .foregroundStyle(Color.lockedGreen)
                Text("RUNNING")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.lockedGreen)
            }

            Spacer()

            Button(action: engine.toggleSpeech) {
                Image(systemName: engine.speechEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.headline)
                    .foregroundStyle(engine.speechEnabled ? Color.lockedGreen : Color.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityLabel(engine.speechEnabled ? "Kilometeransagen ausschalten" : "Kilometeransagen einschalten")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private func metricCard(
        title: String,
        value: String,
        unit: String,
        accent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent ? Color.lockedGreen : Color.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(15)
        .background(Color.lockedCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent ? Color.lockedGreen.opacity(0.24) : Color.lockedBorder, lineWidth: 1)
        }
    }

    private func stopAndSave() {
        do {
            if pendingPayload == nil {
                pendingPayload = try engine.finish()
            }
            savePendingRun()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func savePendingRun() {
        guard let payload = pendingPayload else { return }
        do {
            let record: RunRecord
            if let pendingRecord {
                record = pendingRecord
            } else {
                record = RunRecord(
                    id: payload.runID,
                    date: payload.startedAt,
                    distanceKm: payload.metrics.distanceMeters / 1_000,
                    durationSeconds: payload.activeDurationSeconds,
                    source: "lockedIn",
                    startTime: payload.startedAt,
                    importedPaceSecondsPerKm: payload.metrics.distanceMeters > 0
                        ? payload.activeDurationSeconds / (payload.metrics.distanceMeters / 1_000)
                        : nil,
                    sourceName: "LOCKED IN Running",
                    elevationGainMeters: payload.metrics.elevationGainMeters,
                    elevationLossMeters: payload.metrics.elevationLossMeters,
                    pausedDurationSeconds: payload.pausedDurationSeconds,
                    algorithmVersion: payload.configuration.algorithmVersion,
                    nativeArchiveData: payload.archiveData
                )
                pendingRecord = record
                modelContext.insert(record)
            }

            try modelContext.save()
            try? AutomaticBackup.backup(modelContext: modelContext)
            engine.markSaved()
            saveError = nil
            onComplete()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func formatPace(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "–:––" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let remainder = value % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}
