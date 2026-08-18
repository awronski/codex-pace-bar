// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexPaceBar",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "CodexPaceBar", targets: ["CodexPaceBar"]),
        .executable(name: "ActivityInsightsCollector", targets: ["ActivityInsightsCollector"]),
        .executable(name: "ActivityInsightsAudit", targets: ["ActivityInsightsAudit"])
    ],
    targets: [
        .target(
            name: "CodexActivityInsightsContract",
            path: "Sources/CodexActivityInsightsContract"
        ),
        .target(
            name: "CodexActivityInsightsCore",
            dependencies: ["CodexActivityInsightsContract"],
            path: "Sources/CodexActivityInsightsCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "CodexActivityInsightsMac",
            dependencies: ["CodexActivityInsightsCore"],
            path: "Sources/CodexActivityInsightsMac"
        ),
        .target(
            name: "CodexPaceBarCore",
            path: "Sources/CodexPaceBarCore"
        ),
        .target(
            name: "CodexPaceBarAppSupport",
            dependencies: ["CodexPaceBarCore"],
            path: "Sources/CodexPaceBarAppSupport"
        ),
        .target(
            name: "CodexActivityInsightsChartAdapter",
            dependencies: ["CodexActivityInsightsContract"],
            path: "Sources/CodexActivityInsightsChartAdapter"
        ),
        .target(
            name: "CodexActivityInsightsControlAdapter",
            path: "Sources/CodexActivityInsightsControlAdapter"
        ),
        .executableTarget(
            name: "CodexPaceBar",
            dependencies: [
                "CodexPaceBarCore",
                "CodexPaceBarAppSupport",
                "CodexActivityInsightsContract",
                "CodexActivityInsightsChartAdapter",
                "CodexActivityInsightsControlAdapter"
            ],
            path: "Sources/CodexPaceBar"
        ),
        .executableTarget(
            name: "ActivityInsightsCollector",
            dependencies: ["CodexActivityInsightsCore", "CodexActivityInsightsMac"],
            path: "Sources/ActivityInsightsCollector"
        ),
        .executableTarget(
            name: "ActivityInsightsAudit",
            dependencies: ["CodexActivityInsightsCore", "CodexActivityInsightsMac"],
            path: "Sources/ActivityInsightsAudit"
        ),
        .testTarget(
            name: "CodexPaceBarTests",
            dependencies: ["CodexPaceBarCore", "CodexPaceBarAppSupport"],
            path: "Tests/CodexPaceBarTests"
        ),
        .testTarget(
            name: "CodexActivityInsightsTests",
            dependencies: [
                "CodexActivityInsightsContract",
                "CodexActivityInsightsCore",
                "CodexActivityInsightsMac"
            ],
            path: "Tests/CodexActivityInsightsTests"
        ),
        .testTarget(
            name: "CodexActivityInsightsChartAdapterTests",
            dependencies: [
                "CodexActivityInsightsContract",
                "CodexActivityInsightsChartAdapter"
            ],
            path: "Tests/CodexActivityInsightsChartAdapterTests"
        ),
        .testTarget(
            name: "CodexActivityInsightsControlAdapterTests",
            dependencies: ["CodexActivityInsightsControlAdapter"],
            path: "Tests/CodexActivityInsightsControlAdapterTests"
        )
    ]
)
