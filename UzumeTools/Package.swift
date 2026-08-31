// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PhospheneTools",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "CheckVisualReferences",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CheckVisualReferences"
        ),
    ]
)
