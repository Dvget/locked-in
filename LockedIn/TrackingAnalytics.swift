import Foundation

enum TrackingAnalytics {
    enum RunSeries {
        case overall
        case distance
        case pace
    }

    enum Range: String, CaseIterable, Identifiable {
        case week = "Woche"
        case month = "Monat"
        case year = "Jahr"
        case all = "Gesamt"

        var id: String { rawValue }
    }

    enum Status: Equatable {
        case red
        case yellow
        case green
    }

    struct RunSample {
        let date: Date
        let distanceKm: Double
        let durationSeconds: Double

        var paceSecondsPerKm: Double {
            guard distanceKm > 0 else { return 0 }
            return durationSeconds / distanceKm
        }
    }

    struct RunSummary {
        let count: Int
        let totalDistanceKm: Double
        let averageDistanceKm: Double
        let weightedPaceSecondsPerKm: Double

        static let empty = RunSummary(
            count: 0,
            totalDistanceKm: 0,
            averageDistanceKm: 0,
            weightedPaceSecondsPerKm: 0
        )
    }

    struct StepSample {
        let date: Date
        let steps: Int
        let source: String
    }

    struct StrengthSetSample {
        let weightKg: Double
        let reps: Int
        let repsOnly: Bool
    }

    struct ExerciseSetSample {
        let weightKg: Double
        let reps: Int
    }

    struct ExerciseWorkoutMetrics {
        let maximumWeightKg: Double?
        let totalReps: Int
    }

    struct StepBucket: Identifiable {
        let date: Date
        let label: String
        let steps: Int

        var id: Date { date }
    }

    struct WeightSample {
        let date: Date
        let weightKg: Double
    }

    struct WeightPoint: Identifiable {
        let weekStart: Date
        let averageKg: Double

        var id: Date { weekStart }
    }

    static func runSummary(
        _ samples: [RunSample],
        rollingDays: Int? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> RunSummary {
        let valid = samples.filter { $0.distanceKm > 0 && $0.durationSeconds > 0 }
        let filtered: [RunSample]

        if let rollingDays {
            let today = calendar.startOfDay(for: now)
            let cutoff = calendar.date(
                byAdding: .day,
                value: -(max(1, rollingDays) - 1),
                to: today
            ) ?? .distantPast
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            filtered = valid.filter { $0.date >= cutoff && $0.date < end }
        } else {
            filtered = valid
        }

        guard !filtered.isEmpty else { return .empty }
        let distance = filtered.reduce(0) { $0 + $1.distanceKm }
        let duration = filtered.reduce(0) { $0 + $1.durationSeconds }

        return RunSummary(
            count: filtered.count,
            totalDistanceKm: distance,
            averageDistanceKm: distance / Double(filtered.count),
            weightedPaceSecondsPerKm: distance > 0 ? duration / distance : 0
        )
    }

    static func weeklyRunChange(
        _ samples: [RunSample],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double? {
        guard let current = calendar.dateInterval(of: .weekOfYear, for: now),
              let previousDate = calendar.date(byAdding: .day, value: -7, to: current.start),
              let previous = calendar.dateInterval(of: .weekOfYear, for: previousDate) else {
            return nil
        }

        let currentSummary = runSummary(samples.filter { current.contains($0.date) })
        let previousSummary = runSummary(samples.filter { previous.contains($0.date) })
        guard currentSummary.count > 0,
              previousSummary.count > 0,
              currentSummary.averageDistanceKm > 0,
              previousSummary.averageDistanceKm > 0,
              currentSummary.weightedPaceSecondsPerKm > 0,
              previousSummary.weightedPaceSecondsPerKm > 0 else {
            return nil
        }

        let distanceIndex = currentSummary.averageDistanceKm / previousSummary.averageDistanceKm
        let paceIndex = previousSummary.weightedPaceSecondsPerKm / currentSummary.weightedPaceSecondsPerKm
        return (sqrt(distanceIndex * paceIndex) - 1) * 100
    }

    static func runSeriesChange(
        _ samples: [RunSample],
        series: RunSeries
    ) -> Double? {
        let valid = samples
            .filter { $0.distanceKm > 0 && $0.durationSeconds > 0 }
            .sorted { $0.date < $1.date }
        guard let first = valid.first, let last = valid.last, valid.count > 1 else { return nil }

        switch series {
        case .overall:
            return runChange(current: last, previous: first)
        case .distance:
            return ((last.distanceKm / first.distanceKm) - 1) * 100
        case .pace:
            return ((first.paceSecondsPerKm / last.paceSecondsPerKm) - 1) * 100
        }
    }

    static func runChange(current: RunSample, previous: RunSample) -> Double? {
        guard current.distanceKm > 0,
              current.durationSeconds > 0,
              previous.distanceKm > 0,
              previous.durationSeconds > 0 else {
            return nil
        }

        let distanceRatio = current.distanceKm / previous.distanceKm
        let paceRatio = previous.paceSecondsPerKm / current.paceSecondsPerKm
        return (sqrt(distanceRatio * paceRatio) - 1) * 100
    }

    static func preferredStepSamples(
        _ samples: [StepSample],
        calendar: Calendar = .current
    ) -> [StepSample] {
        let grouped = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date) }

        return grouped.compactMap { day, values in
            let automatic = values.filter { $0.source == "coremotion" }
            guard let selected = (automatic.isEmpty ? values : automatic).max(by: { $0.steps < $1.steps }) else {
                return nil
            }
            return StepSample(date: day, steps: max(0, selected.steps), source: selected.source)
        }
        .sorted { $0.date < $1.date }
    }

