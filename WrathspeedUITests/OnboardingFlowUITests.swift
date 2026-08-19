import XCTest

@MainActor
final class OnboardingFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingPreviewAndConfirmationReachMainTabs() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        XCTAssertTrue(app.buttons["PLAN"].exists)
        XCTAssertTrue(app.buttons["HISTORY"].exists)
        XCTAssertTrue(app.buttons["SETTINGS"].exists)
    }
}
