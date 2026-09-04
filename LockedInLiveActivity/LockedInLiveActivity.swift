import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

@main
struct LockedInLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        LockedInLiveActivity()
        LockedInRunLiveActivity()
    }
}

struct LockedInLiveActivity: Widget {
    private let green = Color(red: 0.55, green: 0.86, blue: 0.31)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LockedInActivityAttributes.self) { context in
            VStack(spacing: 16) {
                ZStack(alignment: .topLeading) {
                    GeometryReader { proxy in
                        lockScreenTimer(context.state)
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }

                    Image("LogoMark")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 78)

                HStack(spacing: 12) {
                    actionButton(title: "−30", intent: SubtractThirtySecondsIntent())
                    pauseButton(state: context.state)
                    actionButton(title: "+30", intent: AddThirtySecondsIntent())
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .activityBackgroundTint(Color.black.opacity(0.28))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("LogoMark")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                }

                DynamicIslandExpandedRegion(.center) {
                    islandTimer(context.state)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: ToggleRestTimerPauseIntent()) {
                        Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        actionButton(title: "−30", intent: SubtractThirtySecondsIntent(), compact: true)
                        pauseButton(state: context.state, compact: true)
                        actionButton(title: "+30", intent: AddThirtySecondsIntent(), compact: true)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image("LogoMark")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                compactTimer(context.state)
            } minimal: {
                Image("LogoMark")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            }
            .keylineTint(green)
        }
    }

    private func actionButton<I: AppIntent>(title: String, intent: I, compact: Bool = false) -> some View {
        Button(intent: intent) {
            Text(title)
                .font(compact ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 38 : 46)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func pauseButton(state: LockedInActivityAttributes.ContentState, compact: Bool = false) -> some View {
        Button(intent: ToggleRestTimerPauseIntent()) {
            Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                .font(compact ? .subheadline.weight(.bold) : .headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 38 : 46)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func lockScreenTimer(_ state: LockedInActivityAttributes.ContentState) -> some View {
        if state.isPaused {
            Text(format(seconds: state.pausedRemainingSeconds))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .foregroundStyle(green)
        } else if let end = state.restEndDate, end > Date() {
            Text(timerInterval: Date()...end, countsDown: true)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .foregroundStyle(green)
        } else {
            Text("0:00")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .foregroundStyle(.yellow)
        }
    }

    @ViewBuilder
    private func islandTimer(_ state: LockedInActivityAttributes.ContentState) -> some View {
        if state.isPaused {
            Text(format(seconds: state.pausedRemainingSeconds))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(green)
        } else if let end = state.restEndDate, end > Date() {
            Text(timerInterval: Date()...end, countsDown: true)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(green)
        } else {
            Text("0:00")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.yellow)
        }
    }

    @ViewBuilder
    private func compactTimer(_ state: LockedInActivityAttributes.ContentState) -> some View {
        if state.isPaused {
            Text(format(seconds: state.pausedRemainingSeconds))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(green)
        } else if let end = state.restEndDate, end > Date() {
            Text(timerInterval: Date()...end, countsDown: true)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(green)
        } else {
            Text("0:00")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.yellow)
        }
    }

    private func format(seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct LockedInRunLiveActivity: Widget {
    private let green = Color(red: 0.55, green: 0.86, blue: 0.31)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LockedInRunActivityAttributes.self) { context in
            VStack(spacing: 4) {
                ZStack {
                    HStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image("LogoMark")
                                .resizable()
                                .renderingMode(.original)
                                .scaledToFit()
                                .frame(
                                    width: context.state.isPaused ? 21 : 27,
                                    height: context.state.isPaused ? 21 : 27
                                )
                            Text("RUNNING")
                                .font(context.state.isPaused ? .caption2.weight(.bold) : .caption.weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(green)
                        }

                        Spacer(minLength: 4)

                        Button(intent: ToggleRunSpeechIntent()) {
                            Image(systemName: context.state.speechEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(context.state.speechEnabled ? green : Color.secondary)
                                .frame(
                                    width: context.state.isPaused ? 28 : 30,
                                    height: context.state.isPaused ? 28 : 30
                                )
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)

                    GeometryReader { proxy in
                        runTimer(context.state)
                            .font(.system(
                                size: context.state.isPaused ? 26 : 32,
                                weight: .bold,
                                design: .rounded
                            ))
                            .minimumScaleFactor(0.68)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: context.state.isPaused ? 28 : 34)

                if context.state.isPaused {
                    HStack(spacing: 7) {
                        runMetric(
                            value: String(format: "%.2f", context.state.distanceMeters / 1_000),
                            unit: "km",
                            compact: true
                        )
                        runMetric(
                            value: pace(context.state.paceSecondsPerKm),
                            unit: "/km",
                            compact: true
                        )
                    }
                    .frame(height: 40)

                    HStack(spacing: 7) {
                        Button(intent: ToggleRunPauseIntent()) {
                            Label("Fortsetzen", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(green)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button(intent: FinishRunIntent()) {
                            Text("Lauf beenden")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(Color.red.opacity(0.78))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    HStack(spacing: 7) {
                        runMetric(
                            value: String(format: "%.2f", context.state.distanceMeters / 1_000),
                            unit: "km",
                            compact: false
                        )

                        Button(intent: ToggleRunPauseIntent()) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 66, height: 68)
                                .background(Color.white.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        runMetric(
                            value: pace(context.state.paceSecondsPerKm),
                            unit: "/km",
                            compact: false
                        )
                    }
                    .frame(height: 68)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .animation(.easeInOut(duration: 0.24), value: context.state.isPaused)
            .activityBackgroundTint(Color.black.opacity(0.30))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("LogoMark")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        runTimer(context.state)
                            .font(.title3.bold())
                        Text(pace(context.state.paceSecondsPerKm) + " /km")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: ToggleRunPauseIntent()) {
                        Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                            .foregroundStyle(context.state.isPaused ? .black : .white)
                            .frame(width: 34, height: 34)
                            .background(context.state.isPaused ? green : Color.white.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(String(format: "%.2f km", context.state.distanceMeters / 1_000))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "figure.run")
                    .foregroundStyle(green)
            } compactTrailing: {
                Text(String(format: "%.2f", context.state.distanceMeters / 1_000))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "figure.run")
                    .foregroundStyle(green)
            }
            .keylineTint(green)
        }
    }

    @ViewBuilder
    private func runTimer(_ state: LockedInRunActivityAttributes.ContentState) -> some View {
        if state.isPaused {
            Text(duration(state.activeDurationSeconds))
                .monospacedDigit()
                .foregroundStyle(.yellow)
        } else {
            Text(timerInterval: state.timerAnchor...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    private func runMetric(value: String, unit: String, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: compact ? 20 : 31, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.66)
                .lineLimit(1)
            Text(unit)
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, compact ? 5 : 6)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func pace(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "–:––" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func duration(_ seconds: Int) -> String {
        let value = max(0, seconds)
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let remainder = value % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}
