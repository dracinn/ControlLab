// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vader5MacOS",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Vader5Core", targets: ["Vader5Core"]),
        .executable(name: "vader5-cli", targets: ["Vader5CLI"]),
        .executable(name: "Vader5GUI", targets: ["Vader5GUI"]),
    ],
    targets: [
        .target(
            name: "Vader5CoreC",
            path: "Sources/Vader5CoreC",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .target(
            name: "Vader5Core",
            dependencies: ["Vader5CoreC"],
            path: "Sources/Vader5Core",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "Vader5CLI",
            dependencies: ["Vader5Core"],
            path: "Sources/Vader5CLI"
        ),
        .executableTarget(
            name: "Vader5GUI",
            dependencies: ["Vader5Core"],
            path: "Sources/Vader5GUI",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "Vader5CoreTests",
            dependencies: ["Vader5Core"],
            path: "Tests/Vader5CoreTests"
        ),
    ]
)
