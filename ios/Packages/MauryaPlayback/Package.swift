// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MauryaPlayback",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MauryaPlayback", targets: ["MauryaPlayback"])],
    dependencies: [
        .package(path: "../MauryaEffects"),
        .package(path: "../MauryaAnalysis"),
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "MauryaPlayback",
            dependencies: [
                "MauryaEffects",
                "MauryaAnalysis",
                .product(name: "MauryaProtocol", package: "ios"),
            ],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "MauryaPlaybackTests",
            dependencies: [
                "MauryaPlayback",
                "MauryaEffects",
                .product(name: "MauryaProtocol", package: "ios"),
            ],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ],
    swiftLanguageModes: [.v6]
)
