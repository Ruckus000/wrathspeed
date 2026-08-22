import Foundation

enum UITestingSupport {
    static let resetStoreLaunchArgument = "-uiTestingResetStore"
    static let uiTestingLaunchArgument = "-uiTesting"
    static let simulateLiveRecordingLaunchArgument = "-uiTestingSimulateLiveRecording"
    static let seedInProgressMobilityLaunchArgument = "-uiTestingSeedInProgressMobility"
    static let presentMobilityPreRunLaunchArgument = "-uiTestingPresentMobilityPreRun"
    static let seedTodayRunLaunchArgument = "-uiTestingSeedTodayRun"
    static let seedTodayStrengthLaunchArgument = "-uiTestingSeedTodayStrength"
    static let seedCompletedOnboardingLaunchArgument = "-uiTestingSeedCompletedOnboarding"
    static let skipCountdownLaunchArgument = "-uiTestingSkipCountdown"

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

    /// Builds and confirms the onboarding plan at launch, through the same API the
    /// onboarding screen calls, so a test whose subject is not onboarding does not have to
    /// replay nine taps and a plan build to reach Today.
    static var shouldSeedCompletedOnboarding: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(seedCompletedOnboardingLaunchArgument)
        #else
        false
        #endif
    }

    /// Skips the three-second pre-roll before a session starts collecting.
    ///
    /// Deliberately its own argument rather than keying off `isUITesting`: hosted unit
    /// tests set that too, and `SessionRecoveryTests` needs a real countdown to cancel
    /// during.
    static var shouldSkipCountdown: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(skipCountdownLaunchArgument)
        #else
        false
        #endif
    }

    /// True whenever the app is being driven by a UI test.
    ///
    /// Deliberately a separate argument from `resetStoreLaunchArgument`: a test that
    /// relaunches to check persistence must keep its store, and keying "am I under test"
    /// off the reset flag meant the app silently reverted to production behaviour on that
    /// second launch -- raising a permission alert that blocked every later tap.
    static var isUITesting: Bool {
        #if DEBUG
        // Hosted unit tests launch the app with no arguments at all, and some construct an
        // AppStore without injecting a scheduler. That reached the live one and raised a
        // real notification prompt, which then sat over the UI tests that ran afterwards.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        return ProcessInfo.processInfo.arguments.contains(uiTestingLaunchArgument)
        #else
        return false
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
