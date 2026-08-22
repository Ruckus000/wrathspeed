import XCTest

@MainActor
final class MarkAccessibilityUITests: XCTestCase {
    // The mark on the first onboarding screen is decorative -- the headline already says
    // what the screen is. Stacking `.accessibilityHidden` with a label silently rebuilds
    // the element, so this asserts the outcome rather than the modifier.
    func testDecorativeMarkStaysOutOfTheAccessibilityTree() {
        let app = XCUIApplication()
        UITestOnboardingHelper.configureFreshLaunch(app)
        app.launch()
        XCTAssertTrue(app.buttons["NEXT →"].waitForExistence(timeout: 20))

        let unlabelled = (0 ..< app.images.count)
            .map { app.images.element(boundBy: $0) }
            .filter { $0.label.isEmpty }
        XCTAssertTrue(
            unlabelled.isEmpty,
            "onboarding exposes \(unlabelled.count) unlabelled image(s) to VoiceOver"
        )
    }
}
