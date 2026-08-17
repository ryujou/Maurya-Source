// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MauryaBluetooth",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MauryaBluetooth", targets: ["MauryaBluetooth"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "MauryaBluetooth",
            dependencies: [
                .product(name: "MauryaProtocol", package: "ios")
            ]
        ),
        .testTarget(
            name: "MauryaBluetoothTests",
            dependencies: ["MauryaBluetooth"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
