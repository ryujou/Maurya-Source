// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MauryaOTA",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MauryaOTA", targets: ["MauryaOTA"])
    ],
    dependencies: [
        .package(path: "../.."),
        .package(path: "../MauryaDevice"),
        .package(path: "../MauryaBluetooth"),
    ],
    targets: [
        .target(
            name: "MauryaOTA",
            dependencies: [
                .product(name: "MauryaProtocol", package: "ios"),
                .product(name: "MauryaDevice", package: "MauryaDevice"),
                .product(name: "MauryaBluetooth", package: "MauryaBluetooth"),
            ],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "MauryaOTATests",
            dependencies: ["MauryaOTA"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ],
    swiftLanguageModes: [.v6]
)
