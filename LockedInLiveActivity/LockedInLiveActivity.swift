import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

@main
struct LockedInLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        LockedInLiveActivity()
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
