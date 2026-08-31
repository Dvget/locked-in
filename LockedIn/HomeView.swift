import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \WorkoutRecord.startedAt, order: .reverse) private var workouts: [WorkoutRecord]
    @Query private var sets: [SetRecord]
    @Query(sort: \RunRecord.date, order: .reverse) private var runs: [RunRecord]
    @Query(sort: \StepRecord.date, order: .reverse) private var steps: [StepRecord]

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

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let headerHeight: CGFloat = 28
                let actionHeight: CGFloat = 92
                let spacing: CGFloat = 12
                let verticalPadding: CGFloat = 10
                let reserved = headerHeight + actionHeight + spacing * 4 + verticalPadding * 2
                let outerCategoryHeight = max(112, (geo.size.height - reserved) / 3)
                let cardContentHeight = max(80, outerCategoryHeight - 32)

                VStack(spacing: spacing) {
                    BrandHeader()
                        .frame(height: headerHeight)

                    if unfinishedWorkout != nil {
                        resumeCard
                            .frame(height: actionHeight)
                    } else {
                        startCard
                            .frame(height: actionHeight)
                    }

                    NavigationLink {
                        StrengthCurrentOverviewView()
                    } label: {
                        TrackingCategoryCard(
                            category: .strength,
                            primary: "\(workoutsThisWeek) / 2",
                            secondary: "Diese Woche · Fortschritt \(StrengthProgressMetric.text(weeklyProgress))",
                            accent: true,
                            minContentHeight: cardContentHeight,
                            dashboardEmphasis: true
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        RunCurrentOverviewView()
                    } label: {
                        TrackingCategoryCard(
                            category: .runs,
                            primary: runs.first.map { "\($0.distanceKm.cleanWeight) km" } ?? "Noch nicht verbunden",
                            secondary: "Aktuelle Laufdaten",
                            minContentHeight: cardContentHeight,
                            dashboardEmphasis: true
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        StepCurrentOverviewView()
                    } label: {
                        TrackingCategoryCard(
                            category: .steps,
                            primary: stepsThisWeek.isEmpty ? "Noch nicht verbunden" : "Ø \(averageStepsThisWeek.formatted()) / 10.000",
                            secondary: stepsThisWeek.isEmpty ? "Diese Woche" : "Diese Woche · \(totalStepsThisWeek.formatted()) Schritte",
                            minContentHeight: cardContentHeight,
                            dashboardEmphasis: true
                        )
                    }
                    .buttonStyle(.plain)


                }
                .padding(.horizontal, 16)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Color.black)
            .sheet(isPresented: $showPlan) { WorkoutPlanView() }
            .fullScreenCover(item: $resumedWorkout) { workoutState in
                ActiveWorkoutView(state: workoutState) {
                    resumedWorkout = nil
                }
            }
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

struct StrengthCurrentOverviewView: View {
    @Query(sort: \WorkoutRecord.startedAt, order: .reverse) private var workouts: [WorkoutRecord]
    @Query private var sets: [SetRecord]

    private var recent: [WorkoutRecord] {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return workouts.filter { $0.isCompleted && !$0.isHidden && interval.contains($0.startedAt) }
    }

    var body: some View {
        List {
            Section("Diese Woche") {
                if recent.isEmpty {
                    Text("Noch kein Krafttraining in dieser Woche.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recent, id: \.id) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Full Body").font(.headline)
                                    Text(workout.startedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                let progress = StrengthProgressMetric.workoutProgress(
                                    workout: workout,
                                    workouts: workouts,
                                    sets: sets
                                )
                                Text(StrengthProgressMetric.text(progress))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(StrengthProgressStyle.color(for: progress))
                            }
                        }
                    }
                }
            }

            Section {
                FullHistoryButton { StrengthHistoryView() }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Krafttraining")
        .lockedSwipeBack()
    }
}

struct RunCurrentOverviewView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var runs: [RunRecord]

    private var recent: [RunRecord] {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return runs.filter { interval.contains($0.date) }
    }

    var body: some View {
        List {
            Section("Diese Woche") {
                if recent.isEmpty {
                    Text("Noch keine Laufdaten in dieser Woche.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recent) { run in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(run.distanceKm.cleanWeight) km").font(.headline)
                            Text(run.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                FullHistoryButton { RunHistoryView() }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Läufe")
        .lockedSwipeBack()
    }
}

struct StepCurrentOverviewView: View {
    @Query(sort: \StepRecord.date, order: .reverse) private var records: [StepRecord]

    private var recordsThisWeek: [StepRecord] {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return records.filter { interval.contains($0.date) }
    }

    private var totalStepsThisWeek: Int {
        recordsThisWeek.reduce(0) { $0 + $1.steps }
    }

    private var elapsedDaysThisWeek: Int {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return 1 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: interval.start)
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return min(7, max(1, days + 1))
    }

    private var averageStepsThisWeek: Int {
        totalStepsThisWeek / elapsedDaysThisWeek
    }

    var body: some View {
        List {
            Section("Diese Woche") {
                if recordsThisWeek.isEmpty {
                    Text("Noch keine Step-Daten in dieser Woche.")
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Tagesdurchschnitt") {
                        Text("\(averageStepsThisWeek.formatted()) / 10.000")
                            .font(.headline.monospacedDigit())
                    }

                    LabeledContent("Wochenziel") {
                        Text("70.000 Schritte")
                            .monospacedDigit()
                    }

                    LabeledContent("Bisher gesamt") {
                        Text(totalStepsThisWeek.formatted())
                            .monospacedDigit()
                    }

                    ForEach(recordsThisWeek) { record in
                        LabeledContent(record.date.formatted(date: .abbreviated, time: .omitted)) {
                            Text(record.steps.formatted())
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section {
                FullHistoryButton { StepHistoryView() }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Steps")
        .lockedSwipeBack()
    }
}
