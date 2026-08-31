import SwiftUI

extension Color {
    static let lockedGreen = Color(red: 0.55, green: 0.86, blue: 0.31)
    static let lockedCard = Color.white.opacity(0.055)
    static let lockedBorder = Color.white.opacity(0.09)
    static let lockedMutedGreen = Color.lockedGreen.opacity(0.55)
}

struct LockedCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(Color.lockedCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.lockedBorder, lineWidth: 1)
            }
    }
}

struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 7) {
            Image("LogoMark")
                .resizable()
                .scaledToFit()
                .frame(height: 22)

            Text("LOCKED")
                .font(.system(size: 12, weight: .semibold))
                .tracking(2.0)
                .foregroundStyle(.white)

            Text("IN")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Color.lockedGreen)
                .padding(.leading, -4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locked In")
    }
}

struct LIWordmark: View {
    var compact = true

    var body: some View {
        Image("LogoMark")
            .resizable()
            .scaledToFit()
            .frame(height: compact ? 18 : 24)
            .accessibilityLabel("Locked In")
    }
}

struct LockedActionButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color.black : Color.primary)
            .background(prominent ? Color.lockedGreen.opacity(configuration.isPressed ? 0.75 : 0.95) : Color.white.opacity(configuration.isPressed ? 0.12 : 0.07))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.lockedBorder, lineWidth: 1)
            }
    }
}

extension Double {
    var cleanWeight: String {
        if rounded() == self { return String(format: "%.0f", self) }
        return String(format: "%.1f", self)
    }
}

extension TimeInterval {
    var shortDuration: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
