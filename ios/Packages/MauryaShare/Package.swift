// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MauryaShare",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MauryaShare", targets: ["MauryaShare"])
    ],
    targets: [
        .target(
            name: "CZlib",
            path: "Sources/CZlib",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("z")]
        ),
        .target(
            name: "MauryaShare",
            dependencies: ["CZlib"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "MauryaShareTests",
            dependencies: ["MauryaShare"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ],
    swiftLanguageModes: [.v6]
)
