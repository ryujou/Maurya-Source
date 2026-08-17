// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MauryaEffects",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MauryaEffects", targets: ["MauryaEffects"])
    ],
    targets: [
        .target(
            name: "MauryaEffects",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ]
        ),
        .testTarget(
            name: "MauryaEffectsTests",
            dependencies: ["MauryaEffects"],
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"])
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
