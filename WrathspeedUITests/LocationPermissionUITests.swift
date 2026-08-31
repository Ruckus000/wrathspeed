import XCTest

/// Covers the location primer and, more importantly, the path out of a refusal.
///
/// Only the refusal half is driven here, and deliberately: DON'T ALLOW never calls
/// CoreLocation, so it stays inside the app and is deterministic. Tapping ALLOW raises the
/// real system prompt, which is a springboard alert an erased simulator answers differently
/// depending on how it was booted -- exactly the kind of flake this suite has been bitten by
/// before.
@MainActor
final class LocationPermissionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Before this flow existed, a refused (or simply never-asked) location permission left
    /// outdoor runs silently degraded: preflight said "NOT YET ALLOWED" forever, nothing
    /// explained it, and there was no way to switch to something that works. Both exits here
    /// have to reach a workout you can actually start.
    func testDecliningTheLocationPrimerOffersTheTreadmill() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(
            app,
            simulateLiveRecording: true,
            seedTodayRun: true,
            seedCompletedOnboarding: true,
            presentLocationPrimer: true
        )
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        let startRun = app.buttons["Start today's run"]
        XCTAssertTrue(startRun.waitForExistence(timeout: 8), "Today's run action missing")
        startRun.tap()

        // The run is outdoor by default, so arriving at preflight is what raises the primer.
        let decline = app.buttons["location_primer_decline"]
        XCTAssertTrue(decline.waitForExistence(timeout: 8), "Location primer did not appear on an outdoor preflight")
        decline.tap()

        let treadmill = app.buttons["location_denied_treadmill"]
        XCTAssertTrue(treadmill.waitForExistence(timeout: 5), "Declining left no way forward")
        XCTAssertTrue(app.buttons["location_denied_outside"].exists, "Running outside anyway must stay available")
        treadmill.tap()

        // Back on preflight, switched over, and startable -- the point of the whole screen.
        XCTAssertTrue(app.staticTexts["PREFLIGHT"].waitForExistence(timeout: 5), "Did not return to preflight")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'TREADMILL SPEED'")).firstMatch
                .waitForExistence(timeout: 5),
            "Switching to treadmill did not change the preflight"
        )
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 3), "Start action missing after switching")
    }

    /// The regression that broke `PreflightLiveStartUITests`: the primer covers preflight the
    /// moment an outdoor run reaches it, and every simulator is undetermined after an erase,
    /// so without the opt-in gate it eats the START WORKOUT tap of every outdoor run test.
    func testPrimerStaysOutOfTheWayWhenNotOptedIn() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(
            app,
            simulateLiveRecording: true,
            seedTodayRun: true,
            seedCompletedOnboarding: true
        )
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        let startRun = app.buttons["Start today's run"]
        XCTAssertTrue(startRun.waitForExistence(timeout: 8))
        startRun.tap()

        XCTAssertTrue(app.staticTexts["PREFLIGHT"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.buttons["location_primer_allow"].waitForExistence(timeout: 2),
            "The primer must not present under UI test unless a test asks for it"
        )
        XCTAssertTrue(app.buttons["Start workout"].isHittable, "START WORKOUT must be reachable, not behind a cover")
    }
}
