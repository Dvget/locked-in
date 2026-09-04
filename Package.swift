// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LockedInAnalytics",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LockedInAnalytics", targets: ["LockedInAnalytics"])
    ],
    targets: [
        .target(
            name: "LockedInAnalytics",
            path: "LockedIn",
            sources: [
                "TrackingAnalytics.swift",
                "PolarRunPayload.swift",
                "RunTrackingCore.swift",
                "RunDiagnosticMetadata.swift",
                "RunSessionState.swift",
                "RunSplitLayout.swift"
            ]
        ),
        .testTarget(
            name: "LockedInAnalyticsTests",
            dependencies: ["LockedInAnalytics"],
            path: "LockedInTests"
        )
    ]
)
