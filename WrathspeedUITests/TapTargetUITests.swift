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

    /// Apple's minimum of 44pt, less a hundredth of a point of floating-point slack.
    /// SwiftUI lays a control declared at 44pt out as 43.99999999999997 and XCUITest
    /// reports that verbatim, so a bare `>= 44` fails on a control that is exactly right.
    /// The slack is three orders of magnitude below anything a finger could tell apart.
    private let minimumHitTarget = 44.0 - 0.01

    /// Apple's minimum is 44x44pt. These three were measurably below it and each caused a
    /// real failure: the plan sheet's close glyph at 9x13, and the mobility and week-nav
    /// buttons at ~13pt tall, which made them intermittently impossible to tap under a
    /// full-suite run.
    func testKeyControlsMeetTheMinimumHitTargetHeight() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        app.buttons["TODAY"].tap()
        let mobility = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'mobility-row-'")
        ).firstMatch
        scrollTo(mobility, in: app)
        XCTAssertTrue(mobility.waitForExistence(timeout: 6), "No mobility row on Today")
        XCTAssertGreaterThanOrEqual(
            mobility.frame.height, minimumHitTarget,
            "Mobility row action is \(mobility.frame.height)pt tall"
        )

        // A library row: flush against its neighbours, so under 44pt an edge tap opens the
        // wrong movement.
        app.buttons["SETTINGS"].tap()
        let libraryEntry = app.buttons["settings.movementLibrary"]
        scrollTo(libraryEntry, in: app)
        XCTAssertTrue(libraryEntry.waitForExistence(timeout: 6), "Movement library entry missing")
        libraryEntry.tap()
        let libraryRow = app.buttons["movement_row_dead-bug"]
        XCTAssertTrue(libraryRow.waitForExistence(timeout: 8), "Dead bug row missing")
        scrollTo(libraryRow, in: app)
        XCTAssertGreaterThanOrEqual(
            libraryRow.frame.height, minimumHitTarget,
            "Movement library row is \(libraryRow.frame.height)pt tall"
        )

        // The two plan-header links. This test tapped WEEKLY CALENDAR without ever
        // measuring it, and it was 13.3pt -- the same frame-outside-the-label defect as
        // the mobility row, on the control every plan-tab test has to get through first.
        app.buttons["PLAN"].tap()
        let weeklyCalendar = app.buttons["plan_weekly_calendar"]
        XCTAssertTrue(weeklyCalendar.waitForExistence(timeout: 8), "Plan tab did not appear")
        XCTAssertGreaterThanOrEqual(
            weeklyCalendar.frame.height, minimumHitTarget,
            "Weekly calendar link is \(weeklyCalendar.frame.height)pt tall"
        )
        let managePlan = app.buttons["plan_manage_plan"]
        XCTAssertTrue(managePlan.waitForExistence(timeout: 6), "Manage plan link missing")
        XCTAssertGreaterThanOrEqual(
            managePlan.frame.height, minimumHitTarget,
            "Manage plan link is \(managePlan.frame.height)pt tall"
        )

        weeklyCalendar.tap()
        let next = app.buttons["weekly_calendar_next_week"]
        XCTAssertTrue(next.waitForExistence(timeout: 8), "Weekly calendar did not open")
        XCTAssertGreaterThanOrEqual(
            next.frame.height, minimumHitTarget,
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
        // Converting back into declared points rather than comparing raw ratios: the ratio
        // form failed on iPhone Air by 5e-8, on a control that measures exactly 44pt once
        // the scale is divided out.
        let declaredPrimaryHeight = 56.0
        let sheetScale = primary.frame.height / declaredPrimaryHeight
        XCTAssertGreaterThanOrEqual(
            close.frame.height / sheetScale,
            minimumHitTarget,
            "Workout sheet close button is \(close.frame.height)pt against a \(primary.frame.height)pt START button, i.e. under 44pt"
        )
        XCTAssertGreaterThanOrEqual(close.frame.width / sheetScale, minimumHitTarget)
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        UITestOnboardingHelper.scrollIntoView(element, in: app)
    }

    /// Settings → Coaching → AUDIO CUES. The value sits hard right, the label hard left,
    /// so the centre of the row is Spacer.
    func testAudioCuesRowTogglesWhenTappedInItsCentre() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        app.buttons["SETTINGS"].tap()

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'AUDIO CUES'")
        ).firstMatch
        scrollTo(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 6), "AUDIO CUES row not found in Settings")

        // Matched on the state suffix rather than the whole label. The row carries a hint
        // line between its title and its value, and that hint changes with the state too, so
        // an exact-string assertion breaks on copy edits that have nothing to do with what
        // this test is about -- which is that the centre of the row is tappable.
        XCTAssertTrue(
            row.label.hasSuffix(", ON"),
            "Cues should start on after a store reset (label was '\(row.label)')"
        )
        row.tap()

        // The row's label carries its own state, so a real toggle shows up as a label change.
        // Deliberately a fresh query rather than a predicate wait on `row`: toggling rebuilds
        // the row's accessibility element, and a `firstMatch` reference held across the tap
        // goes stale mid-wait. That is how this failed on CI -- the waiter timed out hunting
        // the old element while the pill had visibly flipped to OFF.
        let toggledOff = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] 'AUDIO CUES' AND label ENDSWITH ', OFF'")
        ).firstMatch
        XCTAssertTrue(
            toggledOff.waitForExistence(timeout: 5),
            "Tapping the centre of the AUDIO CUES row did not toggle it off"
        )
    }

    /// Settings → Running profile → VDOT · PACE ZONES. Same shape again: label left,
    /// value right, nothing in between.
    func testPaceZonesRowOpensWhenTappedInItsCentre() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
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
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
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
