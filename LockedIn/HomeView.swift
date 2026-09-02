import SwiftUI
import SwiftData
import Charts

struct HomeView: View {
    @Query(sort: \WorkoutRecord.startedAt, order: .reverse) private var workouts: [WorkoutRecord]
    @Query private var sets: [SetRecord]
    @Query(sort: \RunRecord.date, order: .reverse) private var runs: [RunRecord]
    @Query(sort: \StepRecord.date, order: .reverse) private var steps: [StepRecord]
    @Query(sort: \WeightRecord.date, order: .reverse) private var weights: [WeightRecord]

    @State private var showPlan = false
    @State private var resumedWorkout: ActiveWorkoutState?

    private var completed: [WorkoutRecord] {
        workouts.filter { $0.isCompleted && !$0.isHidden }
    }

    private var unfinishedWorkout: WorkoutRecord? {
        workouts.first(where: { !$0.isCompleted })
    }

    private var trackingCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private var currentWeekInterval: DateInterval? {
        trackingCalendar.dateInterval(of: .weekOfYear, for: Date())
    }

    private var workoutsThisWeek: Int {
        guard let interval = currentWeekInterval else { return 0 }
        return completed.filter { interval.contains($0.startedAt) }.count
    }

    private var runsThisWeek: Int {
        guard let interval = currentWeekInterval else { return 0 }
        return runs.filter { !$0.isHidden && interval.contains($0.date) }.count
    }

    private var runWeekChange: Double? {
        TrackingAnalytics.weeklyRunChange(
            runs.filter { !$0.isHidden }.map {
                TrackingAnalytics.RunSample(
                    date: $0.date,
                    distanceKm: $0.distanceKm,
                    durationSeconds: $0.durationSeconds
                )
            },
            calendar: trackingCalendar
        )
    }

    private var runWeekChangeText: String {
        guard let runWeekChange else { return "Noch kein Wochenvergleich" }
        if abs(runWeekChange) < 0.5 { return "Unverändert zur Vorwoche" }
        return String(format: "%+.1f %% zur Vorwoche", runWeekChange)
            .replacingOccurrences(of: ".", with: ",")
    }

    private var runWeekChangeColor: Color {
        guard let runWeekChange else { return .secondary }
        if runWeekChange > 0.5 { return Color.lockedGreen }
        if runWeekChange < -0.5 { return .red }
        return .yellow
    }

