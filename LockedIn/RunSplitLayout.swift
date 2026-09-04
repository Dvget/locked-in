import Foundation

struct RunSplitLayout {
    static func tileWidth(
        availableWidth: Double,
        horizontalPadding: Double,
        spacing: Double,
        visibleTileCount: Int
    ) -> Double {
        guard visibleTileCount > 0 else { return 0 }
        let totalSpacing = spacing * Double(max(0, visibleTileCount - 1))
        let usableWidth = max(0, availableWidth - horizontalPadding * 2 - totalSpacing)
        return usableWidth / Double(visibleTileCount)
    }
}
