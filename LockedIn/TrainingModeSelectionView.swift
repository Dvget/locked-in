import SwiftUI

struct TrainingModeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: TrainingMode = .strength
    @State private var activeMode: TrainingMode?

    var body: some View {
        ZStack {
            switch activeMode {
            case .strength:
                WorkoutPlanView(
                    onClose: { returnToSelection() },
                    onFlowFinished: { dismiss() }
                )
                .transition(.opacity)
            case .running:
                RunPreparationView(
                    onClose: { returnToSelection() },
                    onFlowFinished: { dismiss() }
                )
                .transition(.opacity)
            case nil:
                selectionContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: activeMode)
        .preferredColorScheme(.dark)
    }

    private var selectionContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Schließen") { dismiss() }
                    .foregroundStyle(.secondary)
                Spacer()
                BrandHeader()
                Spacer()
                Text("Schließen")
                    .hidden()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("Training starten")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Wähle, was heute ansteht.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 18)

            VStack(spacing: 14) {
                modeCard(
                    mode: .strength,
                    icon: "dumbbell.fill",
                    title: "Krafttraining"
                )
                .accessibilityIdentifier("training-mode-strength")

                modeCard(
                    mode: .running,
                    icon: "figure.run",
                    title: "Running"
                )
                .accessibilityIdentifier("training-mode-running")
            }
            .padding(.horizontal, 18)
            .frame(maxHeight: .infinity)

            Button {
                activeMode = selectedMode
            } label: {
                HStack {
                    Image(systemName: selectedMode == .strength ? "dumbbell.fill" : "figure.run")
                    Text(selectedMode == .strength ? "Training auswählen" : "Lauf starten")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
            }
            .buttonStyle(LockedActionButtonStyle(prominent: true))
            .padding(18)
            .background(Color.black.opacity(0.96))
        }
        .background(
            LinearGradient(
                colors: [Color.lockedGreen.opacity(0.09), Color.black, Color.black],
                startPoint: .topTrailing,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
        .lockedSwipeBack(action: { dismiss() })
    }

    private func modeCard(
        mode: TrainingMode,
        icon: String,
        title: String
    ) -> some View {
        let selected = selectedMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedMode = mode
            }
        } label: {
            VStack(spacing: 20) {
                Spacer(minLength: 8)

                Image(systemName: icon)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(selected ? Color.black : Color.lockedGreen)
                    .frame(width: 92, height: 92)
                    .background(selected ? Color.lockedGreen : Color.lockedGreen.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selected ? Color.lockedGreen.opacity(0.10) : Color.lockedCard)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Color.lockedGreen : Color.secondary)
                    .padding(20)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        selected ? Color.lockedGreen.opacity(0.75) : Color.lockedBorder,
                        lineWidth: selected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func returnToSelection() {
        withAnimation(.easeInOut(duration: 0.28)) {
            activeMode = nil
        }
    }
}

private enum TrainingMode: String, Identifiable {
    case strength
    case running

    var id: String { rawValue }
}
