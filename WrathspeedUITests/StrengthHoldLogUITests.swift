import XCTest

/// A hold is not counted in reps, and the strength player has to say so twice: on the rest
/// screen, which must not offer a rep stepper, and in what it saves, which must not record a
/// number. Both were wrong -- a 30-second side plank asked how many reps you had done, recorded
/// the planner's placeholder 8, and history read it back as "8 REPS" under SIDE PLANK.
///
/// Every absence assertion here is paired with the same assertion in the positive direction
/// earlier in the same run. Absence is the easiest thing in a UI test to prove by accident: a
/// mistyped query, a screen that never rendered, or a set that was never completed all produce
/// "not found" just as convincingly as the fix does.
@MainActor
final class StrengthHoldLogUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAHoldNeitherAsksForRepsNorRecordsThem() {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedTodayStrength: true, seedCompletedOnboarding: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        app.buttons["TODAY"].tap()

        let strengthRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'strength-row-'")
        ).firstMatch
        XCTAssertTrue(
            strengthRow.waitForExistence(timeout: 10),
            "Today offered no strength session. The seed moves the next session that contains a "
                + "hold onto today, so either seeding failed or no generated session carries one."
        )
        strengthRow.tap()

        // MARK: The rep movement, which proves the query works

        let setDone = app.buttons["strength_set_done"]
        XCTAssertTrue(
            setDone.waitForExistence(timeout: 10),
            "Strength player did not open on a rep movement"
        )
        setDone.tap()

        let skipRest = app.buttons["strength_skip_rest"]
        XCTAssertTrue(skipRest.waitForExistence(timeout: 10), "Rest screen did not appear after a rep set")
        XCTAssertTrue(
            app.staticTexts["REPS"].exists,
            "The rest screen offered no rep count after a rep set. Everything below asserts this "
                + "same element is absent for a hold, so if it is missing here that assertion "
                + "proves nothing."
        )
        skipRest.tap()

        // MARK: Walk to the hold

        let holdToggle = app.buttons["strength_hold_toggle"]
        let next = app.buttons["Next"]
        // Bounded by the sets a session can hold, and by what the card *is* rather than a fixed
        // number of taps: a hard-coded index that quietly landed on the wrong movement would
        // make the absence assertion below pass for the wrong reason.
        var advances = 0
        while !holdToggle.exists && advances < 20 {
            guard next.exists, next.isEnabled else { break }
            next.tap()
            advances += 1
        }
        XCTAssertTrue(
            holdToggle.waitForExistence(timeout: 5),
            "Never reached a hold after \(advances) advances — the seeded session should contain one"
        )

        // MARK: The hold, on screen

        let doneEarly = app.buttons["DONE EARLY"]
        XCTAssertTrue(doneEarly.waitForExistence(timeout: 5), "Hold card offered no way to finish the hold")
        doneEarly.tap()

        XCTAssertTrue(
            skipRest.waitForExistence(timeout: 10),
            "Rest screen did not appear after the hold — the check below would pass on any screen"
        )
        XCTAssertFalse(
            app.staticTexts["REPS"].exists,
            "The rest screen asked for a rep count after a hold"
        )
        skipRest.tap()

        // MARK: The hold, as saved

        let finish = app.buttons["Finish strength session"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "Finish control missing")
        finish.tap()

        let done = app.buttons["DONE"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Session summary did not appear")
        done.tap()

        app.buttons["HISTORY"].tap()
        // "STRENGTH filter", not "STRENGTH": HistoryView relabels the chip so VoiceOver says what
        // the control does rather than only what it is named.
        let strengthFilter = app.buttons["STRENGTH filter"]
        XCTAssertTrue(strengthFilter.waitForExistence(timeout: 10), "History did not offer a strength filter")
        strengthFilter.tap()

        let sessionRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'FULL BODY'")
        ).firstMatch
        XCTAssertTrue(sessionRow.waitForExistence(timeout: 10), "The finished session did not reach history")
        UITestOnboardingHelper.scrollIntoView(sessionRow, in: app)
        sessionRow.tap()

        // The detail lists every set, completed or not, and an untouched log also carries no rep
        // count -- so both of these match on "completed" specifically. Without that, a row for a
        // set nobody performed would satisfy the assertion.
        let squatRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Bodyweight squat, completed, 12 REPS")
        ).firstMatch
        XCTAssertTrue(
            squatRow.waitForExistence(timeout: 10),
            "History recorded no rep count for the completed rep set, so the assertion below "
                + "cannot distinguish a fixed hold from a broken query."
        )

        let plankRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Side plank, completed")
        ).firstMatch
        XCTAssertTrue(
            plankRow.exists,
            "No completed side plank row read exactly \"Side plank, completed\". A recorded rep "
                + "count would appear as a trailing \", N REPS\"."
        )
    }
}
