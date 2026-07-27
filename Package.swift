// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ControlLab",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Vader5Core", targets: ["Vader5Core"]),
        .executable(name: "controllab-cli", targets: ["Vader5CLI"]),
        .executable(name: "ControlLab", targets: ["ControlLab"]),
        .executable(
            name: "ControlLabRGBPreview",
            targets: ["ControlLabRGBPreview"]),
    ],
    targets: [
        .binaryTarget(
            name: "SDL3",
            path: "Vendor/SDL3.xcframework"
        ),
        .target(
            name: "SDLGamepadC",
            dependencies: ["SDL3"],
            path: "Sources/SDLGamepadC",
            publicHeadersPath: "include"
        ),
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
            dependencies: ["Vader5CoreC", "SDLGamepadC"],
            path: "Sources/Vader5Core",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "Vader5CLI",
            dependencies: ["Vader5Core"],
            path: "Sources/Vader5CLI",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .executableTarget(
            name: "ControlLab",
            dependencies: ["Vader5Core"],
            path: "Sources/Vader5GUI",
            exclude: [
                "Resources",
                "DockLightingPreview.swift",
                "RGBPreviewApp.swift",
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .executableTarget(
            name: "ControlLabRGBPreview",
            dependencies: ["Vader5Core"],
            path: "Sources/Vader5GUI",
            exclude: [
                "Resources",
                "BridgeViewModel.swift",
                "ContentView.swift",
                "ControlLabApp.swift",
                "ControllerConfigurationView.swift",
                "ControllerInputView.swift",
                "DockFactoryLightingStore.swift",
                "FirmwareDiagnosticsView.swift",
                "RGBPreviewProcess.swift",
                "SpaceStationTheme.swift",
            ],
            sources: [
                "DockLightingPreview.swift",
                "RGBPreviewApp.swift",
            ],
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
