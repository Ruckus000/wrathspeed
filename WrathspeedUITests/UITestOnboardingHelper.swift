import XCTest

@MainActor
enum UITestOnboardingHelper {
    static let resetStoreLaunchArgument = "-uiTestingResetStore"
    /// Marks every launch, including relaunches that deliberately keep the store, so the
    /// app never reverts to production behaviour part-way through a test.
    static let uiTestingLaunchArgument = "-uiTesting"

    static let englishLocaleArguments = [
        "-AppleLanguages", "(en)",
        "-AppleLocale", "en_US"
    ]

    static let simulateLiveRecordingLaunchArgument = "-uiTestingSimulateLiveRecording"
    static let seedInProgressMobilityLaunchArgument = "-uiTestingSeedInProgressMobility"
    static let presentMobilityPreRunLaunchArgument = "-uiTestingPresentMobilityPreRun"
    // A UI test must not depend on what the generated plan happens to schedule today.
    // Runs and strength sessions land on particular weekdays, so a test that reaches for
    // "today's run" passes on some days and fails on others -- which is exactly how two
    // tests here came to fail only on a Friday. There are two sanctioned ways around it:
    // seed what you need with the arguments below, or navigate through the weekly
    // calendar, which always shows a full week. Mobility sessions are generated for every
    // day and need neither.
    static let seedTodayRunLaunchArgument = "-uiTestingSeedTodayRun"
    static let seedTodayStrengthLaunchArgument = "-uiTestingSeedTodayStrength"
    // Builds and confirms the plan at launch through the same AppStore calls the onboarding
    // screen makes. Opt-in and defaulted off, so no test can silently lose its onboarding
    // coverage just by forgetting a parameter -- OnboardingFlowUITests keeps the real taps.
    static let seedCompletedOnboardingLaunchArgument = "-uiTestingSeedCompletedOnboarding"
    static let skipCountdownLaunchArgument = "-uiTestingSkipCountdown"
    // Opt-in, and off for every other test on purpose: the primer covers preflight as soon
    // as an outdoor run reaches it on a simulator that has never been asked about location,
    // which swallows the START WORKOUT tap.
    static let presentLocationPrimerLaunchArgument = "-uiTestingPresentLocationPrimer"

    static func freshLaunchArguments(
        simulateLiveRecording: Bool = false,
        seedInProgressMobility: Bool = false,
        presentMobilityPreRun: Bool = false,
        seedTodayRun: Bool = false,
        seedTodayStrength: Bool = false,
        seedCompletedOnboarding: Bool = false,
        skipCountdown: Bool = false,
        presentLocationPrimer: Bool = false
    ) -> [String] {
        var args = [resetStoreLaunchArgument, uiTestingLaunchArgument] + englishLocaleArguments
        if simulateLiveRecording {
            args.append(simulateLiveRecordingLaunchArgument)
        }
        if seedInProgressMobility {
            args.append(seedInProgressMobilityLaunchArgument)
        }
        if presentMobilityPreRun {
            args.append(presentMobilityPreRunLaunchArgument)
        }
        if seedTodayRun {
            args.append(seedTodayRunLaunchArgument)
        }
        if seedTodayStrength {
            args.append(seedTodayStrengthLaunchArgument)
        }
        if seedCompletedOnboarding {
            args.append(seedCompletedOnboardingLaunchArgument)
        }
        if skipCountdown {
            args.append(skipCountdownLaunchArgument)
        }
        if presentLocationPrimer {
            args.append(presentLocationPrimerLaunchArgument)
        }
        return args
    }

