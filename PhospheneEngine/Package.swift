// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PhospheneEngine",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PhospheneEngine",
            targets: [
                "Audio",
                "DSP",
                "ML",
                "Renderer",
                "Presets",
                "Orchestrator",
                "Session",
                "Shared"
            ]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-numerics.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Shared",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Numerics", package: "swift-numerics"),
            ],
            path: "Sources/Shared"
        ),
        .target(
            name: "Audio",
            dependencies: [
                "Shared",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            path: "Sources/Audio"
        ),
        .target(
            name: "DSP",
            dependencies: [
                "Shared",
                .product(name: "Numerics", package: "swift-numerics"),
            ],
            path: "Sources/DSP"
        ),
        .target(
            name: "ML",
            dependencies: ["Shared", "Audio"],
            path: "Sources/ML",
            resources: [.copy("Weights")]
        ),
        .target(
            name: "Renderer",
            dependencies: ["Shared"],
            path: "Sources/Renderer",
            resources: [.copy("Shaders")]
        ),
        .target(
            name: "Presets",
            dependencies: ["Shared"],
            path: "Sources/Presets",
            resources: [.copy("Shaders")]
        ),
        .target(
            name: "Session",
            dependencies: ["Shared", "Audio", "DSP", "ML"],
            path: "Sources/Session"
        ),
        .target(
            name: "Orchestrator",
            dependencies: [
                "Shared",
                "Audio",
                "DSP",
                "ML",
                "Renderer",
                "Presets",
                "Session",
            ],
            path: "Sources/Orchestrator"
        ),
        .target(
            name: "Diagnostics",
            dependencies: ["Shared", "Audio", "Renderer"],
            path: "Sources/Diagnostics"
        ),
        .executableTarget(
            name: "SoakRunner",
            dependencies: [
                "Diagnostics",
                "Audio",
                "Renderer",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/SoakRunner"
        ),
        .executableTarget(
            name: "TempoDumpRunner",
            dependencies: [
                "Audio",
                "DSP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/TempoDumpRunner"
        ),
        .executableTarget(
            name: "UtilityCostTableUpdater",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/UtilityCostTableUpdater"
        ),
        .testTarget(
            name: "PhospheneEngineTests",
            dependencies: [
                "Shared", "Audio", "DSP", "ML", "Presets",
                "Renderer", "Session", "Orchestrator", "Diagnostics",
            ],
            path: "Tests/PhospheneEngineTests",
            resources: [
                .copy("Regression/Fixtures"),
                .copy("Fixtures/beat_this_reference"),
            ]
        ),
    ]
)
