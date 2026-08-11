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
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "WrathspeedCoreTests",
            dependencies: ["WrathspeedCore"]
        ),
    ]
)
