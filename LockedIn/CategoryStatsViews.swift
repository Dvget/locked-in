import SwiftUI
import SwiftData
import Charts

private struct ProgressPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

private struct RunDistancePoint: Identifiable {
    let id = UUID()
    let date: Date
    let distanceKm: Double
}

private struct StepAveragePoint: Identifiable {
    let id = UUID()
    let date: Date
    let averageSteps: Double
}

private struct WeightPoint: Identifiable {
    let id = UUID()
    let date: Date
    let weightKg: Double
    let trendKg: Double?
}

struct StrengthStatsDetailView: View {
    @Query(sort: \WorkoutRecord.startedAt) private var workouts: [WorkoutRecord]
    @Query private var sets: [SetRecord]
    @State private var showAdd = false
    @State private var selectedSeries: StrengthSeries = .performance

    private enum StrengthSeries: String, CaseIterable, Identifiable {
        case performance = "Leistung"
        case volume = "Volumen"

        var id: String { rawValue }
    }

    private var completedWorkouts: [WorkoutRecord] {
        workouts.filter { $0.isCompleted && !$0.isHidden }.sorted { $0.startedAt < $1.startedAt }
    }

    private var cumulativePoints: [ProgressPoint] {
        guard let first = completedWorkouts.first else { return [] }
        var result = [ProgressPoint(date: first.startedAt, value: 100)]
        var index = 100.0
        for workout in completedWorkouts.dropFirst() {
            guard let delta = StrengthProgressMetric.workoutProgress(workout: workout, workouts: workouts, sets: sets) else { continue }
            index *= (1 + delta / 100)
            result.append(ProgressPoint(date: workout.startedAt, value: index))
        }
        return result
    }

    private var totalChange: Double? {
        guard let last = cumulativePoints.last, cumulativePoints.count > 1 else { return nil }
        return last.value - 100
    }

    private var latestWorkoutChange: Double? {
        guard let last = completedWorkouts.last else { return nil }
        return StrengthProgressMetric.workoutProgress(workout: last, workouts: workouts, sets: sets)
    }

    private var volumePoints: [ProgressPoint] {
        completedWorkouts.compactMap { workout in
            let samples = sets
                .filter { $0.workoutID == workout.id && $0.reps > 0 }
                .map { set in
                    TrackingAnalytics.StrengthSetSample(
                        weightKg: set.weight,
                        reps: set.reps,
                        repsOnly: ExerciseCatalog.exercise(id: set.exerciseID)?.repsOnly ?? false
                    )
                }
            let volume = TrackingAnalytics.trainingVolume(samples)
            guard volume > 0 else { return nil }
            return ProgressPoint(date: workout.startedAt, value: volume)
        }
    }

    private var trainingFrequency: Double {
        guard let first = completedWorkouts.first, let last = completedWorkouts.last else { return 0 }
        let days = max(1, Calendar.current.dateComponents([.day], from: first.startedAt, to: last.startedAt).day ?? 0)
        return Double(completedWorkouts.count) / max(1, Double(days + 1) / 7)
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Statistik", selection: $selectedSeries) {
                ForEach(StrengthSeries.allCases) { series in
                    Text(series.rawValue).tag(series)
                }
            }
            .pickerStyle(.segmented)

