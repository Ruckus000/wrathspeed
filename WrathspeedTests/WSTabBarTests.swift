import SwiftUI
import XCTest
@testable import Wrathspeed

final class WSTabBarTests: XCTestCase {
    // Inactive tabs render no visible text, so the label is the only thing carrying the tab's
    // name to VoiceOver and to the UI suites that navigate by tab name.
    func testEveryTabHasALabelAndASymbol() {
        for tab in AppTab.allCases {
            XCTAssertFalse(tab.label.isEmpty, "\(tab) has no label")
            XCTAssertFalse(tab.symbol.isEmpty, "\(tab) has no SF Symbol")
        }
    }

    func testSymbolsAreDistinct() {
        let symbols = AppTab.allCases.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count, "two tabs share a symbol")
    }

    // A ScrollView is greedy and reports the height it was proposed, not its content, so the
    // clearance cannot be measured through WSScreen directly. The real proof that the clearance
    // is actually enough is the end-of-scroll tap in FloatingTabBarUITests, which is the only
    // thing that really shows it.
    //
    // Pins the metrics themselves rather than the arithmetic between them: asserting that the
    // top edge equals clearance plus height only restates its definition. Changing either
    // number should be a deliberate act that updates this test.
    func testMetricsAreTheOnesTheLayoutWasBuiltAround() {
        XCTAssertEqual(WSTabBar.height, 56)
        XCTAssertEqual(WSTabBar.bottomClearance, 14)
        XCTAssertEqual(WSTabBar.topEdgeFromScreenBottom, 70)
    }

    /// The bar measures its clearance from the screen edge, so how far it reaches into the
    /// content area is a function of the device. A constant here would be wrong on one of the
    /// two phone shapes the app supports.
    func testContentInsetGivesBackWhateverTheSafeAreaAlreadyCovers() {
        // Home indicator: 34pt of the bar's 70pt reach is already outside the content area.
        XCTAssertEqual(WSTabBar.contentInset(safeAreaBottom: 34), 36)
        // Home button: none of it is, so the content has to clear the whole thing.
        XCTAssertEqual(WSTabBar.contentInset(safeAreaBottom: 0), 70)
    }

    /// A safe area deeper than the bar's reach must not produce negative padding, which would
    /// pull the last row of a scroll view *down* behind the bar instead of lifting it clear.
    func testContentInsetNeverGoesNegative() {
        XCTAssertEqual(WSTabBar.contentInset(safeAreaBottom: 200), 0)
    }

    func testTabHeightClearsTheFortyFourPointFloor() {
        XCTAssertGreaterThanOrEqual(WSTabBar.height, 44)
    }
}
