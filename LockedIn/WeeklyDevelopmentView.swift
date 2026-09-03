import Charts
import SwiftData
import SwiftUI

struct WeeklyDevelopmentView: View {
    enum Category: String, CaseIterable, Identifiable {
        case strength = "Kraft"
        case runs = "Läufe"
        case steps = "Steps"
        case weight = "Gewicht"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .strength: return "dumbbell.fill"
            case .runs: return "figure.run"
            case .steps: return "shoeprints.fill"
            case .weight: return "scalemass.fill"
            }
        }
    }

    struct WeekPoint: Identifiable {
        let weekStart: Date
        let value: Double
        let count: Int
        let formattedValue: String
        var id: Date { weekStart }
    }

    private struct ChartPoint: Identifiable {
        let point: WeekPoint
        let segment: Int
        var id: Date { point.weekStart }
    }

    @Query(sort: \WorkoutRecord.startedAt) private var workouts: [WorkoutRecord]
    @Query private var sets: [SetRecord]
    @Query(sort: \RunRecord.date) private var runs: [RunRecord]
    @Query(sort: \StepRecord.date) private var steps: [StepRecord]
    @Query(sort: \WeightRecord.date) private var weights: [WeightRecord]
    @AppStorage("developmentSelectedCategory") private var selectedCategoryRaw = Category.strength.rawValue

    let reportOnly: Bool

    init(reportOnly: Bool = false) {
        self.reportOnly = reportOnly
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private var selectedCategory: Binding<Category> {
        Binding(
            get: { Category(rawValue: selectedCategoryRaw) ?? .strength },
            set: { selectedCategoryRaw = $0.rawValue }
        )
    }

    private var completedWeeks: [DateInterval] {
        guard let current = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return Array((1...6).compactMap { offset in
            guard let date = calendar.date(byAdding: .weekOfYear, value: -offset, to: current.start) else { return nil }
            return calendar.dateInterval(of: .weekOfYear, for: date)
        }.reversed())
    }

    var body: some View {
        NavigationStack {
            Group {
                if reportOnly {
                    reportContent
                } else {
                    developmentContent
                }
            }
            .background(Color.black)
            .navigationTitle(reportOnly ? "Entwicklung letzte Woche" : "Entwicklung")
        }
    }

    private var developmentContent: some View {
        VStack(spacing: 14) {
            Picker("Bereich", selection: selectedCategory) {
                ForEach(Category.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)

            let category = selectedCategory.wrappedValue
            let points = points(for: category)

            LockedCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("LETZTE 6 WOCHEN")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(latestPoint(in: points)?.formattedValue ?? "Keine Daten")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        Spacer()
                        changeLabel(points, category: category)
                    }

                    if points.count >= 2 {
                        Chart(chartPoints(from: points)) { item in
                            LineMark(
                                x: .value("Woche", item.point.weekStart),
                                y: .value("Wert", item.point.value),
                                series: .value("Abschnitt", item.segment)
                            )
                                .foregroundStyle(Color.lockedGreen)
                                .lineStyle(StrokeStyle(lineWidth: 3))
                            PointMark(x: .value("Woche", item.point.weekStart), y: .value("Wert", item.point.value))
                                .foregroundStyle(Color.lockedGreen)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .weekOfYear)) { value in
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            }
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "Noch kein Wochenvergleich",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Mindestens zwei abgeschlossene Wochen mit Daten werden benötigt.")
                        )
                        .frame(maxHeight: .infinity)
                    }

                    HStack {
                        Text(countLabel(for: category))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(latestPoint(in: points)?.count.formatted() ?? "—")
                            .font(.headline.monospacedDigit())
                    }
                }
            }
            .frame(maxHeight: .infinity)

            LockedCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("LETZTE WOCHEN")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lockedGreen)
                    ForEach(Array(completedWeeks.suffix(3).reversed()), id: \.start) { interval in
                        let point = points.first { $0.weekStart == interval.start }
                        HStack {
                            Text(weekLabel(interval.start))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(point?.formattedValue ?? "Keine Daten")
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var reportContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Dein Vergleich zur Woche davor")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Category.allCases) { category in
                    let categoryPoints = reportPoints(for: category)
                    LockedCard {
                        HStack(spacing: 14) {
                            Image(systemName: category.icon)
                                .font(.title2)
                                .foregroundStyle(Color.lockedGreen)
                                .frame(width: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(category.rawValue.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(latestPoint(in: categoryPoints)?.formattedValue ?? "Keine Daten")
                                    .font(.title3.bold().monospacedDigit())
                            }
                            Spacer()
                            changeLabel(categoryPoints, category: category)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func changeLabel(_ points: [WeekPoint], category: Category) -> some View {
        let change = adjacentWeekChange(in: points)
        VStack(alignment: .trailing, spacing: 2) {
            Text("ZUR VORWOCHE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(change.map { String(format: "%+.1f %%", $0).replacingOccurrences(of: ".", with: ",") } ?? "—")
                .font(.headline.monospacedDigit())
                .foregroundStyle(changeColor(change, category: category))
        }
    }

    private func points(for category: Category) -> [WeekPoint] {
        switch category {
        case .strength: return strengthPoints()
        case .runs: return runPoints()
        case .steps: return stepPoints()
        case .weight: return weightPoints()
        }
    }

    private func reportPoints(for category: Category) -> [WeekPoint] {
        let reportWeeks = Set(completedWeeks.suffix(2).map(\.start))
        return points(for: category).filter { reportWeeks.contains($0.weekStart) }
    }

    private func latestPoint(in points: [WeekPoint]) -> WeekPoint? {
        guard let latestWeek = completedWeeks.last?.start else { return nil }
        return points.first { $0.weekStart == latestWeek }
    }

    private func adjacentWeekChange(in points: [WeekPoint]) -> Double? {
        guard completedWeeks.count >= 2 else { return nil }
        let latestWeek = completedWeeks[completedWeeks.count - 1].start
        let previousWeek = completedWeeks[completedWeeks.count - 2].start
        guard let latest = points.first(where: { $0.weekStart == latestWeek }),
              let previous = points.first(where: { $0.weekStart == previousWeek }) else {
            return nil
        }
        return TrackingAnalytics.percentageChange(from: previous.value, to: latest.value)
    }

    private func chartPoints(from points: [WeekPoint]) -> [ChartPoint] {
        var previousIndex: Int?
        var segment = 0
        return points.compactMap { point in
            guard let index = completedWeeks.firstIndex(where: { $0.start == point.weekStart }) else { return nil }
            if let previousIndex, index != previousIndex + 1 {
                segment += 1
            }
            previousIndex = index
            return ChartPoint(point: point, segment: segment)
        }
    }

    private func strengthPoints() -> [WeekPoint] {
        var index = 100.0
        let completed = workouts.filter { $0.isCompleted && !$0.isHidden }.sorted { $0.startedAt < $1.startedAt }
        var result: [WeekPoint] = []
        for interval in completedWeeks {
            let weekly = completed.filter { interval.contains($0.startedAt) }
            for workout in weekly {
                if let delta = StrengthProgressMetric.workoutProgress(workout: workout, workouts: workouts, sets: sets) {
                    index *= max(0, 1 + delta / 100)
                }
            }
            guard !weekly.isEmpty else { continue }
            result.append(WeekPoint(weekStart: interval.start, value: index, count: weekly.count, formattedValue: String(format: "%.1f", index).replacingOccurrences(of: ".", with: ",")))
        }
        return result
    }

    private func runPoints() -> [WeekPoint] {
        let raw = completedWeeks.compactMap { interval -> (DateInterval, TrackingAnalytics.RunSummary)? in
            let samples = runs.filter { !$0.isHidden && interval.contains($0.date) }.map {
                TrackingAnalytics.RunSample(date: $0.date, distanceKm: $0.distanceKm, durationSeconds: $0.durationSeconds)
            }
            let summary = TrackingAnalytics.runSummary(samples)
            return summary.count > 0 ? (interval, summary) : nil
        }
        guard let baseline = raw.first?.1,
              baseline.averageDistanceKm > 0,
              baseline.weightedPaceSecondsPerKm > 0 else { return [] }
        return raw.map { interval, summary in
            let distanceIndex = summary.averageDistanceKm / baseline.averageDistanceKm
            let paceIndex = baseline.weightedPaceSecondsPerKm / summary.weightedPaceSecondsPerKm
            let index = sqrt(distanceIndex * paceIndex) * 100
            return WeekPoint(weekStart: interval.start, value: index, count: summary.count, formattedValue: String(format: "%.1f", index).replacingOccurrences(of: ".", with: ","))
        }
    }

    private func stepPoints() -> [WeekPoint] {
        let preferred = TrackingAnalytics.preferredStepSamples(steps.map {
            TrackingAnalytics.StepSample(date: $0.date, steps: $0.steps, source: $0.source)
        }, calendar: calendar)
        return completedWeeks.compactMap { interval in
            let weekly = preferred.filter { interval.contains($0.date) }
            guard let average = TrackingAnalytics.recordedStepAverage(weekly, calendar: calendar) else { return nil }
            return WeekPoint(weekStart: interval.start, value: Double(average), count: weekly.count, formattedValue: "Ø \(average.formatted())")
        }
    }

    private func weightPoints() -> [WeekPoint] {
        completedWeeks.compactMap { interval in
            let weekly = weights.filter { !$0.isHidden && interval.contains($0.date) }
            guard !weekly.isEmpty else { return nil }
            let average = weekly.reduce(0) { $0 + $1.weightKg } / Double(weekly.count)
            return WeekPoint(weekStart: interval.start, value: average, count: weekly.count, formattedValue: "\(average.cleanWeight) kg")
        }
    }

    private func countLabel(for category: Category) -> String {
        switch category {
        case .strength: return "TRAININGS IN DER LETZTEN WOCHE"
        case .runs: return "LÄUFE IN DER LETZTEN WOCHE"
        case .steps: return "ERFASSTE TAGE IN DER LETZTEN WOCHE"
        case .weight: return "MESSUNGEN IN DER LETZTEN WOCHE"
        }
    }

    private func weekLabel(_ date: Date) -> String {
        "KW \(calendar.component(.weekOfYear, from: date))"
    }

    private func changeColor(_ change: Double?, category: Category) -> Color {
        guard let change else { return .secondary }
        let directedChange = category == .weight ? -change : change
        if directedChange > 0.05 { return Color.lockedGreen }
        if directedChange < -0.05 { return .red }
        return .yellow
    }
}
