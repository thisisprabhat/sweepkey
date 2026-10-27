// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CleanerKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CleanerKit", targets: ["CleanerKit"]),
        .executable(name: "cleaner", targets: ["CleanerCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "CleanerKit",
            resources: [.copy("Resources/rules.json")]
        ),
        .executableTarget(
            name: "CleanerCLI",
            dependencies: [
                "CleanerKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "CleanerKitTests", dependencies: ["CleanerKit"]),
    ]
)
