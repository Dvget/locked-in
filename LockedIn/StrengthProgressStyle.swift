import SwiftUI

enum StrengthProgressStyle {
    static let significantDeclineThreshold: Double = -5.0

    static func color(for value: Double?) -> Color {
        guard let value else { return .secondary }
        if value > 0 {
            return Color.lockedGreen
        }
        if value < significantDeclineThreshold {
            return .red
        }
        if value < 0 {
            return .yellow
        }
        return .primary
    }
}