            LockedCard {
                VStack(alignment: .leading, spacing: 8) {
                    if selectedSeries == .performance {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("GESAMTLEISTUNGSINDEX")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(cumulativePoints.last.map { String(format: "%.1f", $0.value).replacingOccurrences(of: ".", with: ",") } ?? "—")
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("SEIT BEGINN")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(StrengthProgressMetric.text(totalChange))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(StrengthProgressStyle.color(for: totalChange))
                            }
                        }

                        if cumulativePoints.count >= 2 {
                            Chart(cumulativePoints) { point in
                                LineMark(x: .value("Datum", point.date), y: .value("Index", point.value))
                                    .foregroundStyle(Color.lockedGreen)
                                PointMark(x: .value("Datum", point.date), y: .value("Index", point.value))
                                    .foregroundStyle(Color.lockedGreen)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 190)
                        } else {
                            Text("Für den Gesamttrend werden mindestens zwei vergleichbare Trainings benötigt.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TRAININGSVOLUMEN")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(volumePoints.last.map { "\(Int($0.value.rounded()).formatted()) kg" } ?? "—")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }

                        if volumePoints.count >= 2 {
                            Chart(volumePoints) { point in
                                LineMark(x: .value("Datum", point.date), y: .value("Kilogramm", point.value))
                                    .foregroundStyle(Color.lockedGreen)
                                PointMark(x: .value("Datum", point.date), y: .value("Kilogramm", point.value))
                                    .foregroundStyle(Color.lockedGreen)
                            }
                            .chartYAxis {
                                AxisMarks { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let number = value.as(Double.self) {
                                            Text("\(Int(number.rounded()).formatted()) kg")
                                        }
                                    }
                                }
                            }
                            .frame(height: 190)
                        } else {
                            Text("Ab zwei Trainings zeigt LOCKED IN hier die bewegte Kilozahl pro Training.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
                        }
                    }
                }
            }

            LockedCard {
                HStack {
                    metric("LETZTES TRAINING", StrengthProgressMetric.text(latestWorkoutChange), StrengthProgressStyle.color(for: latestWorkoutChange))
                    Spacer()
                    metric("TRAININGS", completedWorkouts.count.formatted())
                    Spacer()
                    metric("Ø / WOCHE", trainingFrequency == 0 ? "—" : String(format: "%.1f", trainingFrequency).replacingOccurrences(of: ".", with: ","))
                }
            }

            Button {
                showAdd = true
            } label: {
                Label("Training nachtragen", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(LockedActionButtonStyle(prominent: true))

            NavigationLink {
                ExerciseStatsView()
            } label: {
                Label("Einzelne Übungen", systemImage: "dumbbell.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(LockedActionButtonStyle())

            NavigationLink {
                StrengthHistoryView()
            } label: {
                Label("Trainingsverlauf", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(LockedActionButtonStyle())

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
        .navigationTitle("Krafttraining")
        .sheet(isPresented: $showAdd) { ManualStrengthEntryView() }
        .lockedSwipeBack()
    }

    private func metric(_ title: String, _ value: String, _ color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.headline.bold().monospacedDigit()).foregroundStyle(color)
        }
    }
}

struct ExerciseStatsView: View {
    @Query(sort: \WorkoutRecord.startedAt) private var workouts: [WorkoutRecord]
    @Query private var sets: [SetRecord]
    @State private var selectedSlotID = 1
    @State private var selectedExerciseID: String?

    private var slot: PlanSlotDefinition {
        ExerciseCatalog.slot(id: selectedSlotID) ?? ExerciseCatalog.slots[0]
    }

    private var exerciseID: String {
        selectedExerciseID ?? slot.defaultExerciseID
    }

    private var points: [ProgressPoint] {
        let relevantWorkouts = workouts
            .filter { $0.isCompleted && !$0.isHidden }
            .filter { workout in
                sets.contains {
                    $0.workoutID == workout.id &&
                    $0.exerciseID == exerciseID &&
                    $0.reps > 0
                }
            }
            .sorted { $0.startedAt < $1.startedAt }

        guard let first = relevantWorkouts.first else { return [] }
        var dates = [first.startedAt]
        var changes: [Double] = []

        for workout in relevantWorkouts.dropFirst() {
            if let change = StrengthProgressMetric.exerciseProgress(
                    exerciseID: exerciseID,
                    workout: workout,
                    workouts: workouts,
                    sets: sets
            ) {
                dates.append(workout.startedAt)
                changes.append(change)
            }
        }

        let values = TrackingAnalytics.cumulativeIndex(changes: changes)
        return zip(dates, values).map { ProgressPoint(date: $0.0, value: $0.1) }
    }

    private var current: Double? { points.last?.value }

    private var average: Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    private func indexText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    private func indexColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value > 100.05 { return Color.lockedGreen }
        if value < 99.95 { return .red }
        return .yellow
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LockedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ÜBUNG")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack {
                            Picker("Hauptübung", selection: $selectedSlotID) {
                                ForEach(ExerciseCatalog.slots) { item in
                                    Text(item.title).tag(item.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .onChange(of: selectedSlotID) {
                            selectedExerciseID = nil
                        }

                        Divider().overlay(Color.lockedBorder)

                        HStack {
                            Picker("Variante", selection: Binding(
                                get: { exerciseID },
                                set: { selectedExerciseID = $0 }
                            )) {
                                ForEach(slot.exercises) { exercise in
                                    Text(exercise.shortName).tag(exercise.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                LockedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("LEISTUNGSINDEX")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(indexText(current))
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(indexColor(current))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Ø")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(indexText(average))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(indexColor(average))
                            }
                        }

                        if points.count < 2 {
                            ContentUnavailableView(
                                "Noch kein Vergleich möglich",
                                systemImage: "chart.xyaxis.line",
                                description: Text("Für diese Übung werden mindestens zwei Trainings benötigt.")
                            )
                            .frame(height: 220)
                        } else {
                            Chart(points) { point in
                                LineMark(
                                    x: .value("Datum", point.date),
                                    y: .value("Fortschritt", point.value)
                                )
                                .foregroundStyle(Color.lockedGreen)
                                PointMark(
                                    x: .value("Datum", point.date),
                                    y: .value("Fortschritt", point.value)
                                )
                                .foregroundStyle(Color.lockedGreen)
                            }
                            .chartYAxis {
                                AxisMarks { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let number = value.as(Double.self) {
                                            Text(String(format: "%.0f", number))
                                        }
                                    }
                                }
                            }
                            .frame(height: 250)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black)
        .navigationTitle("Einzelne Übungen")
        .lockedSwipeBack()
    }
}

struct RunStatsDetailView: View {
    @Query(sort: \RunRecord.date) private var runs: [RunRecord]
    @State private var showAdd = false
    @State private var selectedSeries: RunSeries = .overall

    private enum RunSeries: String, CaseIterable, Identifiable {
        case overall = "Gesamt"
        case distance = "Distanz"
        case pace = "Pace"

        var id: String { rawValue }
    }

    private var validRuns: [RunRecord] {
        runs.filter { !$0.isHidden && $0.distanceKm > 0 && $0.durationSeconds > 0 }
    }

    private var samples: [TrackingAnalytics.RunSample] {
        validRuns.map {
            TrackingAnalytics.RunSample(
                date: $0.date,
                distanceKm: $0.distanceKm,
                durationSeconds: $0.durationSeconds
            )
        }
    }

    private var lastFourWeeks: TrackingAnalytics.RunSummary {
        TrackingAnalytics.runSummary(samples, rollingDays: 28)
    }

    private var total: TrackingAnalytics.RunSummary {
        TrackingAnalytics.runSummary(samples)
    }

    private var progressPoints: [RunProgressMetric.Point] { RunProgressMetric.points(for: validRuns) }
    private var trackingSeries: TrackingAnalytics.RunSeries {
        switch selectedSeries {
        case .overall: return .overall
        case .distance: return .distance
        case .pace: return .pace
        }
    }

    private var selectedChange: Double? {
        TrackingAnalytics.runSeriesChange(samples, series: trackingSeries)
    }

    private var selectedTitle: String {
        switch selectedSeries {
        case .overall: return "LAUFENTWICKLUNG"
        case .distance: return "DISTANZENTWICKLUNG"
        case .pace: return "PACE-ENTWICKLUNG"
        }
    }

    private var selectedCurrentText: String {
        guard let latest = progressPoints.last else { return "—" }
        switch selectedSeries {
        case .overall:
            return RunProgressMetric.text(latest.overallIndex)
        case .distance:
            return "\(latest.distanceKm.cleanWeight) km"
        case .pace:
            return "\(formatPace(latest.paceSecondsPerKm)) min/km"
        }
    }

    private var selectedChangeColor: Color {
        guard let selectedChange else { return .secondary }
        if selectedChange > 0.05 { return Color.lockedGreen }
        if selectedChange < -0.05 { return .red }
        return .yellow
    }

    private var seriesColor: Color {
        switch selectedSeries {
        case .overall: return Color.lockedGreen
        case .distance: return .cyan
        case .pace: return .orange
        }
    }

    private func seriesValue(_ point: RunProgressMetric.Point) -> Double {
        switch selectedSeries {
        case .overall: return point.overallIndex
        case .distance: return point.distanceKm
        case .pace: return -point.paceSecondsPerKm
        }
    }

    var body: some View {
        VStack(spacing: 9) {
            Picker("Wert", selection: $selectedSeries) {
                ForEach(RunSeries.allCases) { series in
                    Text(series.rawValue).tag(series)
                }
            }
            .pickerStyle(.segmented)

            LockedCard {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(selectedCurrentText)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("SEIT BEGINN")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(selectedChange.map { String(format: "%+.1f %%", $0).replacingOccurrences(of: ".", with: ",") } ?? "—")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(selectedChangeColor)
                        }
                    }

                    if progressPoints.isEmpty {
                        Text("Sobald Läufe vorhanden sind, erscheinen hier Distanz, Pace und Gesamtentwicklung.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 135, alignment: .center)
                    } else {
                        Chart {
                            ForEach(progressPoints, id: \.date) { point in
                                LineMark(
                                    x: .value("Datum", point.date),
                                    y: .value(selectedSeries.rawValue, seriesValue(point))
                                )
                                .foregroundStyle(seriesColor)
                                .lineStyle(StrokeStyle(lineWidth: 3.2))

                                PointMark(
                                    x: .value("Datum", point.date),
                                    y: .value(selectedSeries.rawValue, seriesValue(point))
                                )
                                .foregroundStyle(seriesColor)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let number = value.as(Double.self) {
                                        switch selectedSeries {
                                        case .overall:
                                            Text(String(format: "%.0f", number))
                                        case .distance:
                                            Text("\(number.cleanWeight) km")
                                        case .pace:
                                            Text("\(formatPace(abs(number))) min/km")
                                        }
                                    }
                                }
                            }
                        }
                        .chartLegend(.hidden)
                        .frame(height: 185)
                    }
                }
            }

            LockedCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LETZTE 4 WOCHEN")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lockedGreen)

                    HStack(alignment: .top) {
                        metric("LÄUFE", lastFourWeeks.count.formatted())
                        Spacer()
                        metric("Ø DISTANZ", lastFourWeeks.averageDistanceKm > 0 ? "\(lastFourWeeks.averageDistanceKm.cleanWeight) km" : "—")
                        Spacer()
                        metric("Ø PACE", lastFourWeeks.weightedPaceSecondsPerKm > 0 ? "\(formatPace(lastFourWeeks.weightedPaceSecondsPerKm)) /km" : "—")
                    }
                }
            }

            LockedCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GESAMT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lockedGreen)

                    HStack {
                        metric("LÄUFE", total.count.formatted())
                        Spacer()
                        metric("DISTANZ", total.totalDistanceKm > 0 ? "\(total.totalDistanceKm.cleanWeight) km" : "—")
                        Spacer()
                        metric("Ø DISTANZ", total.averageDistanceKm > 0 ? "\(total.averageDistanceKm.cleanWeight) km" : "—")
                        Spacer()
                        metric("Ø PACE", total.weightedPaceSecondsPerKm > 0 ? "\(formatPace(total.weightedPaceSecondsPerKm)) /km" : "—")
                    }
                }
            }

            VStack(spacing: 9) {
                Button {
                    showAdd = true
                } label: {
                    Label("Lauf nachtragen", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(LockedActionButtonStyle(prominent: true))

                NavigationLink {
                    RunHistoryView()
                } label: {
                    Label("Verlauf / Einzelwerte", systemImage: "list.bullet")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(LockedActionButtonStyle())
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black)
        .navigationTitle("Läufe")
        .sheet(isPresented: $showAdd) { ManualRunEntryView() }
        .lockedSwipeBack()
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold().monospacedDigit())
        }
    }

    private func formatPace(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct StepStatsDetailView: View {
    @Query(sort: \StepRecord.date) private var records: [StepRecord]
    @State private var selectedRange: StepRange = .week
    @State private var showAdd = false

    private enum StepRange: String, CaseIterable, Identifiable {
        case week = "Woche"
        case all = "Gesamt"

        var id: String { rawValue }
    }

    private struct StepBarPoint: Identifiable {
        let id = UUID()
        let label: String
        let date: Date
        let steps: Int
    }

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        return value
    }

    private var dailyTotals: [(date: Date, steps: Int)] {
        TrackingAnalytics.preferredStepSamples(
            records.map {
                TrackingAnalytics.StepSample(date: $0.date, steps: $0.steps, source: $0.source)
            },
            calendar: calendar
        )
        .map { (date: $0.date, steps: $0.steps) }
    }

    private var relevantDailyTotals: [(date: Date, steps: Int)] {
        let now = Date()
        switch selectedRange {
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
            return dailyTotals.filter { interval.contains($0.date) }
        case .all:
            return dailyTotals
        }
    }

    private var chartPoints: [StepBarPoint] {
        let now = Date()

        switch selectedRange {
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
            let labels = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
            let start = calendar.startOfDay(for: interval.start)
            return (0..<7).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                let steps = dailyTotals.first(where: { calendar.isDate($0.date, inSameDayAs: day) })?.steps ?? 0
                return StepBarPoint(label: labels[offset], date: day, steps: steps)
            }

        case .all:
            guard let first = dailyTotals.first?.date, let last = dailyTotals.last?.date else { return [] }
            let useYears = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) > 730
            let grouped = Dictionary(grouping: dailyTotals) {
                calendar.date(
                    from: calendar.dateComponents(useYears ? [.year] : [.year, .month], from: $0.date)
                ) ?? $0.date
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.dateFormat = useYears ? "yyyy" : "MMM yy"
            return grouped.map { date, items in
                StepBarPoint(label: formatter.string(from: date), date: date, steps: items.reduce(0) { $0 + $1.steps })
            }.sorted { $0.date < $1.date }
        }
    }

    private var currentWeekTotals: [(date: Date, steps: Int)] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        let today = calendar.startOfDay(for: Date())
        return dailyTotals.filter { interval.contains($0.date) && $0.date <= today }
    }

    private var currentWeekTotal: Int {
        currentWeekTotals.reduce(0) { $0 + $1.steps }
    }

    private var elapsedDaysThisWeek: Int {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 1 }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        return min(7, max(1, days + 1))
    }

    private var weeklyAverage: Double {
        Double(currentWeekTotal) / Double(elapsedDaysThisWeek)
    }

    private var weeklyProgressColor: Color {
        switch TrackingAnalytics.stepProgressStatus(
            steps: currentWeekTotal,
            elapsedDays: elapsedDaysThisWeek
        ) {
        case .red: return .red
        case .yellow: return .yellow
        case .green: return Color.lockedGreen
        }
    }

    private var selectedAverage: Double {
        if selectedRange == .week { return weeklyAverage }
        guard !relevantDailyTotals.isEmpty else { return 0 }
        return Double(relevantDailyTotals.reduce(0) { $0 + $1.steps }) / Double(relevantDailyTotals.count)
    }

    private var averageColor: Color {
        color(for: TrackingAnalytics.dailyStepStatus(steps: Int(selectedAverage.rounded())))
    }

    private var chartMaximum: Double {
        if selectedRange == .week {
            return Double(TrackingAnalytics.stepChartMaximum(chartPoints.map(\.steps)))
        }
        return max(1, Double(chartPoints.map(\.steps).max() ?? 0) * 1.1)
    }

    private func color(for status: TrackingAnalytics.Status) -> Color {
        switch status {
        case .red: return .red
        case .yellow: return .yellow
        case .green: return Color.lockedGreen
        }
    }

    private func barColor(for point: StepBarPoint) -> Color {
        guard selectedRange == .week else { return Color.lockedGreen }
        return color(for: TrackingAnalytics.dailyStepStatus(steps: point.steps))
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Zeitraum", selection: $selectedRange) {
                ForEach(StepRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            LockedCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("DURCHSCHNITT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(selectedAverage > 0 ? "Ø \(Int(selectedAverage.rounded()).formatted()) Schritte" : "—")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(selectedAverage > 0 ? averageColor : .primary)

                    Text("Ziel: 10.000 Schritte pro Tag")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !chartPoints.isEmpty {
                        Chart {
                            ForEach(chartPoints) { point in
                                BarMark(
                                    x: .value("Zeitraum", point.label),
                                    y: .value("Schritte", point.steps),
                                    width: .fixed(selectedRange == .week ? 24 : 10)
                                )
                                .foregroundStyle(barColor(for: point))
                            }

                            if selectedRange == .week {
                                RuleMark(y: .value("Ziel", 10_000))
                                    .foregroundStyle(Color.lockedGreen)
                                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                                    .annotation(position: .top, alignment: .trailing) {
                                        Text("Ziel 10.000")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Color.lockedGreen)
                                    }

                                if weeklyAverage > 0 {
                                    RuleMark(y: .value("Wochendurchschnitt", weeklyAverage))
                                        .foregroundStyle(Color.white.opacity(0.65))
                                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                                        .annotation(position: .bottom, alignment: .leading) {
                                            Text("Ø Woche \(Int(weeklyAverage.rounded()).formatted())")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.white.opacity(0.8))
                                        }
                                }
                            }
                        }
                        .chartXScale(domain: chartPoints.map(\.label))
                        .chartYScale(domain: 0...chartMaximum)
                        .frame(maxHeight: .infinity)
                        .frame(minHeight: 250)
                    }
                }
            }

            LockedCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("STEPS DIESE WOCHE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        Text(currentWeekTotal.formatted())
                            .foregroundStyle(weeklyProgressColor)
                        Text("/ 70.000")
                            .foregroundStyle(.primary)
                    }
                    .font(.title2.bold().monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
        .navigationTitle("Steps")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Steps nachtragen")
            }
        }
        .sheet(isPresented: $showAdd) { ManualStepEntryView() }
        .lockedSwipeBack()
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.bold().monospacedDigit())
        }
    }
}

