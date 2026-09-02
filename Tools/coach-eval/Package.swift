// swift-tools-version: 6.2
import PackageDescription

// The coach evaluation harness. A plain macOS executable that runs the shipped model contract
// (`WrathspeedCore/CoachModelContract.swift`) against Apple's on-device model, so the prompt
// that ships is the prompt that gets measured. No simulator, no XCTest: every XCTest run sees
// the model as unavailable by design, which is why this package exists.
let package = Package(
    name: "coach-eval",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(path: "../../WrathspeedCore"),
    ],
    targets: [
        .executableTarget(
            name: "coach-eval",
            dependencies: [.product(name: "WrathspeedCore", package: "WrathspeedCore")]
        ),
    ]
)
