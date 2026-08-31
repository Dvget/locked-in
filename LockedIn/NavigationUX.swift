import SwiftUI

private struct LockedSwipeBackModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 18, coordinateSpace: .local)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let predicted = value.predictedEndTranslation.width

                    guard dx > 80,
                          predicted > 120,
                          abs(dy) < 90,
                          dx > abs(dy) * 1.35 else { return }

                    dismiss()
                },
            including: .gesture
        )
    }
}

extension View {
    func lockedSwipeBack() -> some View {
        modifier(LockedSwipeBackModifier())
    }
}

struct FullHistoryButton<Destination: View>: View {
    let destination: Destination

    init(@ViewBuilder destination: () -> Destination) {
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack {
                Text("Gesamten Verlauf anzeigen")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.lockedBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
