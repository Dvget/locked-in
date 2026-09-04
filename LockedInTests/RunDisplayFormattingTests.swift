import XCTest
@testable import LockedInAnalytics

final class RunDisplayFormattingTests: XCTestCase {
    func testElevationGainPresentationUsesOnlyPositiveGain() {
        XCTAssertEqual(RunDisplayFormatting.elevationGainTitle, "HÖHENZUNAHME")
        XCTAssertEqual(RunDisplayFormatting.elevationGainValue(meters: 84.4), "84")
    }
}
