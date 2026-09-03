import SwiftUI

struct TrainingModeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: TrainingMode = .strength
    @State private var activeMode: TrainingMode?

    var body: some View {
        Group {
            switch activeMode {
            case .strength:
                WorkoutPlanView(
                    onClose: { activeMode = nil },
                    onFlowFinished: { dismiss() }
                )
            case .running:
                RunPreparationView(
                    onClose: { activeMode = nil },
                    onFlowFinished: { dismiss() }
                )
            case nil:
                selectionContent
            }
        }
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
            .padding(.top, 34)
            .padding(.bottom, 22)

            VStack(spacing: 14) {
                modeCard(
                    mode: .strength,
                    icon: "dumbbell.fill",
                    title: "Krafttraining",
                    subtitle: "Übungen auswählen und Session starten",
                    detail: "SÄTZE  ·  REPS  ·  GEWICHT"
                )
                .accessibilityIdentifier("training-mode-strength")

                modeCard(
                    mode: .running,
                    icon: "figure.run",
                    title: "Running",
                    subtitle: "Lauf mit dem iPhone aufzeichnen",
                    detail: "GPS  ·  PACE  ·  HÖHENMETER"
                )
                .accessibilityIdentifier("training-mode-running")
            }
            .padding(.horizontal, 18)

            Spacer(minLength: 18)

            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    activeMode = selectedMode
                }
            } label: {
                HStack {
                    Image(systemName: selectedMode == .strength ? "dumbbell.fill" : "figure.run")
                    Text(selectedMode == .strength ? "Krafttraining auswählen" : "Running auswählen")
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
    }

    private func modeCard(
        mode: TrainingMode,
        icon: String,
        title: String,
        subtitle: String,
        detail: String
    ) -> some View {
        let selected = selectedMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedMode = mode
            }
        } label: {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(selected ? Color.black : Color.lockedGreen)
                        .frame(width: 58, height: 58)
                        .background(selected ? Color.lockedGreen : Color.lockedGreen.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Spacer()

                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(selected ? Color.lockedGreen : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(detail)
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(selected ? Color.lockedGreen : Color.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
            .background(selected ? Color.lockedGreen.opacity(0.10) : Color.lockedCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selected ? Color.lockedGreen.opacity(0.75) : Color.lockedBorder, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private enum TrainingMode: String, Identifiable {
    case strength
    case running

    var id: String { rawValue }
}
