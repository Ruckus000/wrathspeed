import XCTest

@MainActor
final class PreflightLiveStartUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPreflightOutdoorAndTreadmillReachLiveRun() throws {
        let app = XCUIApplication()
        // seedTodayRun: the plan schedules runs on particular weekdays, so on a rest day
        // Today offers nothing to start and this test had no run to preflight.
        UITestOnboardingHelper.configureFreshLaunch(
            app,
            simulateLiveRecording: true,
            seedTodayRun: true
        )
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        let startRun = app.buttons["Start today's run"]
        XCTAssertTrue(startRun.waitForExistence(timeout: 8), "Today's run action missing")
        startRun.tap()

        XCTAssertTrue(app.staticTexts["PREFLIGHT"].waitForExistence(timeout: 5), "Preflight sheet missing")

        let outdoor = app.buttons["Outdoor"]
        XCTAssertTrue(outdoor.waitForExistence(timeout: 3))
        outdoor.tap()

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'GPS ROUTE'")).firstMatch.waitForExistence(timeout: 3),
            "Outdoor GPS readiness row missing"
        )

        beginLiveWorkoutFromPreflight(in: app)
        try assertLiveRunOutdoorControls(in: app)
        endLiveWorkout(in: app)

        app.buttons["+ INSTANT RUN"].tap()
        XCTAssertTrue(app.staticTexts["INSTANT RUN"].waitForExistence(timeout: 5))

        let treadmill = app.buttons["Treadmill"]
        XCTAssertTrue(treadmill.waitForExistence(timeout: 3))
        treadmill.tap()

        let continueButton = app.buttons["CONTINUE →"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        XCTAssertTrue(app.staticTexts["PREFLIGHT"].waitForExistence(timeout: 5), "Instant preflight missing")
        XCTAssertTrue(app.buttons["Treadmill"].waitForExistence(timeout: 3))

        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'TREADMILL SPEED'")).firstMatch
                .waitForExistence(timeout: 3),
            "Treadmill speed context missing on preflight"
        )

        beginLiveWorkoutFromPreflight(in: app)
        try assertLiveRunTreadmillControls(in: app)
        confirmTreadmillEndAndAssertHistory(in: app)
    }

    private func beginLiveWorkoutFromPreflight(in app: XCUIApplication) {
        tapStartWorkout(in: app)
        handleWatchLaunchTimeoutIfNeeded(in: app)
    }

    private func tapStartWorkout(in app: XCUIApplication) {
        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
    }

    private func handleWatchLaunchTimeoutIfNeeded(in app: XCUIApplication) {
        let startOnPhone = app.buttons["START ON PHONE"]
        if startOnPhone.waitForExistence(timeout: 14) {
            startOnPhone.tap()
        }
    }

    private func assertLiveRunOutdoorControls(in app: XCUIApplication) throws {
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 12), "Live run pause control missing after outdoor start")

        let lap = app.buttons["LAP"]
        XCTAssertTrue(lap.waitForExistence(timeout: 3), "Outdoor live run should expose LAP")

        let recordingStatus = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'recording'")
        ).firstMatch
        XCTAssertTrue(recordingStatus.waitForExistence(timeout: 5), "Recording status missing")
    }

    private func assertLiveRunTreadmillControls(in app: XCUIApplication) throws {
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 12), "Live run pause control missing after treadmill start")

        let next = app.buttons["NEXT"]
        XCTAssertTrue(next.waitForExistence(timeout: 3), "Treadmill live run should expose NEXT step control")

        let recordingStatus = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'recording'")
        ).firstMatch
        XCTAssertTrue(recordingStatus.waitForExistence(timeout: 5), "Recording status missing")
    }

    private func endLiveWorkout(in app: XCUIApplication) {
        confirmEndLiveWorkout(in: app)
        dismissCelebrationIfNeeded(in: app)
        XCTAssertTrue(app.buttons["TODAY"].waitForExistence(timeout: 10))
    }

    private func confirmTreadmillEndAndAssertHistory(in app: XCUIApplication) {
        confirmEndLiveWorkout(in: app)

        let saveActual = app.buttons["Save workout with actual treadmill distance"]
        XCTAssertTrue(
            saveActual.waitForExistence(timeout: 12),
            "Treadmill actual-distance confirmation missing after END"
        )
        let increaseActual = app.buttons["Increase"]
        XCTAssertTrue(increaseActual.waitForExistence(timeout: 3), "Actual-distance stepper missing")
        increaseActual.tap()
        increaseActual.tap()
        saveActual.tap()

        dismissCelebrationIfNeeded(in: app)

        let history = app.buttons["HISTORY"]
        XCTAssertTrue(history.waitForExistence(timeout: 10), "History tab missing after treadmill save")
        history.tap()

        XCTAssertTrue(app.staticTexts["HISTORY"].waitForExistence(timeout: 5))
        let emptyRuns = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'NO RUNS YET'")
        ).firstMatch
        XCTAssertFalse(emptyRuns.exists, "History still empty after treadmill save")

        let treadmillEvidence = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'TREADMILL'")
        ).firstMatch
        XCTAssertTrue(
            treadmillEvidence.waitForExistence(timeout: 5),
            "Saved treadmill run missing TREADMILL location evidence in History"
        )
    }

    private func confirmEndLiveWorkout(in app: XCUIApplication) {
        let endMatches = app.buttons.matching(NSPredicate(format: "label == 'End workout'"))
        XCTAssertGreaterThan(endMatches.count, 0)
        endMatches.element(boundBy: 0).tap()

        let confirmIndex = min(1, endMatches.count - 1)
        if endMatches.element(boundBy: confirmIndex).waitForExistence(timeout: 3) {
            endMatches.element(boundBy: confirmIndex).tap()
        }
    }

    private func dismissCelebrationIfNeeded(in app: XCUIApplication) {
        let backToToday = app.buttons["BACK TO TODAY"]
        if backToToday.waitForExistence(timeout: 8) {
            backToToday.tap()
        }
    }
}