    static func configureFreshLaunch(
        _ app: XCUIApplication,
        contentSizeCategory: String? = nil,
        simulateLiveRecording: Bool = false,
        seedInProgressMobility: Bool = false,
        presentMobilityPreRun: Bool = false,
        seedTodayRun: Bool = false,
        seedTodayStrength: Bool = false,
        seedCompletedOnboarding: Bool = false,
        skipCountdown: Bool = false,
        presentLocationPrimer: Bool = false
    ) {
        app.launchArguments = freshLaunchArguments(
            simulateLiveRecording: simulateLiveRecording,
            seedInProgressMobility: seedInProgressMobility,
            presentMobilityPreRun: presentMobilityPreRun,
            seedTodayRun: seedTodayRun,
            seedTodayStrength: seedTodayStrength,
            seedCompletedOnboarding: seedCompletedOnboarding,
            skipCountdown: skipCountdown,
            presentLocationPrimer: presentLocationPrimer
        )
        // As a launch *argument*, not a launch environment variable. The environment form is
        // silently inert -- measured on iPhone 16e / iOS 26.0, the headline rendered identically
        // with and without it.
        //
        // The name is validated because an unrecognised one is *also* silently inert, and this
        // suite shipped one for months: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        // is not a real category, so the test asserting Dynamic Type reachability was really
        // asserting it at the default size. Measured: the invalid name leaves the headline at
        // 13.3pt, the valid one takes it to 78.7pt. Failing loudly is the only way this stays
        // honest, since both spellings look equally plausible.
        if let contentSizeCategory {
            precondition(
                Self.contentSizeCategoryNames.contains(contentSizeCategory),
                """
                Unknown content size category "\(contentSizeCategory)". iOS ignores names it does \
                not recognise, so the test would pass at the default size. Valid names: \
                \(Self.contentSizeCategoryNames.sorted().joined(separator: ", "))
                """
            )
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
        }
        app.launchEnvironment.removeValue(forKey: "UIPreferredContentSizeCategoryName")
    }

    /// The names iOS actually recognises. Note the accessibility sizes abbreviate -- XL, not
    /// ExtraLarge -- which is exactly the trap this list exists to close.
    static let contentSizeCategoryNames: Set<String> = [
        "UICTContentSizeCategoryXS",
        "UICTContentSizeCategoryS",
        "UICTContentSizeCategoryM",
        "UICTContentSizeCategoryL",
        "UICTContentSizeCategoryXL",
        "UICTContentSizeCategoryXXL",
        "UICTContentSizeCategoryXXXL",
        "UICTContentSizeCategoryAccessibilityM",
        "UICTContentSizeCategoryAccessibilityL",
        "UICTContentSizeCategoryAccessibilityXL",
        "UICTContentSizeCategoryAccessibilityXXL",
        "UICTContentSizeCategoryAccessibilityXXXL",
    ]

    static func configurePreservingStoreLaunch(_ app: XCUIApplication) {
        app.launchArguments = [uiTestingLaunchArgument] + englishLocaleArguments
        app.launchEnvironment.removeValue(forKey: "UIPreferredContentSizeCategoryName")
    }

    static func completeOnboarding(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // Branch on the launch arguments this test object was configured with, not on a
        // screen probe: the fast path must never quietly degrade into the slow one. A seed
        // that stopped working has to fail here rather than hide behind a slow green run.
        if app.launchArguments.contains(seedCompletedOnboardingLaunchArgument) {
            // The app's own health primer is suppressed on a seeded launch, exactly as it is
            // on a reset one. The springboard alert about workout background access is not
            // ours to suppress: iOS raises it because the app declares `workout-processing`,
            // and it is back on the next launch. It covers roughly the top 234pt, so left up
            // it silently eats every tap aimed at the plan header links or a cover's close
            // button -- the tap is synthesised, springboard swallows it, and the test reports
            // an empty plan. That is what made CI red on any simulator that had not already
            // acknowledged it. The slow path below has always dismissed it; this one must too.
            dismissSystemAlertIfNeeded()
            XCTAssertTrue(
                app.buttons["TODAY"].waitForExistence(timeout: 15),
                "Seeded launch did not reach Today — onboarding seed failed",
                file: file,
                line: line
            )
            return
        }

        // The in-app check goes first because it is the cheap one. `dismissSystemAlertIfNeeded`
        // waits on springboard, which cannot return early when there is no alert to find.
        if app.buttons["TODAY"].waitForExistence(timeout: 2) {
            dismissHealthPrimerIfNeeded(app)
            return
        }
        dismissSystemAlertIfNeeded()

        tapNext(times: 2, in: app, file: file, line: line)

        let miles = app.buttons["Miles"]
        if miles.waitForExistence(timeout: 3) {
            miles.tap()
        }

        tapNext(times: 3, in: app, file: file, line: line)

        let buildDraft = app.buttons["BUILD DRAFT →"]
        XCTAssertTrue(buildDraft.waitForExistence(timeout: 8), "Build draft button missing", file: file, line: line)
        buildDraft.tap()

        let buildingDone = NSPredicate(format: "exists == false")
        let buildingExpectation = XCTNSPredicateExpectation(predicate: buildingDone, object: app.staticTexts["STAND BY"])
        _ = XCTWaiter.wait(for: [buildingExpectation], timeout: 20)

        let confirm = app.buttons["CONFIRM PLAN →"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15), "Draft preview confirm button missing", file: file, line: line)
        confirm.tap()

