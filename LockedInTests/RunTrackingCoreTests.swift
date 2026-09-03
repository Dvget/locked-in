import XCTest
@testable import LockedInAnalytics

final class RunTrackingCoreTests: XCTestCase {
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func sample(
        latitude: Double = 48,
        longitude: Double = 8,
        altitude: Double = 100,
        horizontalAccuracy: Double = 5,
        verticalAccuracy: Double = 5,
        speed: Double = 1.5,
        timestamp: TimeInterval
    ) -> RunLocationSample {
        RunLocationSample(
            timestamp: date(timestamp),
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            reportedSpeed: speed
        )
    }

    func testFilterRejectsStaleFutureAndInaccurateSamples() {
        let filter = RunLocationFilter(configuration: .version1)

        XCTAssertEqual(
            filter.evaluate(sample(timestamp: 80), receivedAt: date(100), previousAccepted: nil).rejectionReason,
            .stale
        )
        XCTAssertEqual(
            filter.evaluate(sample(timestamp: 102), receivedAt: date(100), previousAccepted: nil).rejectionReason,
            .future
        )
        XCTAssertEqual(
            filter.evaluate(sample(horizontalAccuracy: 26, timestamp: 100), receivedAt: date(100), previousAccepted: nil).rejectionReason,
            .horizontalAccuracy
        )
    }

    func testFilterRejectsDuplicateAndImplausibleJump() {
        let filter = RunLocationFilter(configuration: .version1)
        let previous = sample(timestamp: 100)

        XCTAssertEqual(
            filter.evaluate(previous, receivedAt: date(100), previousAccepted: previous).rejectionReason,
            .duplicate
        )
        XCTAssertEqual(
            filter.evaluate(
                sample(latitude: 48.01, timestamp: 101),
                receivedAt: date(101),
                previousAccepted: previous
            ).rejectionReason,
            .implausibleSpeed
        )
    }

    func testAcceptedSamplesAccumulateDistanceAndAveragePace() {
        var calculator = RunMetricsCalculator(configuration: .version1)
        _ = calculator.ingest(sample(timestamp: 0), receivedAt: date(0), isPaused: false)
        let result = calculator.ingest(
            sample(latitude: 48.000899, timestamp: 60),
            receivedAt: date(60),
            isPaused: false
        )

        XCTAssertEqual(result.distanceMeters, 100, accuracy: 1.5)
        XCTAssertEqual(result.activeDurationSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(result.averagePaceSecondsPerKm ?? 0, 600, accuracy: 12)
    }

    func testPausedSamplesAreRetainedWithoutAddingMetricsOrBridgingResume() {
        var calculator = RunMetricsCalculator(configuration: .version1)
        _ = calculator.ingest(sample(timestamp: 0), receivedAt: date(0), isPaused: false)
        _ = calculator.ingest(
            sample(latitude: 48.000899, timestamp: 60),
            receivedAt: date(60),
            isPaused: true
        )
        _ = calculator.ingest(
            sample(latitude: 48.001798, timestamp: 90),
            receivedAt: date(90),
            isPaused: false
        )
        let result = calculator.ingest(
            sample(latitude: 48.002697, timestamp: 150),
            receivedAt: date(150),
            isPaused: false
        )

        XCTAssertEqual(result.route.count, 4)
        XCTAssertTrue(result.route[1].paused)
        XCTAssertEqual(result.distanceMeters, 100, accuracy: 1.5)
        XCTAssertEqual(result.activeDurationSeconds, 60, accuracy: 0.001)
    }

    func testExplicitPauseWithoutLocationSamplesDoesNotBridgeResume() {
        var calculator = RunMetricsCalculator(configuration: .version1)
        _ = calculator.ingest(sample(timestamp: 0), receivedAt: date(0), isPaused: false)

        calculator.beginPause()
        calculator.endPause()

        _ = calculator.ingest(
            sample(latitude: 48.001798, timestamp: 90),
            receivedAt: date(90),
            isPaused: false
        )
        let result = calculator.ingest(
            sample(latitude: 48.002697, timestamp: 150),
            receivedAt: date(150),
            isPaused: false
        )

        XCTAssertEqual(result.distanceMeters, 100, accuracy: 1.5)
        XCTAssertEqual(result.activeDurationSeconds, 60, accuracy: 0.001)
    }

    func testCalculatorStateRestoresPauseBoundaryWithoutPausedSamples() {
        var calculator = RunMetricsCalculator(configuration: .version1)
        _ = calculator.ingest(sample(timestamp: 0), receivedAt: date(0), isPaused: false)
        calculator.beginPause()
        calculator.endPause()

        let restoredState = try! RunArchiveCodec.decode(
            RunMetricsCalculatorState.self,
            from: RunArchiveCodec.encode(calculator.checkpointState)
        )
        var restored = RunMetricsCalculator(configuration: .version1, state: restoredState)
        _ = restored.ingest(
            sample(latitude: 48.001798, timestamp: 90),
            receivedAt: date(90),
            isPaused: false
        )
        let result = restored.ingest(
            sample(latitude: 48.002697, timestamp: 150),
            receivedAt: date(150),
            isPaused: false
        )

        XCTAssertEqual(result.distanceMeters, 100, accuracy: 1.5)
        XCTAssertEqual(result.activeDurationSeconds, 60, accuracy: 0.001)
    }

    func testRollingPaceUsesRecentWindowInsteadOfOnlyLastPair() {
        var calculator = RunMetricsCalculator(configuration: .version1)
        _ = calculator.ingest(sample(timestamp: 0), receivedAt: date(0), isPaused: false)
        _ = calculator.ingest(
            sample(latitude: 48.000450, timestamp: 30),
            receivedAt: date(30),
            isPaused: false
        )
        let result = calculator.ingest(
            sample(latitude: 48.000899, timestamp: 60),
            receivedAt: date(60),
            isPaused: false
        )

        XCTAssertEqual(result.currentPaceSecondsPerKm ?? 0, 600, accuracy: 15)
    }

    func testCrossingKilometreCreatesOneCompletedSplit() {
        var calculator = RunMetricsCalculator(configuration: .version1)
        _ = calculator.ingest(sample(timestamp: 0), receivedAt: date(0), isPaused: false)
        let result = calculator.ingest(
            sample(latitude: 48.00945, timestamp: 600),
            receivedAt: date(600),
            isPaused: false
        )

        XCTAssertEqual(result.splits.count, 1)
        XCTAssertEqual(result.splits.first?.kilometre, 1)
        XCTAssertEqual(result.splits.first?.cumulativeDistanceMeters ?? 0, 1_000, accuracy: 0.001)
    }

    func testElevationDeadbandIgnoresNoiseAndCountsMeaningfulChange() {
        var calculator = RunMetricsCalculator(configuration: .version1)
        _ = calculator.ingest(sample(timestamp: 0), receivedAt: date(0), isPaused: false)
        _ = calculator.ingest(
            sample(latitude: 48.000090, altitude: 101, timestamp: 10),
            receivedAt: date(10),
            isPaused: false
        )
        let result = calculator.ingest(
            sample(latitude: 48.000180, altitude: 104.5, timestamp: 20),
            receivedAt: date(20),
            isPaused: false
        )

        XCTAssertEqual(result.elevationGainMeters, 4.5, accuracy: 0.001)
        XCTAssertEqual(result.elevationLossMeters, 0, accuracy: 0.001)
    }

    func testRejectedSampleIsRetainedWithoutChangingDistance() {
        var calculator = RunMetricsCalculator(configuration: .version1)
        _ = calculator.ingest(sample(timestamp: 0), receivedAt: date(0), isPaused: false)
        let result = calculator.ingest(
            sample(latitude: 48.01, timestamp: 1),
            receivedAt: date(1),
            isPaused: false
        )

        XCTAssertEqual(result.route.count, 2)
        XCTAssertEqual(result.route.last?.rejectionReason, .implausibleSpeed)
        XCTAssertEqual(result.distanceMeters, 0, accuracy: 0.001)
    }

    func testRunArchiveCodecRoundTripsRouteDecisions() throws {
        let original = [
            RunLocationDecision(
                sample: sample(timestamp: 10),
                accepted: true,
                cumulativeDistanceMeters: 42,
                paused: false
            )
        ]

        let encoded = try RunArchiveCodec.encode(original)
        let decoded = try RunArchiveCodec.decode([RunLocationDecision].self, from: encoded)

        XCTAssertEqual(decoded, original)
    }

    func testRunArchiveCodecPreservesSubsecondTimestamps() throws {
        let original = sample(timestamp: 10.123_456)

        let encoded = try RunArchiveCodec.encode(original)
        let decoded = try RunArchiveCodec.decode(RunLocationSample.self, from: encoded)

        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, 10.123_456, accuracy: 0.000_001)
    }

