// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LingoPulseApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LingoPulseApp", targets: ["LingoPulseApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "LingoPulseApp",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/LingoPulseApp"
        ),
        .testTarget(
            name: "LingoPulseAppTests",
            dependencies: ["LingoPulseApp"],
            path: "Tests/LingoPulseAppTests"
        ),
    ]
)
