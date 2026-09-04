import CoreLocation
import SwiftUI

@MainActor
struct RunPreparationView: View {
    @StateObject private var engine: RunTrackingEngine
    @AppStorage("runCountdownSeconds") private var countdownSeconds = RunCountdownOption.defaultOption.seconds
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
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
        ZStack {
            Color.black.ignoresSafeArea()

            if isActive || engine.phase == .recording || engine.phase == .paused || engine.phase == .finishing {
                ActiveRunView(engine: engine, onComplete: onFlowFinished)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                preparationContent
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
            }
        }
        .animation(.easeInOut(duration: 0.45), value: isActive)
        .onAppear {
            engine.prepare()
            if engine.phase == .recording || engine.phase == .paused || engine.phase == .finishing {
                isActive = true
            }
        }
        .onDisappear {
            countdownTask?.cancel()
        }
    }

    private var preparationContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Zurück", action: closePreparation)
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
                    .fill(statusColor.opacity(0.13))
                    .frame(width: 190, height: 190)
                Circle()
                    .stroke(statusColor.opacity(0.48), lineWidth: 1)
                    .frame(width: 154, height: 154)

                if let countdown {
                    Text(String(countdown))
                        .font(.system(size: 76, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.lockedGreen)
                        .monospacedDigit()
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: engine.gpsReady ? "location.fill" : "location")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel(engine.gpsReady ? "GPS bereit" : "GPS wird gesucht")
                }
            }
            .animation(.easeInOut(duration: 0.22), value: countdown)

            Text("Bereit")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 24)
                .opacity(countdown == nil ? 1 : 0)

            Spacer()

            Menu {
                ForEach(RunCountdownOption.allCases) { option in
                    Button {
                        countdownSeconds = option.seconds
                    } label: {
                        if option == selectedCountdown {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text(option.displayName)
                        }
                    }
                }
            } label: {
                LockedCard {
                    HStack(spacing: 14) {
                        Image(systemName: "timer")
                            .font(.title2)
                            .foregroundStyle(Color.lockedGreen)

                        Text("Countdown")
                            .font(.headline)

                        Spacer()

                        Text(selectedCountdown.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(countdown != nil)
            .opacity(countdown == nil ? 1 : 0)
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
            .opacity(countdown == nil ? (engine.canStart ? 1 : 0.45) : 0)
            .accessibilityIdentifier("run-start")
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .background(Color.black.ignoresSafeArea())
        .lockedSwipeBack(action: closePreparation)
    }

    private var selectedCountdown: RunCountdownOption {
        RunCountdownOption(rawValue: countdownSeconds) ?? .defaultOption
    }

    private var statusColor: Color {
        engine.gpsReady ? Color.lockedGreen : Color.orange
    }

    private func startCountdown() {
        guard countdownTask == nil, engine.beginCountdown() else { return }
        let seconds = selectedCountdown.seconds

        if seconds == 0 {
            activateRun()
            return
        }

        countdownTask = Task { @MainActor in
            for value in stride(from: seconds, through: 1, by: -1) {
                guard !Task.isCancelled else {
                    engine.cancelCountdown()
                    countdown = nil
                    countdownTask = nil
                    return
                }
                withAnimation(.easeInOut(duration: 0.18)) {
                    countdown = value
                }
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            countdownTask = nil
            activateRun()
        }
    }

    private func activateRun() {
        guard engine.start() else {
            engine.cancelCountdown()
            countdown = nil
            countdownTask = nil
            return
        }
        countdown = nil
        countdownTask = nil
        withAnimation(.easeInOut(duration: 0.45)) {
            isActive = true
        }
    }

    private func closePreparation() {
        countdownTask?.cancel()
        countdownTask = nil
        engine.cancelCountdown()
        engine.discard()
        onClose()
    }
}
