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
            resources: [.copy("Shaders"), .copy("Resources/Fonts")]
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
        // Executable targets below are retained diagnostics — each is
        // decision-backed and referenced by docs/RUNBOOK.md or a Scripts/
        // wrapper; see docs/AUDIT_KEEPLIST.md before re-flagging any as dead
        // (the 2026-06-14 audit false-positived several). (PUB.4)
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
            name: "BeatThisActivationDumper",
            dependencies: [
                "DSP",
                "ML",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/BeatThisActivationDumper"
        ),
        .executableTarget(
            name: "QualityReelAnalyzer",
            dependencies: [
                "DSP",
                "ML",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/QualityReelAnalyzer"
        ),
        .executableTarget(
            name: "CorpusCensusRunner",
            dependencies: [
                "Audio",
                "DSP",
                "ML",
                "Session",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CorpusCensusRunner"
        ),
        .executableTarget(
            name: "InstrumentFamilyDumper",
            dependencies: [
                "ML",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/InstrumentFamilyDumper"
        ),
        .executableTarget(
            name: "TonalDumper",
            dependencies: [
                "Audio",
                "DSP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/TonalDumper"
        ),
        .executableTarget(
            name: "UtilityCostTableUpdater",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/UtilityCostTableUpdater"
        ),
        .executableTarget(
            name: "PresetSessionReplay",
            dependencies: [
                "Shared",
                "Presets",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/PresetSessionReplay"
        ),
        .executableTarget(
            name: "ColdStartVerifier",
            dependencies: [
                "Audio",
                "DSP",
                "Session",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/ColdStartVerifier"
        ),
        .executableTarget(
            name: "ChainHealthAnalyzer",
            dependencies: ["Shared"],
            path: "Sources/ChainHealthAnalyzer"
        ),
        .testTarget(
            name: "PhospheneEngineTests",
            dependencies: [
                "Shared", "Audio", "DSP", "ML", "Presets",
                "Renderer", "Session", "Orchestrator", "Diagnostics",
                "CorpusCensusRunner", "TonalDumper", "PresetSessionReplay",
            ],
            path: "Tests/PhospheneEngineTests",
            resources: [
                .copy("Regression/Fixtures"),
                .copy("Fixtures/beat_this_reference"),
                .copy("Fixtures/fbs"),
                .copy("Fixtures/panns_reference"),
                .copy("Fixtures/route_coverage"),
            ]
        ),
    ]
)
