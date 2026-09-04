import XCTest
@testable import LockedInAnalytics

final class RunSplitLayoutTests: XCTestCase {
    func testThreeTilesExactlyFitAvailableWidth() {
        let availableWidth = 390.0
        let horizontalPadding = 16.0
        let spacing = 10.0

        let tileWidth = RunSplitLayout.tileWidth(
            availableWidth: availableWidth,
            horizontalPadding: horizontalPadding,
            spacing: spacing,
            visibleTileCount: 3
        )

        let occupiedWidth = horizontalPadding * 2 + tileWidth * 3 + spacing * 2
        XCTAssertEqual(occupiedWidth, availableWidth, accuracy: 0.001)
    }

    func testLayoutAdaptsToNarrowerWidths() {
        let tileWidth = RunSplitLayout.tileWidth(
            availableWidth: 320,
            horizontalPadding: 16,
            spacing: 10,
            visibleTileCount: 3
        )

        XCTAssertGreaterThan(tileWidth, 0)
        XCTAssertEqual(tileWidth, (320 - 32 - 20) / 3, accuracy: 0.001)
    }
}
