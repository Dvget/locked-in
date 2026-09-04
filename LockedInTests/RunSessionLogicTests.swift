import XCTest
@testable import LockedInAnalytics

final class RunSessionLogicTests: XCTestCase {
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    func testClockExcludesPausedIntervalFromActiveDuration() {
        var clock = RunSessionClock()

        XCTAssertTrue(clock.start(at: date(0)))
        XCTAssertTrue(clock.pause(at: date(60)))
        XCTAssertTrue(clock.resume(at: date(90)))

        XCTAssertEqual(clock.activeDuration(at: date(120)), 90, accuracy: 0.001)
        XCTAssertEqual(clock.pausedDuration(at: date(120)), 30, accuracy: 0.001)
    }

    func testSecondStartCannotReplaceActiveSessionStartDate() {
        var clock = RunSessionClock()

        XCTAssertTrue(clock.start(at: date(10)))
        XCTAssertFalse(clock.start(at: date(20)))

        XCTAssertEqual(clock.startedAt, date(10))
        XCTAssertEqual(clock.phase, .recording)
    }

    func testInvalidPauseAndResumeTransitionsDoNotChangeState() {
        var clock = RunSessionClock()

        XCTAssertFalse(clock.pause(at: date(1)))
        XCTAssertFalse(clock.resume(at: date(2)))
        XCTAssertEqual(clock.phase, .preparing)

        XCTAssertTrue(clock.start(at: date(3)))
        XCTAssertFalse(clock.resume(at: date(4)))
        XCTAssertEqual(clock.phase, .recording)
    }

    func testFinishingFreezesActiveDuration() {
        var clock = RunSessionClock()
        XCTAssertTrue(clock.start(at: date(0)))
        XCTAssertTrue(clock.finish(at: date(75)))

        XCTAssertEqual(clock.phase, .finishing)
        XCTAssertEqual(clock.activeDuration(at: date(200)), 75, accuracy: 0.001)
    }

    func testFinishingCheckpointIsRestorableForSaveRetry() {
        var clock = RunSessionClock()
        XCTAssertTrue(clock.start(at: date(0)))
        XCTAssertTrue(clock.finish(at: date(75)))

        let checkpoint = RunSessionCheckpoint(
            runID: UUID(),
            clock: clock,
            metrics: .empty,
            speechEnabled: true,
            savedAt: date(80)
        )

        XCTAssertTrue(checkpoint.isRestorable(at: date(90)))
    }

    func testRunningCountdownOffersOnlyCleanPresetChoices() {
        XCTAssertEqual(RunCountdownOption.allCases.map(\.seconds), [0, 3, 5, 10])
        XCTAssertEqual(RunCountdownOption.defaultOption, .threeSeconds)
        XCTAssertEqual(RunCountdownOption.disabled.displayName, "Ohne")
        XCTAssertEqual(RunCountdownOption.threeSeconds.displayName, "3 Sekunden")
    }

    func testCountdownCanBeCancelledBeforeRecordingStarts() {
        var clock = RunSessionClock()

        XCTAssertTrue(clock.beginCountdown())
        XCTAssertTrue(clock.cancelCountdown())
        XCTAssertEqual(clock.phase, .preparing)
        XCTAssertNil(clock.startedAt)
    }
}
