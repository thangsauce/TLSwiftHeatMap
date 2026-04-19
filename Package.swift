// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TLSwiftHeatMap",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "TLSwiftHeatMap",
            targets: ["TLSwiftHeatMap"]
        )
    ],
    targets: [
        .target(
            name: "TLSwiftHeatMap",
            path: "Sources/TLSwiftHeatMap",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "TLSwiftHeatMapTests",
            dependencies: ["TLSwiftHeatMap"],
            path: "Tests/TLSwiftHeatMapTests"
        )
    ]
)
