# Wrathspeed

Wrathspeed is an Apple-platform running coach app: an iOS app (`Wrathspeed`), a companion watchOS app (`WrathspeedWatch`), and iOS widgets / Live Activities (`WrathspeedWidgets`). Shared training logic lives in the pure-Swift package `WrathspeedCore`. The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Cursor Cloud specific instructions

The Cursor Cloud VM runs Linux. Only part of this repo can be built/run here.

### What runs on Linux (cloud VM)
- `WrathspeedCore` is a pure Swift package (only imports `Foundation` + the `Testing` framework) and is the only target that builds and tests on the Linux cloud VM.
- The Swift 6.2.1 toolchain is preinstalled at `/opt/swift` and symlinked onto `PATH` via `/usr/local/bin` (so `swift` just works). It is baked into the VM snapshot, so the startup update script does not reinstall it.
- Commands (run from the package directory):
  - Build: `cd WrathspeedCore && swift build`
  - Test: `cd WrathspeedCore && swift test` (uses swift-testing; currently 34 tests / 8 suites)
  - `WrathspeedCore` has no external SwiftPM dependencies, so `swift package resolve` is effectively a no-op.
- There is no separate lint tool configured; `swift build` surfaces compiler warnings/errors.

### What does NOT run on Linux
- The `Wrathspeed` (iOS), `WrathspeedWatch` (watchOS), and `WrathspeedWidgets` targets, plus the `Session`/`Shared` sources, depend on Apple-only frameworks (`SwiftUI`, `HealthKit`, `WidgetKit`, `WatchKit`, `ActivityKit`, `WatchConnectivity`, `UIKit`). They require macOS + Xcode 26 (iOS/watchOS 26 deployment targets) and cannot be compiled, run, or simulated on the Linux cloud VM. Do not attempt `xcodebuild` here.
- To work on those targets you need a Mac: regenerate the project with `xcodegen generate` (from `project.yml`) and open `Wrathspeed.xcodeproj` in Xcode.

### Verifying core logic without the app
Because the GUI can't run here, exercise `WrathspeedCore` directly. `swift test` covers plan generation, pace/VDOT math, adaptation, cue policy, and the workout stepper. You can also drive the API from a throwaway SwiftPM executable that adds `.package(path: "<repo>/WrathspeedCore")` and calls e.g. `PlanGenerator.generate(_:)` / `PaceCalculator.zones(vdot:)`.
