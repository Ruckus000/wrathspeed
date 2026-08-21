import Foundation

enum UITestingSupport {
    static let resetStoreLaunchArgument = "-uiTestingResetStore"
    static let simulateLiveRecordingLaunchArgument = "-uiTestingSimulateLiveRecording"
    static let seedInProgressMobilityLaunchArgument = "-uiTestingSeedInProgressMobility"
    static let presentMobilityPreRunLaunchArgument = "-uiTestingPresentMobilityPreRun"
    static let seedTodayRunLaunchArgument = "-uiTestingSeedTodayRun"
    static let seedTodayStrengthLaunchArgument = "-uiTestingSeedTodayStrength"

    /// True when UI tests pass `-uiTestingResetStore` in Debug builds only.
    static var shouldResetStore: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(resetStoreLaunchArgument)
        #else
        false
        #endif
    }

    /// True when UI tests request a local-only live run without HealthKit hardware.
    static var shouldSimulateLiveRecording: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(simulateLiveRecordingLaunchArgument)
        #else
        false
        #endif
    }

    /// Seeds an in-progress mobility session after onboarding confirmation.
    static var shouldSeedInProgressMobility: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(seedInProgressMobilityLaunchArgument)
        #else
        false
        #endif
    }

    /// Presents the pre-run mobility player when Today appears.
    static var shouldPresentMobilityPreRun: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(presentMobilityPreRunLaunchArgument)
        #else
        false
        #endif
    }

    /// Moves the next scheduled run onto today. A generated plan puts runs on particular
    /// weekdays, so whether Today has one to start depends on the day the suite runs.
    static var shouldSeedTodayRun: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(seedTodayRunLaunchArgument)
        #else
        false
        #endif
    }

    /// Moves the next scheduled strength session onto today, for the same reason.
    static var shouldSeedTodayStrength: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(seedTodayStrengthLaunchArgument)
        #else
        false
        #endif
    }
}
