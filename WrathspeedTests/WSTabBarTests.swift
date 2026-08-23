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
    // Pins the metrics themselves rather than the arithmetic between them: asserting that
    // footprint equals height + gap only restates footprint's definition. Changing either
    // number should be a deliberate act that updates this test.
    func testMetricsAreTheOnesTheLayoutWasBuiltAround() {
        XCTAssertEqual(WSTabBar.height, 56)
        XCTAssertEqual(WSTabBar.gap, 8)
        XCTAssertEqual(WSTabBar.footprint, 64)
    }

    func testTabHeightClearsTheFortyFourPointFloor() {
        XCTAssertGreaterThanOrEqual(WSTabBar.height, 44)
    }
}
