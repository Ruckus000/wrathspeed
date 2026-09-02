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

    func testUnavailableCoachRequiresTravelDatesAndNewChatResetsConversation() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)
        app.buttons["PLAN"].tap()
        app.buttons["Open AI coach"].tap()

        app.buttons["coach_quick_travel"].tap()
        XCTAssertTrue(app.staticTexts["Tell me the exact travel start and end dates first."].waitForExistence(timeout: 5))
        app.buttons["coach_new_chat"].tap()
        XCTAssertTrue(app.buttons["coach_quick_travel"].exists)

        app.buttons["coach_quick_treadmill"].tap()
        XCTAssertTrue(app.staticTexts["Which named workout should move indoors?"].waitForExistence(timeout: 5))
    }

    func testUnavailableCoachFasterPromptShowsPreviewAndKeepAsIsDismissesIt() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        UITestOnboardingHelper.completeOnboarding(app)
        app.buttons["PLAN"].tap()
        app.buttons["Open AI coach"].tap()

        app.buttons["coach_quick_faster"].tap()
        XCTAssertTrue(app.buttons["coach_keep_as_is"].waitForExistence(timeout: 12))
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
            NSPredicate(format: "label CONTAINS[c] %@", "next unstarted quality workout")
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

    func testUnavailableCoachCanApplyAProposalAndReturnToPlan() throws {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
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
}
