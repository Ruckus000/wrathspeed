import XCTest

/// Drives the two surfaces that exercise media appears on and attaches screenshots, so a
/// clip regression shows up as a picture and not just a passing assertion.
@MainActor
final class ExerciseMediaScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Settings → Movement library, then a movement that has a bundled clip.
    func testMovementLibraryShowsClips() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        app.buttons["SETTINGS"].tap()

        let library = app.buttons["settings.movementLibrary"]
        var attempts = 0
        while !library.exists && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(library.waitForExistence(timeout: 5), "Movement library entry missing from Settings")
        if !library.isHittable { app.swipeUp() }
        library.tap()

        XCTAssertTrue(
            app.navigationBars["Movements"].waitForExistence(timeout: 8),
            "Movement library did not open"
        )
        attach(app, named: "01-movement-library-list")

        // Dead bug is a strength movement with a bundled anatomical-render clip.
        let deadBug = app.buttons["Dead bug"].firstMatch
        attempts = 0
        while !deadBug.exists && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(deadBug.waitForExistence(timeout: 5), "Dead bug row missing from library")
        deadBug.tap()

        XCTAssertTrue(
            app.navigationBars["Dead bug"].waitForExistence(timeout: 8),
            "Movement detail did not open"
        )
        // Let the looping player get past its first frame so the shot proves playback.
        _ = app.otherElements["Demonstration loop"].waitForExistence(timeout: 5)
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        attach(app, named: "02-movement-detail-dead-bug-clip")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        attach(app, named: "03-movement-detail-dead-bug-clip-later-frame")
    }

    /// Plan → a workout → the prep and recovery block, then the weekly calendar to reach
    /// a quality session, which is the only kind that gets a Form drills routine.
    func testWorkoutDetailShowsPrepAndRecovery() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        app.buttons["PLAN"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        attach(app, named: "04-plan-tab")

        // An easy day: warm-up and cool-down, no drills.
        let easy = app.buttons["plan_workout_easy"].firstMatch
        XCTAssertTrue(easy.waitForExistence(timeout: 5), "No easy run in the current week")
        easy.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        attach(app, named: "05-prep-and-recovery-easy-run")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "easy-run-sheet-tree"
        tree.lifetime = .keepAlways
        add(tree)
        XCTAssertTrue(
            app.staticTexts["workout_prep_and_recovery"].waitForExistence(timeout: 6),
            "Prep and recovery block missing from an easy run"
        )
        XCTAssertTrue(
            app.buttons["workout_routine_warmup"].exists,
            "Easy run has no warm-up routine"
        )
        XCTAssertTrue(
            app.buttons["workout_routine_cooldown"].exists,
            "Easy run has no cool-down routine"
        )
        XCTAssertFalse(
            app.buttons["workout_routine_drills"].exists,
            "Drills should not appear on an easy day"
        )
        closeSheet(app)

        // The first week is a partial week and may hold no quality session, so walk the
        // weekly calendar forward until one turns up.
        app.buttons["plan_weekly_calendar"].tap()
        XCTAssertTrue(
            app.buttons["weekly_calendar_next_week"].waitForExistence(timeout: 8),
            "Weekly calendar did not open"
        )

        var foundDrills = false
        weekLoop: for _ in 0..<4 {
            let rows = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH 'weekly_calendar_workout_'")
            )
            for index in 0..<min(rows.count, 6) {
                let row = rows.element(boundBy: index)
                guard row.exists, row.isHittable else { continue }
                row.tap()
                _ = app.staticTexts["workout_prep_and_recovery"].waitForExistence(timeout: 4)

                if app.buttons["workout_routine_drills"].exists {
                    // Scroll the sheet so the whole prep block is in frame for the shot.
                    // A partially visible row still reports as hittable, so this drag is
                    // unconditional rather than guarded on isHittable.
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
                        .press(
                            forDuration: 0.05,
                            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                        )
                    RunLoop.current.run(until: Date().addingTimeInterval(1.0))
                    attach(app, named: "06-quality-day-form-drills")
                    app.buttons["workout_routine_drills"].tap()
                    RunLoop.current.run(until: Date().addingTimeInterval(2.5))
                    attach(app, named: "07-form-drills-routine-player")
                    foundDrills = true
                    break weekLoop
                }
                closeSheet(app)
            }
            app.buttons["weekly_calendar_next_week"].tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }

        XCTAssertTrue(foundDrills, "No quality day exposed a Form drills routine")
    }

    private func closeSheet(_ app: XCUIApplication) {
        let close = app.buttons["\u{2715}"].firstMatch
        if close.exists {
            close.tap()
        } else {
            app.swipeDown()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
    }
}
