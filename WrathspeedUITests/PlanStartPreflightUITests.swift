import XCTest

/// Starting a workout from the Plan tab. Today's start button is covered by
/// PreflightLiveStartUITests; this is the other entry point, which goes through the
/// workout detail sheet and had no coverage at all.
@MainActor
final class PlanStartPreflightUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testStartingAWorkoutFromThePlanTabOpensPreflight() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        // Through the weekly calendar rather than the current week: a plan starts
        // mid-week, so which workouts sit in that partial week depends on the weekday.
        app.buttons["PLAN"].tap()
        XCTAssertTrue(
            app.buttons["plan_weekly_calendar"].waitForExistence(timeout: 8),
            "Plan tab did not appear"
        )
        app.buttons["plan_weekly_calendar"].tap()

        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'weekly_calendar_workout_'")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "No workout in the weekly calendar")
        row.tap()

        let start = app.buttons["Start workout"]
        XCTAssertTrue(
            start.waitForExistence(timeout: 6),
            "Workout detail sheet has no start action"
        )
        start.tap()

        XCTAssertTrue(
            app.staticTexts["PREFLIGHT"].waitForExistence(timeout: 8),
            "Starting from the plan did not open preflight"
        )
    }
}
