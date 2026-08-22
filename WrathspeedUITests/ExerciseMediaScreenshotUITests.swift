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

    /// Bird dog is the one clip that is a flat illustration rather than a house-style
    /// render, so it gets its own shot to check it does not look out of place.
    func testBirdDogHasAClip() throws {
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
        XCTAssertTrue(library.waitForExistence(timeout: 5), "Movement library entry missing")
        if !library.isHittable { app.swipeUp() }
        library.tap()
        XCTAssertTrue(app.navigationBars["Movements"].waitForExistence(timeout: 8))

        let birdDog = app.buttons["Bird dog"].firstMatch
        attempts = 0
        while !birdDog.exists && attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(birdDog.waitForExistence(timeout: 5), "Bird dog row missing from library")
        birdDog.tap()
        XCTAssertTrue(app.navigationBars["Bird dog"].waitForExistence(timeout: 8))

        // The clip, not the symbol fallback: the media view exposes this only when a file
        // actually resolved.
        XCTAssertTrue(
            app.otherElements["Demonstration loop"].waitForExistence(timeout: 6),
            "Bird dog fell back to its SF Symbol instead of playing a clip"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        attach(app, named: "09-movement-detail-bird-dog-clip")
    }

    /// True when the open workout detail sheet is for a quality session. Read from the
    /// sheet's own meta line so the drills assertion is not circular.
    private func detailSheetIsQuality(_ app: XCUIApplication) -> Bool {
        app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS 'Q SESSION'"))
            .count > 0
    }

    /// Opens the detail sheet for the first workout in the weekly calendar whose quality
    /// flag matches `quality`, paging forward week by week. Drives everything from the
    /// calendar rather than the current week, because a plan starts mid-week and which
    /// kinds land in that partial week depends on the weekday the suite runs on.
    private func openWorkoutDetail(
        in app: XCUIApplication,
        quality: Bool,
        maxWeeks: Int = 6
    ) -> Bool {
        app.buttons["PLAN"].tap()
        guard app.buttons["plan_weekly_calendar"].waitForExistence(timeout: 8) else { return false }
        app.buttons["plan_weekly_calendar"].tap()
        guard app.buttons["weekly_calendar_next_week"].waitForExistence(timeout: 8) else { return false }

        for _ in 0..<maxWeeks {
            let rows = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH 'weekly_calendar_workout_'")
            )
            for index in 0..<min(rows.count, 7) {
                let row = rows.element(boundBy: index)
                guard row.exists, row.isHittable else { continue }
                row.tap()
                if app.staticTexts["workout_prep_and_recovery"].waitForExistence(timeout: 4),
                   detailSheetIsQuality(app) == quality {
                    return true
                }
                closeSheet(app)
            }
            app.buttons["weekly_calendar_next_week"].tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        return false
    }

    /// Brings the prep and recovery block fully into frame. A partially visible row still
    /// reports as hittable, so this drag is unconditional.
    private func scrollDetailSheet(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            )
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    }

    /// A non-quality day gets a warm-up and a cool-down, and no drills.
    func testEasyDayHasWarmupAndCooldownWithoutDrills() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)
        attach(app, named: "04-plan-tab")

        XCTAssertTrue(
            openWorkoutDetail(in: app, quality: false),
            "No non-quality workout found in the first weeks of the plan"
        )
        scrollDetailSheet(app)
        attach(app, named: "05-prep-and-recovery-easy-run")

        XCTAssertTrue(app.buttons["workout_routine_warmup"].exists, "No warm-up routine")
        XCTAssertTrue(app.buttons["workout_routine_cooldown"].exists, "No cool-down routine")
        XCTAssertFalse(
            app.buttons["workout_routine_drills"].exists,
            "Drills should not appear on a non-quality day"
        )
    }

    /// A quality day additionally gets the Form drills block, and it opens.
    func testQualityDayHasFormDrills() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        XCTAssertTrue(
            openWorkoutDetail(in: app, quality: true),
            "No quality workout found in the first weeks of the plan"
        )
        scrollDetailSheet(app)
        attach(app, named: "06-quality-day-form-drills")

        XCTAssertTrue(app.buttons["workout_routine_warmup"].exists, "No warm-up routine")
        XCTAssertTrue(app.buttons["workout_routine_cooldown"].exists, "No cool-down routine")
        let drills = app.buttons["workout_routine_drills"]
        XCTAssertTrue(drills.exists, "Quality day has no Form drills routine")

        drills.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        attach(app, named: "07-form-drills-routine-player")
    }

    /// The move-date sheet and the routine sheet both hang off the workout detail sheet.
    /// Routine presentation is covered by testQualityDayHasFormDrills; this pins the
    /// move-date sheet, which nothing else exercises.
    func testWorkoutDetailPresentsMoveDateSheet() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        XCTAssertTrue(
            openWorkoutDetail(in: app, quality: false),
            "No non-quality workout found in the first weeks of the plan"
        )

        let moveDate = app.buttons["workout_move_date"]
        XCTAssertTrue(moveDate.waitForExistence(timeout: 4), "Move date control missing")
        moveDate.tap()
        XCTAssertTrue(
            app.datePickers["move_workout_date_picker"].waitForExistence(timeout: 6),
            "Move date sheet did not present"
        )
    }

    /// The strength player also shows a demo loop. Reached from Today, which only offers a
    /// strength session on the days the plan scheduled one, so this seeds one rather than
    /// skipping and quietly losing the coverage on most days.
    func testStrengthPlayerShowsClip() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedTodayStrength: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        app.buttons["TODAY"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        let start = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'strength-row-'")
        ).firstMatch
        XCTAssertTrue(
            start.waitForExistence(timeout: 8),
            "Today offered no strength session even with one seeded"
        )
        start.tap()

        XCTAssertTrue(
            app.buttons["ABOUT THIS EXERCISE"].waitForExistence(timeout: 8),
            "Strength player did not open"
        )
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        attach(app, named: "08-strength-player-clip")
    }

    private func closeSheet(_ app: XCUIApplication) {
        // Matched by identifier, not by the ✕ glyph: the button carries an accessibility
        // label now, which replaces the glyph as its label. Leaving the sheet open makes
        // everything behind it unhittable, which is a confusing way for a later step to
        // fail.
        let close = app.buttons["workout_sheet_close"]
        if close.exists, close.isHittable {
            close.tap()
        } else {
            app.swipeDown()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        if close.exists {
            // Still up: the gesture did not take. Try the button once more.
            if close.isHittable { close.tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        }
    }
}
