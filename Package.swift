// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HueBar",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "HueKit"),
        .executableTarget(
            name: "HueBarApp",
            dependencies: ["HueKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "HueKitTests", dependencies: ["HueKit"]),
    ]
)
