// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IconMixer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "IconMixCore"),
        .executableTarget(name: "IconMixer", dependencies: ["IconMixCore"]),
        .testTarget(name: "IconMixCoreTests", dependencies: ["IconMixCore"]),
        .testTarget(name: "IconMixerTests", dependencies: ["IconMixer"]),
    ]
)
