// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MauryaEditor",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MauryaEditor", targets: ["MauryaEditor"])
    ],
    targets: [
        .target(
            name: "MauryaEditor",
            resources: [.copy("Resources/EditorBundle")],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "MauryaEditorTests",
            dependencies: ["MauryaEditor"],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ],
    swiftLanguageModes: [.v6]
)
