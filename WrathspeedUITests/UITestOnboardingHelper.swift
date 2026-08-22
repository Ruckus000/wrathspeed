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

    static func freshLaunchArguments(
        simulateLiveRecording: Bool = false,
        seedInProgressMobility: Bool = false,
        presentMobilityPreRun: Bool = false,
        seedTodayRun: Bool = false,
        seedTodayStrength: Bool = false,
        seedCompletedOnboarding: Bool = false,
        skipCountdown: Bool = false
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
        skipCountdown: Bool = false
    ) {
        app.launchArguments = freshLaunchArguments(
            simulateLiveRecording: simulateLiveRecording,
            seedInProgressMobility: seedInProgressMobility,
            presentMobilityPreRun: presentMobilityPreRun,
            seedTodayRun: seedTodayRun,
            seedTodayStrength: seedTodayStrength,
            seedCompletedOnboarding: seedCompletedOnboarding,
            skipCountdown: skipCountdown
        )
        if let contentSizeCategory {
            app.launchEnvironment["UIPreferredContentSizeCategoryName"] = contentSizeCategory
        } else {
            app.launchEnvironment.removeValue(forKey: "UIPreferredContentSizeCategoryName")
        }
    }

    static func configurePreservingStoreLaunch(_ app: XCUIApplication) {
        app.launchArguments = [uiTestingLaunchArgument] + englishLocaleArguments
        app.launchEnvironment.removeValue(forKey: "UIPreferredContentSizeCategoryName")
    }

    static func completeOnboarding(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // Branch on the launch arguments this test object was configured with, not on a
        // screen probe: the fast path must never quietly degrade into the slow one. A seed
        // that stopped working has to fail here rather than hide behind a slow green run.
        if app.launchArguments.contains(seedCompletedOnboardingLaunchArgument) {
            XCTAssertTrue(
                app.buttons["TODAY"].waitForExistence(timeout: 15),
                "Seeded launch did not reach Today — onboarding seed failed",
                file: file,
                line: line
            )
            // No health primer to dismiss: the app suppresses it on a seeded launch, exactly
            // as it already does on a reset one.
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
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 1) else { return }
        for title in ["Allow While Using App", "Allow", "OK", "Don't Allow"] {
            let button = alert.buttons[title]
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
