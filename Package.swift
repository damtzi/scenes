// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Scenes",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Scenes", targets: ["Scenes"]),
    ],
    targets: [
        .executableTarget(name: "Scenes"),
        .testTarget(name: "ScenesTests", dependencies: ["Scenes"]),
    ]
)
