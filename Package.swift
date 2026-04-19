// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftHeatMap",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "SwiftHeatMap",
            targets: ["SwiftHeatMap"]
        )
    ],
    targets: [
        .target(
            name: "SwiftHeatMap",
            path: "Sources/SwiftHeatMap",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SwiftHeatMapTests",
            dependencies: ["SwiftHeatMap"],
            path: "Tests/SwiftHeatMapTests"
        )
    ]
)
