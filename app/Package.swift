// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LingoPulseApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LingoPulseApp", targets: ["LingoPulseApp"]),
        .executable(name: "LingoPulseIME", targets: ["LingoPulseIME"]),
        .library(name: "LingoPulseIMECore", targets: ["LingoPulseIMECore"]),
    ],
    targets: [
        .executableTarget(
            name: "LingoPulseApp",
            path: "Sources/LingoPulseApp"
        ),
        .target(
            name: "LingoPulseIMECore",
            path: "Sources/LingoPulseIMECore"
        ),
        .executableTarget(
            name: "LingoPulseIME",
            dependencies: ["LingoPulseIMECore"],
            path: "Sources/LingoPulseIME",
            linkerSettings: [
                .linkedFramework("InputMethodKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "LingoPulseAppTests",
            dependencies: ["LingoPulseApp"],
            path: "Tests/LingoPulseAppTests"
        ),
        .testTarget(
            name: "LingoPulseIMETests",
            dependencies: ["LingoPulseIMECore"],
            path: "Tests/LingoPulseIMETests"
        ),
    ]
)
