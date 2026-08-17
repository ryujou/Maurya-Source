// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MauryaIOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MauryaProtocol", targets: ["MauryaProtocol"])
    ],
    targets: [
        .target(name: "MauryaProtocol"),
        .testTarget(
            name: "MauryaProtocolTests",
            dependencies: ["MauryaProtocol"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
