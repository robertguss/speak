// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DictationCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "DictationCore", targets: ["DictationCore"]),
        .library(name: "DictationUI", targets: ["DictationUI"]),
    ],
    targets: [
        .target(name: "DictationCore"),
        .target(name: "DictationUI", dependencies: ["DictationCore"]),
        .testTarget(
            name: "DictationCoreTests",
            dependencies: ["DictationCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
