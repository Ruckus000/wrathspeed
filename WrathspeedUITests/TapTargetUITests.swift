import XCTest

/// Rows built as `HStack { label; Spacer(); value }` look tappable across their whole
/// width. Whether they are depends on what wraps them, and the line is not obvious:
///
/// - `Button` + `.buttonStyle(.plain)` -- **not** hit-testable across the Spacer, even
///   with a background shape behind it. Needs an explicit `.contentShape`.
/// - `NavigationLink` -- hit-testable across the whole row already.
///
/// Each test here taps the centre of a row, which is the part a Spacer occupies.
@MainActor
final class TapTargetUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Apple's minimum is 44x44pt. These three were measurably below it and each caused a
    /// real failure: the plan sheet's close glyph at 9x13, and the mobility and week-nav
    /// buttons at ~13pt tall, which made them intermittently impossible to tap under a
    /// full-suite run.
    func testKeyControlsMeetTheMinimumHitTargetHeight() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        app.buttons["TODAY"].tap()
        let mobility = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'mobility-row-'")
        ).firstMatch
        scrollTo(mobility, in: app)
        XCTAssertTrue(mobility.waitForExistence(timeout: 6), "No mobility row on Today")
        XCTAssertGreaterThanOrEqual(
            mobility.frame.height, 44,
            "Mobility row action is \(mobility.frame.height)pt tall"
        )

        app.buttons["PLAN"].tap()
        app.buttons["plan_weekly_calendar"].tap()
        let next = app.buttons["weekly_calendar_next_week"]
        XCTAssertTrue(next.waitForExistence(timeout: 8), "Weekly calendar did not open")
        XCTAssertGreaterThanOrEqual(
            next.frame.height, 44,
            "Next week button is \(next.frame.height)pt tall"
        )

        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'weekly_calendar_workout_'")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6), "No workout in the weekly calendar")
        row.tap()
        let close = app.buttons["workout_sheet_close"]
        XCTAssertTrue(close.waitForExistence(timeout: 6), "Workout sheet close button missing")
        // XCUITest reports a presented sheet's contents at about 0.984 scale -- the 56pt
        // primary button below measures 55.1 -- so an absolute 44 would fail on a control
        // that is genuinely 44pt. Compare against that button instead, which makes the
        // check scale-invariant.
        let primary = app.buttons["Start workout"]
        XCTAssertTrue(primary.waitForExistence(timeout: 4), "Sheet has no START button to calibrate against")
        let declaredPrimaryHeight = 56.0
        XCTAssertGreaterThanOrEqual(
            close.frame.height / primary.frame.height,
            44.0 / declaredPrimaryHeight,
            "Workout sheet close button is \(close.frame.height)pt against a \(primary.frame.height)pt START button, i.e. under 44pt"
        )
        XCTAssertGreaterThanOrEqual(close.frame.width / primary.frame.height, 44.0 / declaredPrimaryHeight)
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 8) {
        var tries = 0
        while !element.exists && tries < attempts {
            app.swipeUp()
            tries += 1
        }
        if element.exists, !element.isHittable { app.swipeUp() }
    }

    /// Settings → Coaching → AUDIO CUES. The value sits hard right, the label hard left,
    /// so the centre of the row is Spacer.
    func testAudioCuesRowTogglesWhenTappedInItsCentre() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        app.buttons["SETTINGS"].tap()

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'AUDIO CUES'")
        ).firstMatch
        scrollTo(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 6), "AUDIO CUES row not found in Settings")

        let before = row.label
        row.tap()

        // The row's label carries its own state ("AUDIO CUES, ON" / "... OFF"), so a real
        // toggle shows up as a label change without needing a separate probe.
        let changed = NSPredicate(format: "label != %@", before)
        let expectation = XCTNSPredicateExpectation(predicate: changed, object: row)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(
            result, .completed,
            "Tapping the centre of the AUDIO CUES row did nothing. Label stayed '\(before)'."
        )
    }

    /// Settings → Running profile → VDOT · PACE ZONES. Same shape again: label left,
    /// value right, nothing in between.
    func testPaceZonesRowOpensWhenTappedInItsCentre() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        app.buttons["SETTINGS"].tap()

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'PACE ZONES'")
        ).firstMatch
        scrollTo(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 6), "Pace zones row not found in Settings")
        row.tap()

        XCTAssertTrue(
            app.buttons["← SETTINGS"].waitForExistence(timeout: 6),
            "Tapping the centre of the pace zones row did not open it"
        )
    }

    /// Today → Not feeling 100% → MODE. WSSelectRow has a background shape, which looked
    /// like it should be hit-testable on its own -- it is not, and this test is what
    /// established that.
    func testSelectRowSelectsWhenTappedInItsCentre() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        app.buttons["TODAY"].tap()
        let n100 = app.buttons["NOT FEELING 100%?"]
        scrollTo(n100, in: app)
        XCTAssertTrue(n100.waitForExistence(timeout: 6), "Not feeling 100% entry missing")
        n100.tap()

        let row = app.buttons["Short easy runs"]
        XCTAssertTrue(row.waitForExistence(timeout: 6), "Mode row missing")
        XCTAssertFalse(row.isSelected, "Short easy runs is already the selected mode")

        row.tap()

        let selected = NSPredicate(format: "isSelected == true")
        let expectation = XCTNSPredicateExpectation(predicate: selected, object: row)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
            "Tapping the centre of a WSSelectRow did not select it"
        )
    }
}
