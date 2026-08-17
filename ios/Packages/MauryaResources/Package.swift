// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MauryaResources",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MauryaResources", targets: ["MauryaResources"])
    ],
    dependencies: [
        .package(path: "../MauryaShare")
    ],
    targets: [
        .target(
            name: "CWebP",
            path: "Sources/CWebP",
            exclude: ["LICENSE.libwebp"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .define("WEBP_USE_THREAD", to: "1"),
            ]
        ),
        .target(
            name: "MauryaResources",
            dependencies: ["MauryaShare", "CWebP"],
            resources: [.process("Resources")],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "MauryaResourcesTests",
            dependencies: ["MauryaResources", "MauryaShare"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ],
    swiftLanguageModes: [.v6]
)
