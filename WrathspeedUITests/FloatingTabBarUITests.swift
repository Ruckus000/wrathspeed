import XCTest

@MainActor
final class FloatingTabBarUITests: XCTestCase {
    // The bar floats over content now, so the risk is that a scroll view's last row ends up
    // underneath it and cannot be tapped. Scrolling to the end and hit-testing the last row is
    // the only thing that actually proves the clearance is right.
    func testLastRowOfEachTabClearsTheBar() {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        XCTAssertTrue(app.buttons["SETTINGS"].waitForExistence(timeout: 20))
        UITestOnboardingHelper.completeOnboarding(app)

        for tab in ["TODAY", "PLAN", "HISTORY", "SETTINGS"] {
            app.buttons[tab].tap()
            let scroll = app.scrollViews.firstMatch
            guard scroll.waitForExistence(timeout: 5) else { continue }
            for _ in 0 ..< 12 { scroll.swipeUp(velocity: .fast) }

            let bar = app.buttons["SETTINGS"].frame
            let candidates = (0 ..< app.buttons.count)
                .map { app.buttons.element(boundBy: $0) }
                .filter { $0.exists && $0.frame.height > 0 && $0.frame.minY < bar.minY }
            guard let lowest = candidates.max(by: { $0.frame.maxY < $1.frame.maxY }) else { continue }
            XCTAssertTrue(lowest.isHittable,
                          "\(tab): '\(lowest.label)' is under the floating bar and cannot be tapped")
        }
    }

    // The unit matrix can only measure the whole bar, so the per-tab hit region is asserted
    // here, where the frames are the real ones the system hit-tests against. An earlier draft
    // sized the tab content to a fixed 44pt inside a 56pt bar, which left a dead strip that
    // looked tappable and was not -- nothing in the unit tests could see it.
    func testEveryTabPresentsA44PointTarget() {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        XCTAssertTrue(app.buttons["TODAY"].waitForExistence(timeout: 20))
        UITestOnboardingHelper.completeOnboarding(app)

        for tab in ["TODAY", "PLAN", "HISTORY", "SETTINGS"] {
            let frame = app.buttons[tab].frame
            XCTAssertGreaterThanOrEqual(frame.height, 44, "\(tab) is only \(frame.height)pt tall")
            XCTAssertGreaterThanOrEqual(frame.width, 44, "\(tab) is only \(frame.width)pt wide")
        }
    }

    func testEveryTabIsReachableByName() {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app, seedCompletedOnboarding: true)
        app.launch()
        XCTAssertTrue(app.buttons["TODAY"].waitForExistence(timeout: 20))
        UITestOnboardingHelper.completeOnboarding(app)

        // Only the selected tab draws its label, so this fails the moment the inactive tabs
        // stop declaring their accessibility names.
        for tab in ["PLAN", "HISTORY", "SETTINGS", "TODAY"] {
            let button = app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(tab) is not reachable by name")
            XCTAssertTrue(button.isHittable, "\(tab) is not hittable")
            button.tap()
        }
    }
}
