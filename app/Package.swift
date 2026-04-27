// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LingoPulseApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LingoPulseApp", targets: ["LingoPulseApp"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "LingoPulseApp",
            dependencies: [],
            path: "Sources/LingoPulseApp"
        ),
        .testTarget(
            name: "LingoPulseAppTests",
            dependencies: ["LingoPulseApp"],
            path: "Tests/LingoPulseAppTests"
        ),
    ]
)
