import XCTest

@MainActor
final class CoachUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCoachOpensFallbackAndQuickPromptsAreReachable() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)

        app.buttons["PLAN"].tap()
        XCTAssertTrue(app.buttons["Open AI coach"].waitForExistence(timeout: 8))
        app.buttons["Open AI coach"].tap()

        XCTAssertTrue(app.staticTexts["COACH"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["coach_quick_soreness"].isHittable)
        XCTAssertTrue(app.buttons["coach_quick_travel"].isHittable)
        XCTAssertTrue(app.buttons["coach_quick_treadmill"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["coach_new_chat"].frame.height, 44)
    }

    /// The three parameterised quick actions each open a picker and compile the intent without
    /// the model, so they work on every device. Before, two of them sent a sentence to a model
    /// that is unavailable here and dead-ended on "which named workout?".
    func testQuickPickersProduceProposalsWithoutTheModel() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)
        app.buttons["PLAN"].tap()
        app.buttons["Open AI coach"].tap()

        // Treadmill: the first upcoming outdoor run, straight to an applicable card.
        app.buttons["coach_quick_treadmill"].tap()
        let firstRun = app.buttons["coach_pick_workout_0"]
        XCTAssertTrue(firstRun.waitForExistence(timeout: 6), "the treadmill picker lists the coming runs")
        XCTAssertGreaterThanOrEqual(firstRun.frame.height, 44)
        firstRun.tap()
        XCTAssertTrue(app.buttons["coach_apply"].waitForExistence(timeout: 8), "moving a run indoors is applicable")
        app.buttons["coach_new_chat"].tap()

        // Long run: a weekday from the runner's own available days.
        app.buttons["coach_quick_long_run"].tap()
        let weekday = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'coach_pick_weekday_'")).firstMatch
        XCTAssertTrue(weekday.waitForExistence(timeout: 6), "the weekday picker lists the other run days")
        weekday.tap()
        XCTAssertTrue(app.otherElements["coach_proposal_card"].waitForExistence(timeout: 12), "moving the long run produces a card")
        app.buttons["coach_new_chat"].tap()

        // Travel: two days from tomorrow, picked, previewed.
        app.buttons["coach_quick_travel"].tap()
        let confirm = app.buttons["coach_pick_travel_confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 6))
        confirm.tap()
        XCTAssertTrue(app.otherElements["coach_proposal_card"].waitForExistence(timeout: 12), "picked travel dates produce a card")
    }

    func testUnavailableCoachFasterPromptShowsPreviewAndKeepAsIsDismissesIt() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)
        app.buttons["PLAN"].tap()
        app.buttons["Open AI coach"].tap()

        // A fresh plan has no completed runs, so FASTER PACES has no evidence: a blocked card
        // that says what would unlock it, dismissable like any other.
        app.buttons["coach_quick_faster"].tap()
        XCTAssertTrue(app.buttons["coach_keep_as_is"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["coach_apply"].exists, "no evidence, no applicable proposal")
        let reason = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "three completed runs")).firstMatch
        XCTAssertTrue(reason.waitForExistence(timeout: 4), "the card says what would unlock faster paces")
        XCTAssertGreaterThanOrEqual(app.buttons["coach_quick_faster"].frame.height, 44)
        app.buttons["coach_keep_as_is"].tap()
        XCTAssertFalse(app.buttons["coach_keep_as_is"].exists)
    }

    func testSorenessQuickPromptShowsConcreteAdjustmentInsteadOfGenericReply() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)
        app.buttons["PLAN"].tap()
        app.buttons["Open AI coach"].tap()

        app.buttons["coach_quick_soreness"].tap()

        let concreteReply = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "80% of its distance")
        ).firstMatch
        XCTAssertTrue(concreteReply.waitForExistence(timeout: 8))
        // KEEP AS IS renders on blocked proposals too, so it proves only that a card appeared.
        // The thing this button exists to do is produce something the runner can apply.
        let apply = app.buttons["coach_apply"]
        let applyWithWarning = app.buttons["coach_apply_with_warning"]
        XCTAssertTrue(
            apply.waitForExistence(timeout: 8) || applyWithWarning.waitForExistence(timeout: 2),
            "I'M SORE produced a blocked card instead of an applicable proposal"
        )
    }

    /// With three recent runs faster than target, FASTER PACES previews and applies.
    func testUnavailableCoachCanApplyAProposalAndReturnToPlan() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedFastResults: true, seedCompletedOnboarding: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)
        app.buttons["PLAN"].tap()
        app.buttons["Open AI coach"].tap()

        app.buttons["coach_quick_faster"].tap()
        let apply = app.buttons["coach_apply"]
        let applyWithWarning = app.buttons["coach_apply_with_warning"]
        XCTAssertTrue(apply.waitForExistence(timeout: 6) || applyWithWarning.waitForExistence(timeout: 6))
        if apply.exists {
            apply.tap()
        } else {
            applyWithWarning.tap()
        }
        XCTAssertTrue(app.buttons["Open AI coach"].waitForExistence(timeout: 8))
    }

    /// The coach is where a runner types about pain, and `answerOnly` shows the model's own
    /// words. It had no health statement at all; the one added to Settings must be one tap away.
    func testCoachScreenCarriesTheHealthStatement() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)
        app.buttons["PLAN"].tap()
        app.buttons["Open AI coach"].tap()

        let link = app.buttons["coach_health_safety"]
        XCTAssertTrue(link.waitForExistence(timeout: 8), "the coach screen must carry the health statement")
        XCTAssertGreaterThanOrEqual(link.frame.height, 44)
        link.tap()
        XCTAssertTrue(app.staticTexts["HEALTH\nAND SAFETY"].waitForExistence(timeout: 6))
        app.buttons["Back to coach"].tap()
        XCTAssertTrue(link.waitForExistence(timeout: 6), "dismissing the sheet returns to the coach")
    }
}
