// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LingoPulseApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LingoPulseApp", targets: ["LingoPulseApp"]),
        .executable(name: "LingoPulseIME", targets: ["LingoPulseIME"]),
    ],
    targets: [
        .executableTarget(
            name: "LingoPulseApp",
            path: "Sources/LingoPulseApp"
        ),
        .executableTarget(
            name: "LingoPulseIME",
            path: "Sources/LingoPulseIME",
            linkerSettings: [
                .linkedFramework("InputMethodKit"),
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "LingoPulseAppTests",
            dependencies: ["LingoPulseApp"],
            path: "Tests/LingoPulseAppTests"
        ),
    ]
)
