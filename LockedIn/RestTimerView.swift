import SwiftUI

struct RestTimerView: View {
    @Binding var remainingSeconds: Int
    @Binding var isRunning: Bool
    var defaultSeconds: Int = 120
    var subtract30: (() -> Void)? = nil
    var skip: (() -> Void)? = nil
    var reset: (() -> Void)? = nil
    var add30: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text("PAUSE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.lockedGreen)
                .tracking(1.5)

            Text(timeString)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()

            HStack(spacing: 10) {
                timerButton("−30") {
                    if let subtract30 { subtract30() }
                    else { remainingSeconds = max(0, remainingSeconds - 30) }
                }

                timerButton("Skip", prominent: true) {
                    if let skip { skip() }
                    else {
                        remainingSeconds = 0
                        isRunning = false
                    }
                }

                timerIconButton("arrow.counterclockwise") {
                    if let reset { reset() }
                    else {
                        remainingSeconds = defaultSeconds
                        isRunning = false
                    }
                }

                timerButton("+30") {
                    if let add30 { add30() }
                    else { remainingSeconds += 30 }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var timeString: String {
        String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    private func timerButton(_ text: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(LockedActionButtonStyle(prominent: prominent))
    }

    private func timerIconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(LockedActionButtonStyle())
    }
}
