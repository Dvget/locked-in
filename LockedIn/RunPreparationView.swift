import CoreLocation
import SwiftUI

@MainActor
struct RunPreparationView: View {
    @StateObject private var engine: RunTrackingEngine
    @State private var countdown: Int?
    @State private var isActive = false

    private let onClose: () -> Void
    private let onFlowFinished: () -> Void

    init(
        engine: RunTrackingEngine? = nil,
        onClose: @escaping () -> Void,
        onFlowFinished: @escaping () -> Void
    ) {
        _engine = StateObject(wrappedValue: engine ?? RunTrackingEngine())
        self.onClose = onClose
        self.onFlowFinished = onFlowFinished
    }

    var body: some View {
        Group {
            if isActive || engine.phase == .recording || engine.phase == .paused {
                ActiveRunView(engine: engine, onComplete: onFlowFinished)
            } else {
                preparationContent
            }
        }
        .onAppear {
            engine.prepare()
            if engine.phase == .recording || engine.phase == .paused {
                isActive = true
            }
        }
    }

    private var preparationContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Zurück") {
                    engine.discard()
                    onClose()
                }
                .foregroundStyle(.secondary)
                Spacer()
                BrandHeader()
                Spacer()
                Text("Zurück").hidden()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .fill(engine.gpsReady ? Color.lockedGreen.opacity(0.13) : Color.white.opacity(0.05))
                    .frame(width: 190, height: 190)
                Circle()
                    .stroke(engine.gpsReady ? Color.lockedGreen.opacity(0.45) : Color.white.opacity(0.10), lineWidth: 1)
                    .frame(width: 154, height: 154)
                Image(systemName: engine.gpsReady ? "location.fill" : "location")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(engine.gpsReady ? Color.lockedGreen : Color.secondary)
            }

            VStack(spacing: 8) {
                Text(countdown.map { String($0) } ?? readinessTitle)
                    .font(.system(size: countdown == nil ? 30 : 72, weight: .bold, design: .rounded))
                    .foregroundStyle(countdown == nil ? Color.white : Color.lockedGreen)
                    .monospacedDigit()
                Text(readinessDetail)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 290)
            }
            .padding(.top, 24)

            Spacer()

            LockedCard {
                HStack(spacing: 14) {
                    Image(systemName: engine.gpsReady ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(engine.gpsReady ? Color.lockedGreen : Color.yellow)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("GPS-Signal")
                            .font(.headline)
                        Text(engine.gpsReady ? "Bereit für die Aufzeichnung" : "Position wird vorbereitet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

            Button(action: startCountdown) {
                Label("Lauf starten", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
            }
            .buttonStyle(LockedActionButtonStyle(prominent: true))
            .disabled(!engine.canStart || countdown != nil)
            .opacity(engine.canStart ? 1 : 0.45)
            .accessibilityIdentifier("run-start")
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var readinessTitle: String {
        switch engine.authorizationStatus {
        case .denied, .restricted:
            return "Standort benötigt"
        default:
            return engine.gpsReady ? "Bereit zum Laufen" : "GPS wird gesucht"
        }
    }

    private var readinessDetail: String {
        if let lastError = engine.lastError { return lastError }
        if engine.gpsReady {
            return "Die Aufzeichnung startet nach einem kurzen Countdown."
        }
        return "Bleib kurz unter freiem Himmel, bis ein ausreichend genaues Signal verfügbar ist."
    }

    private func startCountdown() {
        guard engine.beginCountdown() else { return }
        Task { @MainActor in
            for value in stride(from: 3, through: 1, by: -1) {
                countdown = value
                try? await Task.sleep(for: .seconds(1))
            }
            guard engine.start() else {
                countdown = nil
                return
            }
            countdown = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                isActive = true
            }
        }
    }
}
