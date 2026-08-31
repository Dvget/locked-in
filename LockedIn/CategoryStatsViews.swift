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

    private var chartPoints: [RunDistancePoint] {
        validRuns.map { RunDistancePoint(date: $0.date, distanceKm: $0.distanceKm) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LockedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LAUFENTWICKLUNG")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if chartPoints.isEmpty {
                            ContentUnavailableView(
                                "Noch keine Laufdaten",
                                systemImage: "figure.run",
                                description: Text("Sobald Läufe vorhanden sind, erscheint hier die Gesamtübersicht.")
                            )
                            .frame(height: 220)
                        } else {
                            Chart(chartPoints) { point in
                                LineMark(
                                    x: .value("Datum", point.date),
                                    y: .value("Distanz", point.distanceKm)
                                )
                                .foregroundStyle(Color.lockedGreen)
                                PointMark(
                                    x: .value("Datum", point.date),
                                    y: .value("Distanz", point.distanceKm)
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

    private var dailyTotals: [(date: Date, steps: Int)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { date, items in
                (date: date, steps: items.reduce(0) { $0 + $1.steps })
            }
            .sorted { $0.date < $1.date }
    }

    private var totalSteps: Int {
        dailyTotals.reduce(0) { $0 + $1.steps }
    }

    private var averageSteps: Double {
        dailyTotals.isEmpty ? 0 : Double(totalSteps) / Double(dailyTotals.count)
    }

    private var trendPoints: [StepAveragePoint] {
        guard !dailyTotals.isEmpty else { return [] }

        var runningTotal = 0
        return dailyTotals.enumerated().map { index, item in
            runningTotal += item.steps
            return StepAveragePoint(
                date: item.date,
                averageSteps: Double(runningTotal) / Double(index + 1)
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LockedCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GESAMTDURCHSCHNITT")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(averageSteps > 0 ? "Ø \(Int(averageSteps.rounded()).formatted())" : "—")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(averageSteps >= 10_000 ? Color.lockedGreen : .primary)

                        Text("Ziel: 10.000 Schritte pro Tag")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if !trendPoints.isEmpty {
                            Chart(trendPoints) { point in
                                LineMark(
                                    x: .value("Datum", point.date),
                                    y: .value("Ø Schritte", point.averageSteps)
                                )
                                .foregroundStyle(Color.lockedGreen)

                                RuleMark(y: .value("Ziel", 10_000))
                                    .foregroundStyle(.secondary)
                                    .lineStyle(StrokeStyle(dash: [5, 5]))
                            }
                            .frame(height: 250)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                LockedCard {
                    HStack {
                        metric(title: "ERFASSTE TAGE", value: dailyTotals.count.formatted())
                        Spacer()
                        metric(title: "GESAMTSCHRITTE", value: totalSteps.formatted())
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
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
                .font(.title3.bold().monospacedDigit())
        }
    }
}

struct WeightStatsDetailView: View {
    @Query(sort: \WeightRecord.date) private var records: [WeightRecord]
    @State private var showAdd = false

    private var validRecords: [WeightRecord] {
        records.filter { $0.weightKg > 0 }
    }

    private var currentWeight: Double? {
        validRecords.last?.weightKg
    }

    private var firstWeight: Double? {
        validRecords.first?.weightKg
    }

    private var change: Double? {
        guard let firstWeight, let currentWeight else { return nil }
        return currentWeight - firstWeight
    }

    private var minWeight: Double? {
        validRecords.map(\.weightKg).min()
    }

    private var maxWeight: Double? {
        validRecords.map(\.weightKg).max()
    }

    private var chartPoints: [WeightPoint] {
        validRecords.enumerated().map { index, record in
            let start = max(0, index - 6)
            let slice = validRecords[start...index]
            let trend = slice.map(\.weightKg).reduce(0, +) / Double(slice.count)
            return WeightPoint(date: record.date, weightKg: record.weightKg, trendKg: trend)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LockedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("AKTUELLES GEWICHT")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(currentWeight.map { "\($0.cleanWeight) kg" } ?? "—")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("SEIT BEGINN")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(change.map { signedWeight($0) } ?? "—")
                                    .font(.headline.monospacedDigit())
                            }
                        }

                        if chartPoints.isEmpty {
                            ContentUnavailableView(
                                "Noch keine Gewichtsdaten",
                                systemImage: "scalemass.fill",
                                description: Text("Gewichtsdaten werden hier langfristig dargestellt und später automatisch mit Apple Health synchronisiert.")
                            )
                            .frame(height: 220)
                        } else {
                            Chart(chartPoints) { point in
                                LineMark(
                                    x: .value("Datum", point.date),
                                    y: .value("Gewicht", point.weightKg)
                                )
                                .foregroundStyle(.secondary)

                                if let trend = point.trendKg {
                                    LineMark(
                                        x: .value("Datum", point.date),
                                        y: .value("Trend", trend)
                                    )
                                    .foregroundStyle(Color.lockedGreen)
                                    .lineStyle(StrokeStyle(lineWidth: 3))
                                }
                            }
                            .frame(height: 250)
                        }
                    }
                }

                LockedCard {
                    HStack {
                        metric(title: "NIEDRIGSTER WERT", value: minWeight.map { "\($0.cleanWeight) kg" } ?? "—")
                        Spacer()
                        metric(title: "HÖCHSTER WERT", value: maxWeight.map { "\($0.cleanWeight) kg" } ?? "—")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black)
        .navigationTitle("Gewicht")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            ManualWeightEntryView()
        }
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

    private func signedWeight(_ value: Double) -> String {
        if abs(value) < 0.05 { return "0,0 kg" }
        return String(format: "%+.1f kg", value)
            .replacingOccurrences(of: ".", with: ",")
    }
}
