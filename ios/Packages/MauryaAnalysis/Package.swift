// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MauryaAnalysis",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MauryaAnalysis", targets: ["MauryaAnalysis"])
    ],
    dependencies: [
        .package(path: "../MauryaEffects")
    ],
    targets: [
        .target(
            name: "MauryaAnalysis",
            dependencies: ["MauryaEffects"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "MauryaAnalysisTests",
            dependencies: ["MauryaAnalysis", "MauryaEffects"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ],
    swiftLanguageModes: [.v6]
)