    func testNativeRunArchiveDecodesLegacyEmptyObject() throws {
        let archive = try JSONDecoder().decode(NativeRunArchive.self, from: Data("{}".utf8))

        XCTAssertNil(archive.algorithmVersion)
        XCTAssertNil(archive.route)
        XCTAssertNil(archive.splits)
        XCTAssertNil(archive.configuration)
        XCTAssertNil(archive.metadata)
    }

    func testCalculatorReplayRestoresSavedRouteMetrics() {
        var original = RunMetricsCalculator(configuration: .version1)
        _ = original.ingest(sample(timestamp: 0), receivedAt: date(0), isPaused: false)
        let saved = original.ingest(
            sample(latitude: 48.000899, timestamp: 60),
            receivedAt: date(60),
            isPaused: false
        )

        let restored = RunMetricsCalculator(
            configuration: .version1,
            replaying: saved.route
        )

        XCTAssertEqual(restored.currentSnapshot.distanceMeters, saved.distanceMeters, accuracy: 0.001)
        XCTAssertEqual(restored.currentSnapshot.activeDurationSeconds, saved.activeDurationSeconds, accuracy: 0.001)
        XCTAssertEqual(restored.currentSnapshot.route, saved.route)
    }

    func testCalculatorReplayPreservesRejectedDecisionWithoutReclassifyingIt() {
        let accepted = RunLocationDecision(
            sample: sample(timestamp: 0),
            accepted: true,
            cumulativeDistanceMeters: 0,
            paused: false
        )
        let rejected = RunLocationDecision(
            sample: sample(latitude: 48.0001, timestamp: 1),
            accepted: false,
            rejectionReason: .stale,
            cumulativeDistanceMeters: 0,
            paused: false
        )

        let restored = RunMetricsCalculator(
            configuration: .version1,
            replaying: [accepted, rejected]
        )

        XCTAssertEqual(restored.currentSnapshot.route, [accepted, rejected])
        XCTAssertEqual(restored.currentSnapshot.distanceMeters, 0, accuracy: 0.001)
    }
}
