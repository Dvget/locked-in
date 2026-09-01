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

    private var completedWorkouts: [WorkoutRecord] {
        workouts
            .filter { $0.isCompleted && !$0.isHidden }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private var cumulativePoints: [ProgressPoint] {
        guard let first = completedWorkouts.first else { return [] }

        var result: [ProgressPoint] = [
            ProgressPoint(date: first.startedAt, value: 100)
        ]
        var index = 100.0

        for workout in completedWorkouts.dropFirst() {
            guard let delta = StrengthProgressMetric.workoutProgress(
                workout: workout,
                workouts: workouts,
                sets: sets
            ) else { continue }

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
        return StrengthProgressMetric.workoutProgress(
            workout: last,
            workouts: workouts,
            sets: sets
        )
    }

    private var trainingFrequency: Double {
        guard let first = completedWorkouts.first, let last = completedWorkouts.last else { return 0 }
        let days = max(1, Calendar.current.dateComponents([.day], from: first.startedAt, to: last.startedAt).day ?? 0)
        let weeks = max(1.0, Double(days + 1) / 7.0)
        return Double(completedWorkouts.count) / weeks
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LockedCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("GESAMTLEISTUNGSINDEX")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(cumulativePoints.last.map { String(format: "%.1f", $0.value).replacingOccurrences(of: ".", with: ",") } ?? "—")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("SEIT BEGINN")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(StrengthProgressMetric.text(totalChange))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(StrengthProgressStyle.color(for: totalChange))
                            }
                        }

                        if cumulativePoints.count < 2 {
                            ContentUnavailableView(
                                "Noch kein Gesamttrend",
                                systemImage: "chart.xyaxis.line",
                                description: Text("Für den Gesamttrend werden mindestens zwei vergleichbare Trainings benötigt.")
                            )
                            .frame(height: 220)
                        } else {
                            Chart(cumulativePoints) { point in
                                LineMark(
                                    x: .value("Datum", point.date),
                                    y: .value("Index", point.value)
                                )
                                .foregroundStyle(Color.lockedGreen)

                                PointMark(
                                    x: .value("Datum", point.date),
                                    y: .value("Index", point.value)
                                )
                                .foregroundStyle(Color.lockedGreen)
                            }
                            .frame(height: 250)
                        }
                    }
                }

                LockedCard {
                    VStack(spacing: 14) {
                        HStack {
                            metric(
                                title: "LETZTES TRAINING",
                                value: StrengthProgressMetric.text(latestWorkoutChange),
                                valueColor: StrengthProgressStyle.color(for: latestWorkoutChange)
                            )
                            Spacer()
                            metric(
                                title: "TRAININGS",
                                value: completedWorkouts.count.formatted()
                            )
                        }

                        Divider().overlay(Color.lockedBorder)

                        HStack {
                            metric(
                                title: "Ø PRO WOCHE",
                                value: trainingFrequency == 0 ? "—" : String(format: "%.1f", trainingFrequency).replacingOccurrences(of: ".", with: ",")
                            )
                            Spacer()
                            metric(
                                title: "BASISINDEX",
                                value: "100,0"
                            )
                        }
                    }
                }

                NavigationLink {
                    ExerciseStatsView()
                } label: {
                    LockedCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("EINZELNE ÜBUNGEN")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("Übungsfortschritt ansehen")
                                    .font(.headline)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black)
        .navigationTitle("Krafttraining")
        .lockedSwipeBack()
    }

    private func metric(title: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(valueColor)
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
        workouts
            .filter { $0.isCompleted && !$0.isHidden }
            .compactMap { workout in
                guard let progress = StrengthProgressMetric.exerciseProgress(
                    exerciseID: exerciseID,
                    workout: workout,
                    workouts: workouts,
                    sets: sets
                ) else { return nil }
                return ProgressPoint(date: workout.startedAt, value: progress)
            }
            .sorted { $0.date < $1.date }
    }

    private var current: Double? { points.last?.value }

    private var average: Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
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
                                Text("LEISTUNGSFORTSCHRITT")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(StrengthProgressMetric.text(current))
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(StrengthProgressStyle.color(for: current))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Ø")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(StrengthProgressMetric.text(average))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(StrengthProgressStyle.color(for: average))
                            }
                        }

                        if points.isEmpty {
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
                                            Text(String(format: "%.0f%%", number))
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
        .navigationTitle("Übungen")
        .lockedSwipeBack()
    }
}

struct RunStatsDetailView: View {
    @Query(sort: \RunRecord.date) private var runs: [RunRecord]

    private var validRuns: [RunRecord] {
        runs.filter { $0.distanceKm > 0 && $0.durationSeconds > 0 }
    }

    private var totalDistance: Double {
        validRuns.reduce(0) { $0 + $1.distanceKm }
    }

    private var totalDuration: Double {
        validRuns.reduce(0) { $0 + $1.durationSeconds }
    }

