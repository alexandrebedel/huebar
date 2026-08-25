// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HueBar",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HueKit", targets: ["HueKit"]),
        .library(name: "WaveKit", targets: ["WaveKit"]),
        .library(name: "SyncKit", targets: ["SyncKit"]),
    ],
    targets: [
        .target(name: "HueKit"),
        .target(name: "WaveKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "SyncKit", dependencies: ["HueKit", "WaveKit"]),
        .testTarget(name: "WaveKitTests", dependencies: ["WaveKit"]),
        .testTarget(name: "SyncKitTests", dependencies: ["SyncKit", "HueKit", "WaveKit"]),
        .executableTarget(
            name: "HueBarApp",
            dependencies: ["HueKit", "WaveKit", "SyncKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "HueKitTests", dependencies: ["HueKit"]),
    ]
)
