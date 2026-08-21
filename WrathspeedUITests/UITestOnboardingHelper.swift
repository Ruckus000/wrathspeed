import XCTest

@MainActor
enum UITestOnboardingHelper {
    static let resetStoreLaunchArgument = "-uiTestingResetStore"

    static let englishLocaleArguments = [
        "-AppleLanguages", "(en)",
        "-AppleLocale", "en_US"
    ]

    static let simulateLiveRecordingLaunchArgument = "-uiTestingSimulateLiveRecording"
    static let seedInProgressMobilityLaunchArgument = "-uiTestingSeedInProgressMobility"
    static let presentMobilityPreRunLaunchArgument = "-uiTestingPresentMobilityPreRun"
    static let seedTodayRunLaunchArgument = "-uiTestingSeedTodayRun"
    static let seedTodayStrengthLaunchArgument = "-uiTestingSeedTodayStrength"

    static func freshLaunchArguments(
        simulateLiveRecording: Bool = false,
        seedInProgressMobility: Bool = false,
        presentMobilityPreRun: Bool = false,
        seedTodayRun: Bool = false,
        seedTodayStrength: Bool = false
    ) -> [String] {
        var args = [resetStoreLaunchArgument] + englishLocaleArguments
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
        return args
    }

    static func configureFreshLaunch(
        _ app: XCUIApplication,
        contentSizeCategory: String? = nil,
        simulateLiveRecording: Bool = false,
        seedInProgressMobility: Bool = false,
        presentMobilityPreRun: Bool = false,
        seedTodayRun: Bool = false,
        seedTodayStrength: Bool = false
    ) {
        app.launchArguments = freshLaunchArguments(
            simulateLiveRecording: simulateLiveRecording,
            seedInProgressMobility: seedInProgressMobility,
            presentMobilityPreRun: presentMobilityPreRun,
            seedTodayRun: seedTodayRun,
            seedTodayStrength: seedTodayStrength
        )
        if let contentSizeCategory {
            app.launchEnvironment["UIPreferredContentSizeCategoryName"] = contentSizeCategory
        } else {
            app.launchEnvironment.removeValue(forKey: "UIPreferredContentSizeCategoryName")
        }
    }

    static func configurePreservingStoreLaunch(_ app: XCUIApplication) {
        app.launchArguments = englishLocaleArguments
        app.launchEnvironment.removeValue(forKey: "UIPreferredContentSizeCategoryName")
    }

    static func completeOnboarding(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        if app.buttons["TODAY"].waitForExistence(timeout: 2) {
            dismissHealthPrimerIfNeeded(app)
            return
        }

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