        let today = app.buttons["TODAY"]
        XCTAssertTrue(today.waitForExistence(timeout: 15), "Today tab did not appear after confirmation", file: file, line: line)

        dismissHealthPrimerIfNeeded(app)
    }

    /// Backstop for any system alert that still reaches the screen -- Health or location,
    /// which other flows can raise. A UI test cannot dismiss these through `app`, because
    /// they belong to springboard.
    /// Scrolls until `element` can actually be tapped.
    ///
    /// Checking `exists` is not enough on a WSScreen: it is an eager VStack inside a
    /// ScrollView, so every row exists whether or not it is on screen. Only `isHittable`
    /// tells the two apart, which is why the older exists-based loops never scrolled.
    static func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 10) {
        guard element.exists else { return }
        var tries = 0
        while !element.isHittable && tries < attempts {
            app.swipeUp()
            tries += 1
        }
    }

    static func dismissSystemAlertIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let titles = ["Allow While Using App", "Allow", "OK", "Don't Allow"]
        // Deliberately not `springboard.alerts`. iOS 26 does not present the workout
        // background-access notice -- the one it raises because the app declares
        // `workout-processing` -- as an alert element: `springboard.alerts.count` is 0 while
        // its "OK" and "Settings" buttons are sitting right there on springboard. The old
        // `alerts.firstMatch` guard therefore returned early and never dismissed it, which
        // is how a notice covering the top of the screen survived every test. Querying the
        // buttons reaches both that notice and ordinary alerts.
        let anyButton = springboard.buttons
            .matching(NSPredicate(format: "label IN %@", titles))
            .firstMatch
        guard anyButton.waitForExistence(timeout: 1) else { return }
        // One bounded wait above, then pick by preference: a location alert offers both
        // "Allow While Using App" and "Don't Allow", and hierarchy order is not preference.
        for title in titles {
            let button = springboard.buttons[title]
            if button.exists {
                button.tap()
                return
            }
        }
    }

    static func dismissBlockingAlertIfNeeded(_ app: XCUIApplication) {
        let alertTitle = app.staticTexts["SOMETHING WENT WRONG"]
        if alertTitle.waitForExistence(timeout: 1) {
            let ok = app.buttons["OK"]
            if ok.exists {
                ok.tap()
            }
        }
    }

    static func dismissHealthPrimerIfNeeded(_ app: XCUIApplication) {
        if app.buttons["ALLOW HEALTH ACCESS"].waitForExistence(timeout: 2) {
            let notNow = app.buttons["NOT NOW"]
            if notNow.exists {
                notNow.tap()
            }
        } else if app.buttons["NOT NOW"].waitForExistence(timeout: 1) {
            app.buttons["NOT NOW"].tap()
        }
        waitForHealthPrimerDismissed(app)
    }

    static func waitForHealthPrimerDismissed(_ app: XCUIApplication, timeout: TimeInterval = 5) {
        let primerTitle = app.staticTexts["CONNECT\nAPPLE HEALTH"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !primerTitle.exists && !app.buttons["ALLOW HEALTH ACCESS"].exists {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    static func tapNext(
        times: Int,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<times {
            let next = app.buttons["NEXT →"]
            XCTAssertTrue(next.waitForExistence(timeout: 5), "NEXT → missing", file: file, line: line)
            next.tap()
        }
    }
}
