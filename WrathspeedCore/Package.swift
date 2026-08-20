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
            exclude: ["InstantWorkoutFactory.swift"],
            resources: [
                .process("Resources"),
                // Copied, not processed: these are already-encoded H.264 clips and the
                // Media/ subdirectory has to survive into the bundle for lookup by
                // subdirectory. See Tools/exercise-media/build_media.py.
                .copy("Media"),
            ]
        ),
        .testTarget(
            name: "WrathspeedCoreTests",
            dependencies: ["WrathspeedCore"]
        ),
    ]
)
