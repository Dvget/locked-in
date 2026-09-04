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
        Group {
            if let pendingPayload {
                RunCompletionSummaryView(
                    payload: pendingPayload,
                    onSave: savePendingRun,
                    onDiscard: { showDiscardConfirmation = true }
                )
            } else if engine.phase == .finishing {
                ProgressView("Lauf wird zusammengefasst …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                activeRunContent
            }
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
            Button("Lauf beenden", role: .destructive) { stopRun() }
            Button("Weiterlaufen", role: .cancel) {}
        } message: {
            Text("Die Aufzeichnung wird gestoppt. Anschließend kannst du den Lauf prüfen, speichern oder verwerfen.")
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
        .onAppear(perform: recoverSummaryIfNeeded)
        .onChange(of: engine.phase) { _, phase in
            guard phase == .finishing else { return }
            recoverSummaryIfNeeded()
        }
    }

    private var activeRunContent: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 3) {
                Text(engine.phase == .paused ? "PAUSIERT" : "LAUFZEIT")
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(engine.phase == .paused ? Color.yellow : Color.secondary)
                Text(formatDuration(engine.activeDurationSeconds))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(engine.phase == .paused ? Color.yellow : Color.white)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
            }
            .padding(.top, 16)

            Spacer(minLength: 12)

            largeMetric(
                title: "DURCHSCHNITTLICHE PACE",
                value: formatPace(engine.averagePaceSecondsPerKm),
                unit: "min/km",
                accent: false
            )

            Spacer(minLength: 12)

            largeMetric(
                title: "DISTANZ",
                value: formatDistance(engine.metrics.distanceMeters / 1_000),
                unit: "km",
                accent: false
            )

            Spacer(minLength: 14)

            splitStrip

            Spacer(minLength: 14)

            Group {
                if engine.phase == .paused {
                    HStack(spacing: 12) {
                        Button {
                            _ = engine.resume()
                        } label: {
                            Label("Fortsetzen", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                        }
                        .buttonStyle(LockedActionButtonStyle(prominent: true))
                        .accessibilityIdentifier("run-pause")

                        Button {
                            showStopConfirmation = true
                        } label: {
                            Label("Lauf beenden", systemImage: "stop.fill")
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
                } else {
                    Button {
                        _ = engine.pause()
                    } label: {
                        Label("Lauf pausieren", systemImage: "pause.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                    }
                    .buttonStyle(LockedActionButtonStyle(prominent: false))
                    .accessibilityIdentifier("run-pause")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
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

    private func largeMetric(
        title: String,
        value: String,
        unit: String,
        accent: Bool
    ) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 70, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent ? Color.lockedGreen : Color.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("\(title) (\(unit))")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var splitStrip: some View {
        VStack(spacing: 8) {
            Text("ZWISCHENZEITEN (KM)")
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                let width = max(96, (proxy.size.width - 20) / 3)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        if engine.metrics.splits.isEmpty {
                            ForEach(1...3, id: \.self) { kilometre in
                                splitTile(kilometre: kilometre, pace: nil)
                                    .frame(width: width)
                            }
                        } else {
                            ForEach(engine.metrics.splits) { split in
                                splitTile(kilometre: split.kilometre, pace: split.paceSecondsPerKm)
                                    .frame(width: width)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .frame(height: 76)
        }
    }

    private func splitTile(kilometre: Int, pace: Double?) -> some View {
        VStack(spacing: 3) {
            Text("KM \(kilometre)")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(formatPace(pace))
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(pace == nil ? Color.secondary : Color.white)
            Text("min/km")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lockedCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.lockedBorder, lineWidth: 1)
        }
    }

    private func stopRun() {
        do {
            pendingPayload = try engine.finish()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func recoverSummaryIfNeeded() {
        guard engine.phase == .finishing, pendingPayload == nil else { return }
        do {
            pendingPayload = try engine.recoverFinishedPayload()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func savePendingRun() {
        if pendingPayload == nil, engine.phase == .finishing {
            pendingPayload = try? engine.recoverFinishedPayload()
        }
        guard let payload = pendingPayload else {
            saveError = "Die beendeten Laufdaten konnten nicht wiederhergestellt werden."
            return
        }
        do {
            let record: RunRecord
            if let pendingRecord {
                record = pendingRecord
            } else if let existing = try existingRun(id: payload.runID) {
                record = existing
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
            engine.markSaved()
            try? AutomaticBackup.backup(modelContext: modelContext)
            saveError = nil
            onComplete()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func existingRun(id: UUID) throws -> RunRecord? {
        let descriptor = FetchDescriptor<RunRecord>(
            predicate: #Predicate<RunRecord> { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func formatPace(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "–:––" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formatDistance(_ kilometres: Double) -> String {
        kilometres.formatted(.number.precision(.fractionLength(2)))
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

private struct RunCompletionSummaryView: View {
    let payload: RunFinishedPayload
    let onSave: () -> Void
    let onDiscard: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader()
                .padding(.top, 12)

            Spacer(minLength: 20)

            Image(systemName: "checkmark")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 82, height: 82)
                .background(Color.lockedGreen)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Text("Lauf abgeschlossen")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .padding(.top, 18)

            LazyVGrid(columns: columns, spacing: 12) {
                summaryMetric(
                    title: "DISTANZ",
                    value: (payload.metrics.distanceMeters / 1_000).formatted(.number.precision(.fractionLength(2))),
                    unit: "km",
                    accent: true
                )
                summaryMetric(
                    title: "Ø PACE",
                    value: pace,
                    unit: "min/km",
                    accent: false
                )
                summaryMetric(
                    title: "LAUFZEIT",
                    value: duration,
                    unit: "aktiv",
                    accent: false
                )
                summaryMetric(
                    title: "HÖHENMETER",
                    value: "+\(Int(payload.metrics.elevationGainMeters.rounded())) / −\(Int(payload.metrics.elevationLossMeters.rounded()))",
                    unit: "m",
                    accent: false
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 26)

            Spacer(minLength: 20)

            VStack(spacing: 12) {
                Button(action: onSave) {
                    Label("Lauf speichern", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                }
                .buttonStyle(LockedActionButtonStyle(prominent: true))

                Button(action: onDiscard) {
                    Label("Lauf verwerfen", systemImage: "trash")
                        .font(.headline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func summaryMetric(
        title: String,
        value: String,
        unit: String,
        accent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent ? Color.lockedGreen : Color.white)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(14)
        .background(Color.lockedCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent ? Color.lockedGreen.opacity(0.30) : Color.lockedBorder, lineWidth: 1)
        }
    }

    private var pace: String {
        guard payload.metrics.distanceMeters > 0 else { return "–:––" }
        let seconds = payload.activeDurationSeconds / (payload.metrics.distanceMeters / 1_000)
        guard seconds.isFinite, seconds > 0 else { return "–:––" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var duration: String {
        let value = max(0, Int(payload.activeDurationSeconds))
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let seconds = value % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
