// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Focus",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "FocusCore"),
        .executableTarget(name: "Focus", dependencies: ["FocusCore"]),
        .testTarget(name: "FocusCoreTests", dependencies: ["FocusCore"]),
    ],
    swiftLanguageModes: [.v5]
)
