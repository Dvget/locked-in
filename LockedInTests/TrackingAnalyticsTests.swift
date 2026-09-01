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
            TrackingAnalytics.RunSample(date: date("2026-08-04"), distanceKm: 10, durationSeconds: 3_600),
            TrackingAnalytics.RunSample(date: date("2026-08-03"), distanceKm: 20, durationSeconds: 7_200)
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
}
