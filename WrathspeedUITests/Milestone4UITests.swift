import XCTest

final class Milestone4UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWeeklyCalendarAndManagePlanFlows() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestingResetStore",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        completeOnboarding(app)

        app.buttons["PLAN"].tap()
        let calendar = app.buttons["Open weekly calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        calendar.tap()

        XCTAssertTrue(app.buttons["Previous week"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Next week"].exists)

        app.buttons["Back to plan"].tap()
        app.buttons["Manage plan schedule"].tap()
        XCTAssertTrue(app.buttons["PREVIEW CHANGES"].waitForExistence(timeout: 5))
        app.buttons["PREVIEW CHANGES"].tap()
        XCTAssertTrue(app.buttons["APPLY SCHEDULE"].waitForExistence(timeout: 5))
        app.buttons["← BACK"].tap()

        app.buttons["TODAY"].tap()
        app.buttons["NOT FEELING 100%?"].tap()
        XCTAssertTrue(app.buttons["APPLY"].waitForExistence(timeout: 5))
        app.buttons["APPLY"].tap()
        app.buttons["NOT FEELING 100%?"].tap()
        XCTAssertTrue(app.buttons["END ADJUSTMENT"].waitForExistence(timeout: 5))
        app.buttons["END ADJUSTMENT"].tap()
    }

    func testDynamicTypeKeepsPlanActionsReachable() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestingResetStore",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment["UIPreferredContentSizeCategoryName"] = "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        app.launch()
        completeOnboarding(app)

        app.buttons["PLAN"].tap()
        let calendar = app.buttons["Open weekly calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        XCTAssertTrue(calendar.isHittable)
        calendar.tap()
        XCTAssertTrue(app.buttons["Back to plan"].waitForExistence(timeout: 5))
    }

    private func completeOnboarding(_ app: XCUIApplication) {
        for _ in 0..<2 {
            app.buttons["NEXT →"].tap()
        }
        if app.buttons["Miles"].waitForExistence(timeout: 2) {
            app.buttons["Miles"].tap()
        }
        for _ in 0..<3 {
            app.buttons["NEXT →"].tap()
        }
        app.buttons["BUILD DRAFT →"].tap()
        let confirm = app.buttons["CONFIRM PLAN →"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20))
        confirm.tap()
        XCTAssertTrue(app.buttons["TODAY"].waitForExistence(timeout: 20))
        if app.buttons["NOT NOW"].waitForExistence(timeout: 2) {
            app.buttons["NOT NOW"].tap()
        }
    }
}
