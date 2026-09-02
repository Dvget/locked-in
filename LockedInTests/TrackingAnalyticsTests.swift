import XCTest
@testable import LockedInAnalytics

final class TrackingAnalyticsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)!
    }

    func testRunSummaryUsesRolling28DaysAndDistanceWeightedPace() {
        let now = date("2026-09-01")
        let samples = [
            TrackingAnalytics.RunSample(date: date("2026-08-05"), distanceKm: 5, durationSeconds: 1_500),
            TrackingAnalytics.RunSample(date: date("2026-08-06"), distanceKm: 10, durationSeconds: 3_600),
            TrackingAnalytics.RunSample(date: date("2026-08-04"), distanceKm: 20, durationSeconds: 7_200)
        ]

        let summary = TrackingAnalytics.runSummary(
            samples,
            rollingDays: 28,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.totalDistanceKm, 15, accuracy: 0.001)
        XCTAssertEqual(summary.averageDistanceKm, 7.5, accuracy: 0.001)
        XCTAssertEqual(summary.weightedPaceSecondsPerKm, 340, accuracy: 0.001)
    }

    func testWeeklyRunComparisonCombinesDistanceAndPace() {
        let now = date("2026-09-01")
        let samples = [
            TrackingAnalytics.RunSample(date: date("2026-08-25"), distanceKm: 5, durationSeconds: 1_800),
            TrackingAnalytics.RunSample(date: date("2026-09-01"), distanceKm: 5.5, durationSeconds: 1_800)
        ]

        let change = TrackingAnalytics.weeklyRunChange(
            samples,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(change!, 10, accuracy: 0.2)
    }

    func testRunSeriesChangesUseRawDistanceAndFasterPaceAsPositive() {
        let samples = [
            TrackingAnalytics.RunSample(date: date("2026-08-01"), distanceKm: 5, durationSeconds: 1_800),
            TrackingAnalytics.RunSample(date: date("2026-08-08"), distanceKm: 7.5, durationSeconds: 3_150)
        ]

        XCTAssertEqual(
            TrackingAnalytics.runSeriesChange(samples, series: .distance)!,
            50,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TrackingAnalytics.runSeriesChange(samples, series: .pace)!,
            -14.285,
            accuracy: 0.01
        )
        XCTAssertEqual(
            TrackingAnalytics.runSeriesChange(samples, series: .overall)!,
            13.389,
            accuracy: 0.01
        )

        let faster = [
            TrackingAnalytics.RunSample(date: date("2026-08-01"), distanceKm: 5, durationSeconds: 1_800),
            TrackingAnalytics.RunSample(date: date("2026-08-08"), distanceKm: 5, durationSeconds: 1_500)
        ]
        XCTAssertEqual(
            TrackingAnalytics.runSeriesChange(faster, series: .pace)!,
            20,
            accuracy: 0.001
        )
    }

    func testRunChangeComparesCombinedPerformanceToPreviousRun() {
        let previous = TrackingAnalytics.RunSample(
            date: date("2026-08-01"),
            distanceKm: 5,
            durationSeconds: 1_800
        )
        let current = TrackingAnalytics.RunSample(
            date: date("2026-08-08"),
            distanceKm: 6,
            durationSeconds: 1_800
        )

        XCTAssertEqual(
            TrackingAnalytics.runChange(current: current, previous: previous)!,
            20,
            accuracy: 0.001
        )
    }

    func testPreferredStepSamplesUseOneCoreMotionValuePerDay() {
        let day = date("2026-09-01")
        let samples = [
            TrackingAnalytics.StepSample(date: day, steps: 8_000, source: "manual"),
            TrackingAnalytics.StepSample(date: day, steps: 9_000, source: "coremotion"),
            TrackingAnalytics.StepSample(date: day, steps: 10_000, source: "coremotion")
        ]

        let preferred = TrackingAnalytics.preferredStepSamples(samples, calendar: calendar)

        XCTAssertEqual(preferred.count, 1)
        XCTAssertEqual(preferred.first?.steps, 10_000)
        XCTAssertEqual(preferred.first?.source, "coremotion")
    }

    func testRecordedStepAverageUsesOnlyDaysWithSamples() {
        let samples = [
            TrackingAnalytics.StepSample(date: date("2026-08-31"), steps: 10_000, source: "coremotion"),
            TrackingAnalytics.StepSample(date: date("2026-09-01"), steps: 4_000, source: "coremotion")
        ]

        XCTAssertEqual(
            TrackingAnalytics.recordedStepAverage(samples, calendar: calendar),
            7_000
        )
    }

    func testRecordedStepAverageStillPrefersOneCoreMotionValuePerDay() {
        let samples = [
            TrackingAnalytics.StepSample(date: date("2026-08-31"), steps: 8_000, source: "manual"),
            TrackingAnalytics.StepSample(date: date("2026-08-31"), steps: 10_000, source: "coremotion"),
            TrackingAnalytics.StepSample(date: date("2026-09-01"), steps: 4_000, source: "coremotion")
        ]

        XCTAssertEqual(
            TrackingAnalytics.recordedStepAverage(samples, calendar: calendar),
            7_000
        )
    }

    func testStepProgressStatusUsesElapsedWeeklyTarget() {
        XCTAssertEqual(
            TrackingAnalytics.stepProgressStatus(steps: 10_000, elapsedDays: 2),
            .red
        )
        XCTAssertEqual(
            TrackingAnalytics.stepProgressStatus(steps: 18_000, elapsedDays: 2),
            .yellow
        )
        XCTAssertEqual(
            TrackingAnalytics.stepProgressStatus(steps: 20_000, elapsedDays: 2),
            .green
        )
    }

    func testStepChartMaximumStartsAtTenThousandAndRoundsUp() {
        XCTAssertEqual(TrackingAnalytics.stepChartMaximum([]), 10_000)
        XCTAssertEqual(TrackingAnalytics.stepChartMaximum([10_000]), 10_000)
        XCTAssertEqual(TrackingAnalytics.stepChartMaximum([10_001]), 12_500)
        XCTAssertEqual(TrackingAnalytics.stepChartMaximum([13_100]), 15_000)
        XCTAssertEqual(TrackingAnalytics.stepChartMaximum([18_600]), 20_000)
    }

    func testDailyStepStatusUsesAgreedThresholds() {
        XCTAssertEqual(TrackingAnalytics.dailyStepStatus(steps: 4_000), .red)
        XCTAssertEqual(TrackingAnalytics.dailyStepStatus(steps: 4_001), .yellow)
        XCTAssertEqual(TrackingAnalytics.dailyStepStatus(steps: 7_499), .yellow)
        XCTAssertEqual(TrackingAnalytics.dailyStepStatus(steps: 7_500), .green)
    }

    func testCumulativeIndexMovesUpForProgressAndDownForRegression() {
        let points = TrackingAnalytics.cumulativeIndex(changes: [10, -5])

        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0], 100, accuracy: 0.001)
        XCTAssertEqual(points[1], 110, accuracy: 0.001)
        XCTAssertEqual(points[2], 104.5, accuracy: 0.001)
    }

    func testTrainingVolumeSumsOnlyWeightedCompletedRepetitions() {
        let volume = TrackingAnalytics.trainingVolume([
            .init(weightKg: 60, reps: 8, repsOnly: false),
            .init(weightKg: 20, reps: 10, repsOnly: false),
            .init(weightKg: 0, reps: 50, repsOnly: true),
            .init(weightKg: 100, reps: 0, repsOnly: false)
        ])

        XCTAssertEqual(volume, 680, accuracy: 0.001)
    }

    func testExerciseWorkoutMetricsUseHighestWeightAndTotalRepetitions() {
        let metrics = TrackingAnalytics.exerciseWorkoutMetrics([
            .init(weightKg: 60, reps: 8),
            .init(weightKg: 62, reps: 7),
            .init(weightKg: 60, reps: 6),
            .init(weightKg: 100, reps: 0)
        ], repsOnly: false)

        XCTAssertEqual(metrics.maximumWeightKg, 62)
        XCTAssertEqual(metrics.totalReps, 21)
    }

    func testExerciseWorkoutMetricsHideWeightForRepsOnlyExercise() {
        let metrics = TrackingAnalytics.exerciseWorkoutMetrics([
            .init(weightKg: 20, reps: 5),
            .init(weightKg: 20, reps: 4),
            .init(weightKg: 20, reps: 3)
        ], repsOnly: true)

        XCTAssertNil(metrics.maximumWeightKg)
        XCTAssertEqual(metrics.totalReps, 12)
    }

    func testPercentageChangeUsesRawMetricDirection() {
        XCTAssertEqual(
            TrackingAnalytics.percentageChange(from: 50, to: 60)!,
            20,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TrackingAnalytics.percentageChange(from: 10, to: 8)!,
            -20,
            accuracy: 0.001
        )
        XCTAssertNil(TrackingAnalytics.percentageChange(from: 0, to: 10))
    }

    func testDefaultWeightRangeFollowsHistorySpan() {
        XCTAssertEqual(
            TrackingAnalytics.defaultWeightRange(
                [
                    .init(date: date("2026-08-28"), weightKg: 94),
                    .init(date: date("2026-09-01"), weightKg: 93.5)
                ],
                calendar: calendar
            ),
            .week
        )
        XCTAssertEqual(
            TrackingAnalytics.defaultWeightRange(
                [
                    .init(date: date("2026-06-01"), weightKg: 96),
                    .init(date: date("2026-09-01"), weightKg: 93.5)
                ],
                calendar: calendar
            ),
            .year
        )
        XCTAssertEqual(
            TrackingAnalytics.defaultWeightRange(
                [
                    .init(date: date("2025-01-01"), weightKg: 100),
                    .init(date: date("2026-09-01"), weightKg: 93.5)
                ],
                calendar: calendar
            ),
            .all
        )
    }

    func testWeightPointsAverageVisibleMeasurementsByWeek() {
        let samples = [
            TrackingAnalytics.WeightSample(date: date("2026-08-31"), weightKg: 94),
            TrackingAnalytics.WeightSample(date: date("2026-09-01"), weightKg: 93),
            TrackingAnalytics.WeightSample(date: date("2026-08-24"), weightKg: 95)
        ]

        let points = TrackingAnalytics.weightPoints(
            samples,
            range: .all,
            now: date("2026-09-01"),
            calendar: calendar
        )

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].averageKg, 95, accuracy: 0.001)
        XCTAssertEqual(points[1].averageKg, 93.5, accuracy: 0.001)
    }

    func testWeightPointsUseCompleteWeekBeforeRangeClipping() {
        let samples = [
            TrackingAnalytics.WeightSample(date: date("2026-08-28"), weightKg: 100),
            TrackingAnalytics.WeightSample(date: date("2026-08-29"), weightKg: 80),
            TrackingAnalytics.WeightSample(date: date("2026-09-04"), weightKg: 95)
        ]

        let points = TrackingAnalytics.weightPoints(
            samples,
            range: .week,
            now: date("2026-09-04"),
            calendar: calendar
        )

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].averageKg, 90, accuracy: 0.001)
        XCTAssertEqual(points[1].averageKg, 95, accuracy: 0.001)
    }

    func testWeightRangeAnchorsToLatestAvailableMeasurement() {
        let samples = [
            TrackingAnalytics.WeightSample(date: date("2025-01-01"), weightKg: 96),
            TrackingAnalytics.WeightSample(date: date("2025-01-05"), weightKg: 95)
        ]

        XCTAssertEqual(
            TrackingAnalytics.defaultWeightRange(samples, calendar: calendar),
            .week
        )

        let points = TrackingAnalytics.weightPoints(
            samples,
            range: .week,
            now: date("2026-09-01"),
            calendar: calendar
        )

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].averageKg, 95.5, accuracy: 0.001)
    }
}
