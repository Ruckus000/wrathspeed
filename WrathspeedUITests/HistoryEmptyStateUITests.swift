import XCTest

final class HistoryEmptyStateUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHistoryShowsEmptyRunsStateAfterOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestingResetStore",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        tapNext(times: 2, in: app)
        if app.buttons["Miles"].waitForExistence(timeout: 3) {
            app.buttons["Miles"].tap()
        }
        tapNext(times: 3, in: app)
        XCTAssertTrue(app.buttons["BUILD DRAFT →"].waitForExistence(timeout: 8))
        app.buttons["BUILD DRAFT →"].tap()
        XCTAssertTrue(app.buttons["CONFIRM PLAN →"].waitForExistence(timeout: 30))
        app.buttons["CONFIRM PLAN →"].tap()
        XCTAssertTrue(app.buttons["TODAY"].waitForExistence(timeout: 15))
        if app.buttons["NOT NOW"].waitForExistence(timeout: 3) {
            app.buttons["NOT NOW"].tap()
        }

        app.buttons["HISTORY"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'NO RUNS YET'")).firstMatch.waitForExistence(timeout: 5),
            "Empty runs state missing"
        )
    }

    private func tapNext(times: Int, in app: XCUIApplication) {
        for _ in 0..<times {
            let next = app.buttons["NEXT →"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
    }
}
