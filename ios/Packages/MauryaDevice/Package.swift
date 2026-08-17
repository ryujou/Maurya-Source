// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MauryaDevice",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MauryaDevice", targets: ["MauryaDevice"])
    ],
    dependencies: [
        .package(path: "../.."),
        .package(path: "../MauryaBluetooth"),
    ],
    targets: [
        .target(
            name: "MauryaDevice",
            dependencies: [
                .product(name: "MauryaProtocol", package: "ios"),
                .product(name: "MauryaBluetooth", package: "MauryaBluetooth"),
            ]
        ),
        .testTarget(
            name: "MauryaDeviceTests",
            dependencies: ["MauryaDevice", .product(name: "MauryaProtocol", package: "ios")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
