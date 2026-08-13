import XCTest

final class OnboardingFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingPreviewAndConfirmationReachMainTabs() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestingResetStore",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        tapNext(times: 2, in: app)

        let miles = app.buttons["Miles"]
        if miles.waitForExistence(timeout: 3) {
            miles.tap()
        }
        tapNext(times: 3, in: app)

        let buildDraft = app.buttons["BUILD DRAFT →"]
        XCTAssertTrue(buildDraft.waitForExistence(timeout: 8), "Build draft button missing")
        buildDraft.tap()

        let confirm = app.buttons["CONFIRM PLAN →"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), "Draft preview confirm button missing")
        confirm.tap()

        let today = app.buttons["TODAY"]
        XCTAssertTrue(today.waitForExistence(timeout: 15), "Today tab did not appear after confirmation")

        if app.buttons["ALLOW HEALTH ACCESS"].waitForExistence(timeout: 3) {
            app.buttons["NOT NOW"].tap()
        }

        XCTAssertTrue(app.buttons["PLAN"].exists)
        XCTAssertTrue(app.buttons["HISTORY"].exists)
        XCTAssertTrue(app.buttons["SETTINGS"].exists)
    }

    private func tapNext(times: Int, in app: XCUIApplication) {
        for _ in 0..<times {
            let next = app.buttons["NEXT →"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
    }
}