struct WeightStatsDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightRecord.date) private var records: [WeightRecord]
    @StateObject private var scaleManager = EtekcityScaleManager()
    @State private var showAdd = false
    @State private var selectedRange: TrackingAnalytics.Range = .month
    @State private var didChooseInitialRange = false

    private var validRecords: [WeightRecord] {
        records.filter { !$0.isHidden && $0.weightKg > 0 }
    }

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        return value
    }

    private var weightSamples: [TrackingAnalytics.WeightSample] {
        validRecords.map {
            TrackingAnalytics.WeightSample(date: $0.date, weightKg: $0.weightKg)
        }
    }

    private var displayedPoints: [TrackingAnalytics.WeightPoint] {
        TrackingAnalytics.weightPoints(weightSamples, range: selectedRange, calendar: calendar)
    }

    private var chartDomain: ClosedRange<Date> {
        guard let first = displayedPoints.first?.weekStart,
              let last = displayedPoints.last?.weekStart else {
            let now = Date()
            return calendar.date(byAdding: .day, value: -3, to: now)!...calendar.date(byAdding: .day, value: 3, to: now)!
        }

        if first == last {
            return calendar.date(byAdding: .day, value: -3, to: first)!...calendar.date(byAdding: .day, value: 3, to: last)!
        }

        let spanDays = max(7, calendar.dateComponents([.day], from: first, to: last).day ?? 7)
        let paddingDays = max(2, min(21, spanDays / 20))
        return calendar.date(byAdding: .day, value: -paddingDays, to: first)!...calendar.date(byAdding: .day, value: paddingDays, to: last)!
    }

    private var currentWeekAverage: Double? {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return nil }
        let values = validRecords.filter { interval.contains($0.date) }.map(\.weightKg)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var previousWeekAverage: Double? {
        guard let current = calendar.dateInterval(of: .weekOfYear, for: Date()),
              let previousDate = calendar.date(byAdding: .day, value: -7, to: current.start),
              let previous = calendar.dateInterval(of: .weekOfYear, for: previousDate) else { return nil }
        let values = validRecords.filter { previous.contains($0.date) }.map(\.weightKg)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var weekChange: Double? {
        guard let currentWeekAverage, let previousWeekAverage else { return nil }
        return currentWeekAverage - previousWeekAverage
    }

    private var measurementsThisWeek: Int {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return validRecords.filter { interval.contains($0.date) }.count
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Zeitraum", selection: $selectedRange) {
                ForEach([TrackingAnalytics.Range.month, .year, .all]) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            LockedCard {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("WOCHENDURCHSCHNITT")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(currentWeekAverage.map { "\($0.cleanWeight) kg" } ?? "—")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("ZUR VORWOCHE")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(weekChange.map(signedWeight) ?? "—")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(changeColor)
                        }
                    }

                    Text("\(measurementsThisWeek) Messungen diese Woche")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if displayedPoints.count >= 2 {
                        Chart(displayedPoints) { point in
                            LineMark(
                                x: .value("Woche", point.weekStart),
                                y: .value("Ø Gewicht", point.averageKg)
                            )
                            .foregroundStyle(Color.lockedGreen)
                            .lineStyle(StrokeStyle(lineWidth: 3))

                            PointMark(
                                x: .value("Woche", point.weekStart),
                                y: .value("Ø Gewicht", point.averageKg)
                            )
                            .foregroundStyle(Color.lockedGreen)
                        }
                        .chartXScale(domain: chartDomain)
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let date = value.as(Date.self) {
                                        switch selectedRange {
                                        case .week:
                                            Text(date.formatted(.dateTime.day().month(.abbreviated)))
                                        case .month:
                                            Text(date.formatted(.dateTime.day().month(.abbreviated)))
                                        case .year:
                                            Text(date.formatted(.dateTime.month(.abbreviated)))
                                        case .all:
                                            Text(date.formatted(.dateTime.month(.abbreviated).year(.twoDigits)))
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: .infinity)
                        .frame(minHeight: 235)
                    } else {
                        ContentUnavailableView(
                            "Noch kein Wochentrend",
                            systemImage: "scalemass.fill",
                            description: Text("Wiege dich regelmäßig. Ab zwei Wochen zeigt LOCKED IN hier die geglättete Entwicklung.")
                        )
                        .frame(minHeight: 215)
                    }
                }
            }

            Button {
                scaleManager.startMeasurement()
            } label: {
                Label("Von Waage übernehmen", systemImage: "scalemass.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(LockedActionButtonStyle(prominent: true))

            HStack(spacing: 10) {
                Button {
                    showAdd = true
                } label: {
                    Label("Manuell eintragen", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(LockedActionButtonStyle())

                NavigationLink {
                    WeightHistoryView()
                } label: {
                    Label("Verlauf", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(LockedActionButtonStyle())
            }

            if !scaleManager.state.message.isEmpty {
                Text(scaleManager.state.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
        .navigationTitle("Gewicht")
        .sheet(isPresented: $showAdd) {
            ManualWeightEntryView()
        }
        .onAppear {
            if !didChooseInitialRange {
                selectedRange = TrackingAnalytics.defaultWeightRange(
                    weightSamples,
                    calendar: calendar
                )
                if selectedRange == .week {
                    selectedRange = .month
                }
                didChooseInitialRange = true
            }

            scaleManager.onMeasurement = { weight in
                let existing = validRecords.filter { $0.source == EtekcityScaleManager.sourceID }
                for record in existing where abs(record.date.timeIntervalSinceNow) < 120 {
                    modelContext.delete(record)
                }

                modelContext.insert(
                    WeightRecord(
                        date: Date(),
                        weightKg: weight,
                        source: EtekcityScaleManager.sourceID
                    )
                )
                try? modelContext.save()
                try? AutomaticBackup.backup(modelContext: modelContext)
            }
        }
        .lockedSwipeBack()
    }

    private var changeColor: Color {
        guard let weekChange else { return .secondary }
        if weekChange < -0.05 { return Color.lockedGreen }
        if weekChange > 0.05 { return .red }
        return .yellow
    }

    private func signedWeight(_ value: Double) -> String {
        if abs(value) < 0.05 { return "0,0 kg" }
        return String(format: "%+.1f kg", value)
            .replacingOccurrences(of: ".", with: ",")
    }
}
