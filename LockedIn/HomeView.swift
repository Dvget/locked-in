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

    private var currentWeekInterval: DateInterval? {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())
    }

    private var workoutsThisWeek: Int {
        guard let interval = currentWeekInterval else { return 0 }
        return completed.filter { interval.contains($0.startedAt) }.count
    }

    private var runsThisWeek: Int {
        guard let interval = currentWeekInterval else { return 0 }
        return runs.filter { !$0.isHidden && interval.contains($0.date) }.count
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

    private var stepsThisWeek: [StepRecord] {
        guard let interval = currentWeekInterval else { return [] }
        return steps.filter { interval.contains($0.date) }
    }

    private var totalStepsThisWeek: Int {
        stepsThisWeek.reduce(0) { $0 + $1.steps }
    }

    private var elapsedDaysThisWeek: Int {
        guard let interval = currentWeekInterval else { return 1 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: interval.start)
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return min(7, max(1, days + 1))
    }

    private var averageStepsThisWeek: Int {
        totalStepsThisWeek / elapsedDaysThisWeek
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
                        secondary: "Wochenziel",
                        minContentHeight: 100,
                        dashboardEmphasis: true,
                        iconAccent: false
                    )
                }
                .buttonStyle(.plain)
                .frame(height: 132)

                NavigationLink {
                    StepCurrentOverviewView()
                } label: {
                    TrackingCategoryCard(
                        category: .steps,
                        primary: stepsThisWeek.isEmpty ? "Noch keine Daten" : "Ø \(averageStepsThisWeek.formatted()) / 10.000",
                        secondary: stepsThisWeek.isEmpty ? "Steps synchronisieren" : "\(totalStepsThisWeek.formatted()) Schritte diese Woche",
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

struct StepCurrentOverviewView: View {
    @Query(sort: \StepRecord.date) private var records: [StepRecord]

    private struct DayPoint: Identifiable {
        let id: Int
        let label: String
        let date: Date
        let steps: Int
    }

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        return value
    }

    private var currentWeek: DateInterval? {
        calendar.dateInterval(of: .weekOfYear, for: Date())
    }

    private var dailyTotals: [DayPoint] {
        guard let interval = currentWeek else { return [] }
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
        let labels = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
        let start = calendar.startOfDay(for: interval.start)

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let total = grouped[day]?.reduce(0) { $0 + $1.steps } ?? 0
            return DayPoint(id: offset, label: labels[offset], date: day, steps: total)
        }
    }

    private var elapsedDailyTotals: [DayPoint] {
        let today = calendar.startOfDay(for: Date())
        return dailyTotals.filter { $0.date <= today }
    }

    private var totalStepsThisWeek: Int {
        elapsedDailyTotals.reduce(0) { $0 + $1.steps }
    }

    private var averageStepsThisWeek: Int {
        guard !elapsedDailyTotals.isEmpty else { return 0 }
        return totalStepsThisWeek / elapsedDailyTotals.count
    }

    private var previousWeekAverages: [Double] {
        let grouped = Dictionary(grouping: records) { record in
            calendar.dateInterval(of: .weekOfYear, for: record.date)?.start ?? calendar.startOfDay(for: record.date)
        }
        guard let currentStart = currentWeek?.start else { return [] }

        return grouped
            .filter { $0.key < currentStart }
            .compactMap { _, items -> Double? in
                let dayGrouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
                guard !dayGrouped.isEmpty else { return nil }
                let total = dayGrouped.values.reduce(0) { partial, dayItems in
                    partial + dayItems.reduce(0) { $0 + $1.steps }
                }
                return Double(total) / Double(dayGrouped.count)
            }
    }

    private var comparisonText: String {
        guard !previousWeekAverages.isEmpty else {
            return "Noch nicht genug frühere Wochen für einen Vergleich."
        }
        let baseline = previousWeekAverages.reduce(0, +) / Double(previousWeekAverages.count)
        guard baseline > 0 else { return "Noch kein sinnvoller Wochenvergleich möglich." }
        let delta = (Double(averageStepsThisWeek) / baseline - 1) * 100
        let absText = String(format: "%.0f", abs(delta))
        if abs(delta) < 1 {
            return "Diese Woche liegt ungefähr auf deinem bisherigen Wochenschnitt."
        }
        return delta > 0
            ? "Diese Woche liegst du \(absText) % über deinem bisherigen Wochenschnitt."
            : "Diese Woche liegst du \(absText) % unter deinem bisherigen Wochenschnitt."
    }

    private var averageColor: Color {
        switch averageStepsThisWeek {
        case ...4_000: return .red
        case 4_001..<7_500: return .yellow
        default: return Color.lockedGreen
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            LockedCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("DIESE WOCHE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Ø \(averageStepsThisWeek.formatted())")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(averageColor)
                        Text("/ 10.000")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    Chart(dailyTotals) { item in
                        BarMark(
                            x: .value("Tag", item.label),
                            y: .value("Schritte", item.steps)
                        )
                        .foregroundStyle(Color.lockedGreen)

                        RuleMark(y: .value("Ziel", 10_000))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(dash: [5, 5]))
                    }
                    .chartXScale(domain: ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"])
                    .chartXAxis {
                        AxisMarks(values: ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"])
                    }
                    .frame(maxHeight: .infinity)
                    .frame(minHeight: 220)
                }
            }

            LockedCard {
                VStack(spacing: 10) {
                    LabeledContent("Wochenziel") {
                        Text("70.000 Schritte").monospacedDigit()
                    }
                    Divider().overlay(Color.lockedBorder)
                    LabeledContent("Bisher gesamt") {
                        Text(totalStepsThisWeek.formatted()).monospacedDigit()
                    }
                    Divider().overlay(Color.lockedBorder)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VERGLEICH")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(comparisonText)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            NavigationLink {
                StepStatsDetailView()
            } label: {
                LockedCard {
                    HStack {
                        Text("Statistik ansehen")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
        .navigationTitle("Steps")
        .lockedSwipeBack()
    }
}

