// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SweepkeyKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SweepkeyKit", targets: ["SweepkeyKit"]),
        .executable(name: "sweepkey", targets: ["SweepkeyCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SweepkeyKit",
            resources: [.copy("Resources/rules.json")]
        ),
        .executableTarget(
            name: "SweepkeyCLI",
            dependencies: [
                "SweepkeyKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "SweepkeyKitTests", dependencies: ["SweepkeyKit"]),
    ]
)