    private var weeklyProgress: Double? {
        guard let interval = currentWeekInterval else { return nil }
        let recent = workouts.filter { interval.contains($0.startedAt) }
        let values = recent.compactMap {
            StrengthProgressMetric.workoutProgress(workout: $0, workouts: workouts, sets: sets)
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var preferredSteps: [TrackingAnalytics.StepSample] {
        TrackingAnalytics.preferredStepSamples(
            steps.map {
                TrackingAnalytics.StepSample(date: $0.date, steps: $0.steps, source: $0.source)
            }
        )
    }

    private var stepsThisWeek: [TrackingAnalytics.StepSample] {
        guard let interval = currentWeekInterval else { return [] }
        return preferredSteps.filter { interval.contains($0.date) }
    }

    private var averageStepsThisWeek: Int {
        TrackingAnalytics.recordedStepAverage(
            stepsThisWeek,
            calendar: trackingCalendar
        ) ?? 0
    }

    private var strengthProgressColor: Color {
        guard let weeklyProgress else { return .secondary }
        if weeklyProgress > 0.0001 { return Color.lockedGreen }
        if weeklyProgress < -0.0001 { return .red }
        return .yellow
    }

    private var stepStatusColor: Color {
        switch averageStepsThisWeek {
        case ...4_000: return .red
        case 4_001..<7_500: return .yellow
        default: return Color.lockedGreen
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                BrandHeader()
                    .frame(height: 30)

                Spacer()
                    .frame(height: 8)

                if unfinishedWorkout != nil {
                    resumeCard
                        .frame(height: 92)
                } else {
                    startCard
                        .frame(height: 92)
                }

                NavigationLink {
                    StrengthStatsDetailView()
                } label: {
                    TrackingCategoryCard(
                        category: .strength,
                        primary: "\(workoutsThisWeek) / 2",
                        secondary: "Wochenfortschritt \(StrengthProgressMetric.text(weeklyProgress))",
                        accent: true,
                        minContentHeight: 100,
                        dashboardEmphasis: true,
                        primaryColor: Color.lockedGreen,
                        secondaryColor: strengthProgressColor,
                        iconAccent: false
                    )
                }
                .buttonStyle(.plain)
                .frame(height: 132)

                NavigationLink {
                    RunStatsDetailView()
                } label: {
                    TrackingCategoryCard(
                        category: .runs,
                        primary: "\(runsThisWeek) / 2",
                        secondary: runWeekChangeText,
                        minContentHeight: 100,
                        dashboardEmphasis: true,
                        primaryColor: runsThisWeek > 0 ? Color.lockedGreen : nil,
                        secondaryColor: runWeekChangeColor,
                        iconAccent: false
                    )
                }
                .buttonStyle(.plain)
                .frame(height: 132)

                NavigationLink {
                    StepStatsDetailView()
                } label: {
                    TrackingCategoryCard(
                        category: .steps,
                        primary: stepsThisWeek.isEmpty ? "Noch keine Daten" : "Ø \(averageStepsThisWeek.formatted()) Schritte",
                        secondary: stepsThisWeek.isEmpty ? "Steps synchronisieren" : "Durchschnitt diese Woche",
                        minContentHeight: 100,
                        dashboardEmphasis: true,
                        primaryColor: stepsThisWeek.isEmpty ? nil : stepStatusColor,
                        iconAccent: false
                    )
                }
                .buttonStyle(.plain)
                .frame(height: 132)

                NavigationLink {
                    WeightStatsDetailView()
                } label: {
                    weightCard
                }
                .buttonStyle(.plain)
                .frame(height: 92)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black)
            .sheet(isPresented: $showPlan) { WorkoutPlanView() }
            .fullScreenCover(item: $resumedWorkout) { workoutState in
                ActiveWorkoutView(state: workoutState) {
                    resumedWorkout = nil
                }
            }
        }
    }

    private var weightCard: some View {
        LockedCard {
            HStack(spacing: 14) {
                Image(systemName: TrackingCategory.weight.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 54, height: 54)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Gewicht")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("Gewichtsübersicht und Waage")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        }
    }

    private var resumeCard: some View {
        Button {
            resumeWorkout()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.black)
                    .frame(width: 54, height: 54)
                    .background(Color.lockedGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Training fortsetzen").font(.title3.bold())
                    Text("Laufende Session")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color.lockedGreen.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.lockedGreen.opacity(0.25), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var startCard: some View {
        Button { showPlan = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Color.lockedGreen.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Training starten").font(.title2.bold())
                    Text("Neues Krafttraining beginnen")
                        .font(.subheadline)
                        .foregroundStyle(Color.lockedGreen)
                }

                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color.lockedGreen.opacity(0.34), Color.lockedGreen.opacity(0.12)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.lockedGreen.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func resumeWorkout() {
        guard let unfinishedWorkout else { return }
        if let stored = WorkoutSessionStore.load(), stored.workoutID == unfinishedWorkout.id {
            resumedWorkout = stored
        } else {
            resumedWorkout = ActiveWorkoutState(
                workoutID: unfinishedWorkout.id,
                startedAt: unfinishedWorkout.startedAt,
                exerciseIDsBySlot: Dictionary(uniqueKeysWithValues: ExerciseCatalog.slots.map { ($0.id, $0.defaultExerciseID) }),
                slotIndex: 0,
                timerEndDate: nil
            )
        }
    }
}
