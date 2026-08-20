import XCTest

@MainActor
final class GuidedResumeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMobilitySessionResumesAfterRelaunch() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, presentMobilityPreRun: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        XCTAssertTrue(
            app.buttons["NEXT"].waitForExistence(timeout: 12),
            "Mobility player did not open after onboarding"
        )

        app.buttons["NEXT"].tap()

        XCTAssertTrue(
            app.staticTexts["2 / 3"].waitForExistence(timeout: 5),
            "Expected advance to movement 2 after NEXT"
        )

        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()

        XCTAssertTrue(
            app.buttons["NEXT"].waitForNonExistence(timeout: 6),
            "Mobility player did not dismiss after close"
        )
        XCTAssertTrue(app.buttons["TODAY"].waitForExistence(timeout: 5))

        app.terminate()
        XCTAssertFalse(app.state == .runningForeground || app.state == .runningBackground)

        UITestOnboardingHelper.configurePreservingStoreLaunch(app)
        app.launch()

        XCTAssertTrue(app.buttons["TODAY"].waitForExistence(timeout: 15))
        UITestOnboardingHelper.dismissBlockingAlertIfNeeded(app)
        app.buttons["TODAY"].tap()

        let resume = app.buttons["mobility-row-pre_run"]
        if !resume.waitForExistence(timeout: 4) {
            app.swipeUp()
        }
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "Resume affordance missing after relaunch")
        XCTAssertTrue(resume.label.hasPrefix("Resume"), "Expected resume label after relaunch, got \(resume.label)")
        if !resume.isHittable {
            app.swipeUp()
        }
        resume.tap()
        if !app.buttons["Close"].waitForExistence(timeout: 4) {
            let labeled = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resume'")).firstMatch
            if labeled.exists {
                labeled.tap()
            } else {
                resume.tap()
            }
        }
        XCTAssertTrue(
            app.buttons["Close"].waitForExistence(timeout: 8),
            "Resume row did not open the mobility player"
        )
        XCTAssertTrue(
            app.staticTexts["2 / 3"].waitForExistence(timeout: 8),
            "Mobility player did not restore movement progress after resume"
        )
    }
}