    private var averageDistance: Double {
        validRuns.isEmpty ? 0 : totalDistance / Double(validRuns.count)
    }

    private var weightedPace: Double {
        totalDistance > 0 ? totalDuration / totalDistance : 0
    }

    private var progressPoints: [RunProgressMetric.Point] {
        RunProgressMetric.points(for: validRuns)
    }

    private var latestOverall: Double? {
        progressPoints.last?.overallIndex
    }

    private var overallChange: Double? {
        RunProgressMetric.changeFromBaseline(for: validRuns)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LockedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("LAUFENTWICKLUNG")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(latestOverall.map { RunProgressMetric.text($0) } ?? "—")
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 3) {
                                Text("SEIT BEGINN")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(overallChange.map { String(format: "%+.1f %%", $0).replacingOccurrences(of: ".", with: ",") } ?? "—")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle((overallChange ?? 0) >= 0 ? Color.lockedGreen : .red)
                            }
                        }

                        if progressPoints.isEmpty {
                            ContentUnavailableView(
                                "Noch keine Laufdaten",
                                systemImage: "figure.run",
                                description: Text("Sobald Läufe vorhanden sind, erscheinen hier Distanz, Pace und Gesamtentwicklung.")
                            )
                            .frame(height: 220)
                        } else {
                            Chart {
                                ForEach(progressPoints, id: \.date) { point in
                                    LineMark(
                                        x: .value("Datum", point.date),
                                        y: .value("Distanz-Index", point.distanceIndex),
                                        series: .value("Metrik", "Distanz")
                                    )
                                    .foregroundStyle(by: .value("Metrik", "Distanz"))

                                    LineMark(
                                        x: .value("Datum", point.date),
                                        y: .value("Pace-Index", point.paceIndex),
                                        series: .value("Metrik", "Pace")
                                    )
                                    .foregroundStyle(by: .value("Metrik", "Pace"))

                                    LineMark(
                                        x: .value("Datum", point.date),
                                        y: .value("Gesamt-Index", point.overallIndex),
                                        series: .value("Metrik", "Gesamt")
                                    )
                                    .foregroundStyle(by: .value("Metrik", "Gesamt"))
                                    .lineStyle(StrokeStyle(lineWidth: 3))
                                }
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartLegend(position: .bottom, alignment: .leading)
                            .frame(height: 280)

                            Text("Index 100 = dein erster erfasster Lauf. Distanz und Pace werden auf dieselbe Skala normiert; der Gesamtwert kombiniert beide.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                LockedCard {
                    VStack(spacing: 14) {
                        HStack {
                            metric(title: "LÄUFE", value: validRuns.count.formatted())
                            Spacer()
                            metric(title: "GESAMTDISTANZ", value: totalDistance > 0 ? "\(totalDistance.cleanWeight) km" : "—")
                        }

                        Divider().overlay(Color.lockedBorder)

                        HStack {
                            metric(title: "GESAMTZEIT", value: totalDuration > 0 ? formatLongDuration(totalDuration) : "—")
                            Spacer()
                            metric(title: "Ø DISTANZ", value: averageDistance > 0 ? "\(averageDistance.cleanWeight) km" : "—")
                        }

                        Divider().overlay(Color.lockedBorder)

                        HStack {
                            metric(title: "Ø PACE", value: weightedPace > 0 ? "\(formatPace(weightedPace)) /km" : "—")
                            Spacer()
                            metric(title: "GESAMTINDEX", value: latestOverall.map { RunProgressMetric.text($0) } ?? "—")
                        }
                    }
                }

                if !validRuns.isEmpty {
                    LockedCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("EINZELWERTE")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(validRuns.reversed(), id: \.id) { run in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(run.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(run.distanceKm.cleanWeight) km · \(formatPace(run.paceSecondsPerKm)) /km")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(formatLongDuration(run.durationSeconds))
                                        .font(.subheadline.monospacedDigit())
                                }
                            }

                            Text("Herzfrequenz wird hier ergänzt, sobald eine spätere Datenquelle sie zuverlässig liefert.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black)
        .navigationTitle("Läufe")
        .lockedSwipeBack()
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
        }
    }

    private func formatLongDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d h", hours, minutes)
        }
        return "\(minutes) min"
    }

    private func formatPace(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct StepStatsDetailView: View {
    @Query(sort: \StepRecord.date) private var records: [StepRecord]
    @State private var selectedRange: StepRange = .week

    private enum StepRange: String, CaseIterable, Identifiable {
        case week = "Woche"
        case month = "Monat"
        case sixMonths = "6 Mon."
        case year = "Jahr"

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
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { date, items in
                (date: date, steps: items.reduce(0) { $0 + $1.steps })
            }
            .sorted { $0.date < $1.date }
    }

    private var relevantDailyTotals: [(date: Date, steps: Int)] {
        let now = Date()
        switch selectedRange {
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
            return dailyTotals.filter { interval.contains($0.date) }
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: now) else { return [] }
            return dailyTotals.filter { interval.contains($0.date) }
        case .sixMonths:
            guard let start = calendar.date(byAdding: .month, value: -5, to: calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now) else { return [] }
            return dailyTotals.filter { $0.date >= start && $0.date <= now }
        case .year:
            guard let interval = calendar.dateInterval(of: .year, for: now) else { return [] }
            return dailyTotals.filter { interval.contains($0.date) }
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

        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: now) else { return [] }
            return dailyTotals.filter { interval.contains($0.date) }.map {
                StepBarPoint(label: "\(calendar.component(.day, from: $0.date))", date: $0.date, steps: $0.steps)
            }

        case .sixMonths:
            guard let start = calendar.date(byAdding: .month, value: -5, to: calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now) else { return [] }
            let grouped = Dictionary(grouping: dailyTotals.filter { $0.date >= start }) {
                calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date)) ?? $0.date
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.dateFormat = "MMM"
            return grouped.map { date, items in
                StepBarPoint(label: formatter.string(from: date), date: date, steps: items.reduce(0) { $0 + $1.steps })
            }.sorted { $0.date < $1.date }

        case .year:
            guard let interval = calendar.dateInterval(of: .year, for: now) else { return [] }
            let grouped = Dictionary(grouping: dailyTotals.filter { interval.contains($0.date) }) {
                calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date)) ?? $0.date
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.dateFormat = "MMM"
            return grouped.map { date, items in
                StepBarPoint(label: formatter.string(from: date), date: date, steps: items.reduce(0) { $0 + $1.steps })
            }.sorted { $0.date < $1.date }
        }
    }

    private var selectedAverage: Double {
        guard !relevantDailyTotals.isEmpty else { return 0 }
        return Double(relevantDailyTotals.reduce(0) { $0 + $1.steps }) / Double(relevantDailyTotals.count)
    }

    private var averageColor: Color {
        switch Int(selectedAverage.rounded()) {
        case ...4_000: return .red
        case 4_001..<7_500: return .yellow
        default: return Color.lockedGreen
        }
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
                        Chart(chartPoints) { point in
                            BarMark(
                                x: .value("Zeitraum", point.label),
                                y: .value("Schritte", point.steps)
                            )
                            .foregroundStyle(Color.lockedGreen)

                            if selectedRange == .week || selectedRange == .month {
                                RuleMark(y: .value("Ziel", 10_000))
                                    .foregroundStyle(.secondary)
                                    .lineStyle(StrokeStyle(dash: [5, 5]))
                            }
                        }
                        .chartXScale(domain: chartPoints.map(\.label))
                        .frame(maxHeight: .infinity)
                        .frame(minHeight: 250)
                    }
                }
            }

            LockedCard {
                HStack {
                    metric(title: "ERFASSTE TAGE", value: relevantDailyTotals.count.formatted())
                    Spacer()
                    metric(title: "GESAMTSCHRITTE", value: relevantDailyTotals.reduce(0) { $0 + $1.steps }.formatted())
                    Spacer()
                    metric(title: "BESTER TAG", value: relevantDailyTotals.map(\.steps).max()?.formatted() ?? "—")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
        .navigationTitle("Steps")
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

    private struct WeeklyWeightPoint: Identifiable {
        let id = UUID()
        let weekStart: Date
        let averageKg: Double
    }

    private var validRecords: [WeightRecord] {
        records.filter { $0.weightKg > 0 }
    }

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        return value
    }

    private var weeklyPoints: [WeeklyWeightPoint] {
        let grouped = Dictionary(grouping: validRecords) { record in
            calendar.dateInterval(of: .weekOfYear, for: record.date)?.start ?? calendar.startOfDay(for: record.date)
        }

        return grouped.map { start, items in
            WeeklyWeightPoint(
                weekStart: start,
                averageKg: items.map(\.weightKg).reduce(0, +) / Double(items.count)
            )
        }
        .sorted { $0.weekStart < $1.weekStart }
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
            LockedCard {
                VStack(alignment: .leading, spacing: 10) {
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

                    if weeklyPoints.count >= 2 {
                        Chart(weeklyPoints) { point in
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
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(maxHeight: .infinity)
                        .frame(minHeight: 240)
                    } else {
                        ContentUnavailableView(
                            "Noch kein Wochentrend",
                            systemImage: "scalemass.fill",
                            description: Text("Wiege dich regelmäßig. Ab zwei Wochen zeigt LOCKED IN hier die geglättete Entwicklung.")
                        )
                        .frame(minHeight: 220)
                    }
                }
            }

            Button {
                scaleManager.startMeasurement()
            } label: {
                Label("Von Waage übernehmen", systemImage: "scalemass.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(LockedActionButtonStyle(prominent: true))

            HStack(spacing: 10) {
                Button {
                    showAdd = true
                } label: {
                    Label("Manuell eintragen", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(LockedActionButtonStyle())

                NavigationLink {
                    WeightHistoryView()
                } label: {
                    Label("Verlauf", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
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
