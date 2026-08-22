import XCTest

@MainActor
final class HistoryEmptyStateUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHistoryShowsEmptyRunsStateWithNoRecordedRuns() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        app.buttons["HISTORY"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'NO RUNS YET'")).firstMatch.waitForExistence(timeout: 5),
            "Empty runs state missing"
        )
    }
}
