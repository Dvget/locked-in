import Foundation

enum RunDisplayFormatting {
    static let elevationGainTitle = "HÖHENZUNAHME"

    static func elevationGainValue(meters: Double) -> String {
        String(Int(max(0, meters).rounded()))
    }
}