    static func recordedStepAverage(
        _ samples: [StepSample],
        calendar: Calendar = .current
    ) -> Int? {
        let preferred = preferredStepSamples(samples, calendar: calendar)
        guard !preferred.isEmpty else { return nil }
        return preferred.reduce(0) { $0 + $1.steps } / preferred.count
    }

    static func completedDayStepAverage(
        _ samples: [StepSample],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int? {
        let today = calendar.startOfDay(for: now)
        return recordedStepAverage(
            samples.filter { calendar.startOfDay(for: $0.date) < today },
            calendar: calendar
        )
    }

    static func stepBuckets(
        _ samples: [StepSample],
        range: Range,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [StepBucket] {
        let preferred = preferredStepSamples(samples, calendar: calendar)
        let daily = Dictionary(uniqueKeysWithValues: preferred.map {
            (calendar.startOfDay(for: $0.date), $0.steps)
        })
        let today = calendar.startOfDay(for: now)

        switch range {
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
            let labels = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
            return (0..<7).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
                return StepBucket(date: day, label: labels[offset], steps: daily[day] ?? 0)
            }

        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: now) else { return [] }
            let days = calendar.dateComponents([.day], from: interval.start, to: today).day ?? 0
            return (0...max(0, days)).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
                return StepBucket(
                    date: day,
                    label: calendar.component(.day, from: day).formatted(),
                    steps: daily[day] ?? 0
                )
            }

        case .year:
            guard let interval = calendar.dateInterval(of: .year, for: now) else { return [] }
            return groupedStepBuckets(
                preferred.filter { interval.contains($0.date) },
                component: [.year, .month],
                format: "MMM",
                calendar: calendar
            )

        case .all:
            guard let first = preferred.first?.date, let last = preferred.last?.date else { return [] }
            let span = calendar.dateComponents([.day], from: first, to: last).day ?? 0
            return groupedStepBuckets(
                preferred,
                component: span > 730 ? [.year] : [.year, .month],
                format: span > 730 ? "yyyy" : "MMM yy",
                calendar: calendar
            )
        }
    }

    static func stepProgressStatus(steps: Int, elapsedDays: Int) -> Status {
        let expected = 70_000.0 * Double(min(7, max(1, elapsedDays))) / 7.0
        let ratio = Double(max(0, steps)) / expected
        if ratio < 0.7 { return .red }
        if ratio < 1 { return .yellow }
        return .green
    }

    static func stepChartMaximum(_ steps: [Int]) -> Int {
        let highest = max(0, steps.max() ?? 0)
        guard highest > 10_000 else { return 10_000 }
        return Int((Double(highest) / 2_500).rounded(.up)) * 2_500
    }

    static func dailyStepStatus(steps: Int) -> Status {
        if steps <= 4_000 { return .red }
        if steps < 7_500 { return .yellow }
        return .green
    }

    static func cumulativeIndex(
        changes: [Double],
        baseline: Double = 100
    ) -> [Double] {
        var result = [baseline]
        var current = baseline
        for change in changes {
            current *= max(0, 1 + change / 100)
            result.append(current)
        }
        return result
    }

    static func trainingVolume(_ samples: [StrengthSetSample]) -> Double {
        samples.reduce(0) { total, sample in
            guard !sample.repsOnly, sample.weightKg > 0, sample.reps > 0 else { return total }
            return total + sample.weightKg * Double(sample.reps)
        }
    }

    static func exerciseWorkoutMetrics(
        _ samples: [ExerciseSetSample],
        repsOnly: Bool
    ) -> ExerciseWorkoutMetrics {
        let completed = samples.filter { $0.reps > 0 }
        let maximumWeight = repsOnly
            ? nil
            : completed.map(\.weightKg).filter { $0 > 0 }.max()

        return ExerciseWorkoutMetrics(
            maximumWeightKg: maximumWeight,
            totalReps: completed.reduce(0) { $0 + $1.reps }
        )
    }

    static func percentageChange(from first: Double, to last: Double) -> Double? {
        guard first > 0 else { return nil }
        return ((last / first) - 1) * 100
    }

    static func defaultWeightRange(
        _ samples: [WeightSample],
        calendar: Calendar = .current
    ) -> Range {
        let valid = samples.filter { $0.weightKg > 0 }.sorted { $0.date < $1.date }
        guard let first = valid.first?.date, let last = valid.last?.date else { return .week }
        let days = calendar.dateComponents([.day], from: first, to: last).day ?? 0
        if days < 7 { return .week }
        if days < 31 { return .month }
        if days < 366 { return .year }
        return .all
    }

    static func weightPoints(
        _ samples: [WeightSample],
        range: Range,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WeightPoint] {
        let valid = samples.filter { $0.weightKg > 0 }
        let grouped = Dictionary(grouping: valid) {
            calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start
                ?? calendar.startOfDay(for: $0.date)
        }

        let points = grouped.map { start, values in
            WeightPoint(
                weekStart: start,
                averageKg: values.reduce(0) { $0 + $1.weightKg } / Double(values.count)
            )
        }
        .sorted { $0.weekStart < $1.weekStart }

        guard range != .all,
              let latestAvailable = valid
                .filter({ $0.date <= now })
                .map(\.date)
                .max(),
              let cutoff = rollingCutoff(
                for: range,
                now: latestAvailable,
                calendar: calendar
              ) else {
            return points
        }

        let end = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: latestAvailable)
        ) ?? latestAvailable

        return points.filter { point in
            let interval = calendar.dateInterval(of: .weekOfYear, for: point.weekStart)
            return (interval?.end ?? point.weekStart) > cutoff && point.weekStart < end
        }
    }

    private static func rollingCutoff(
        for range: Range,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch range {
        case .week:
            return calendar.date(byAdding: .day, value: -6, to: today)
        case .month:
            return calendar.date(byAdding: .day, value: -30, to: today)
        case .year:
            return calendar.date(byAdding: .day, value: -365, to: today)
        case .all:
            return nil
        }
    }

    private static func groupedStepBuckets(
        _ samples: [StepSample],
        component: Set<Calendar.Component>,
        format: String,
        calendar: Calendar
    ) -> [StepBucket] {
        let grouped = Dictionary(grouping: samples) {
            calendar.date(from: calendar.dateComponents(component, from: $0.date))
                ?? calendar.startOfDay(for: $0.date)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = format

        return grouped.map { date, values in
            StepBucket(
                date: date,
                label: formatter.string(from: date),
                steps: values.reduce(0) { $0 + $1.steps }
            )
        }
        .sorted { $0.date < $1.date }
    }
}
