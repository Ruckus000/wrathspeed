// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WrathspeedCore",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v15),
    ],
    products: [
        .library(name: "WrathspeedCore", targets: ["WrathspeedCore"]),
    ],
    targets: [
        .target(
            name: "WrathspeedCore",
            exclude: ["InstantWorkoutFactory.swift"]
        ),
        .testTarget(
            name: "WrathspeedCoreTests",
            dependencies: ["WrathspeedCore"]
        ),
    ]
)
