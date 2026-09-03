import XCTest
@testable import LockedInAnalytics

final class RunBackgroundLocationSupportTests: XCTestCase {
    func testBackgroundLocationIsEnabledOnlyWhenLocationModeExists() {
        XCTAssertTrue(
            RunBackgroundLocationSupport.isEnabled(
                infoDictionary: ["UIBackgroundModes": ["location"]]
            )
        )
    }

    func testBackgroundLocationIsDisabledWhenModeIsMissing() {
        XCTAssertFalse(
            RunBackgroundLocationSupport.isEnabled(infoDictionary: [:])
        )
    }

    func testBackgroundLocationIsDisabledForMalformedStringValue() {
        XCTAssertFalse(
            RunBackgroundLocationSupport.isEnabled(
                infoDictionary: ["UIBackgroundModes": "location"]
            )
        )
    }
}
