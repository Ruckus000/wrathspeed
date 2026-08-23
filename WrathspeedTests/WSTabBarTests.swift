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
    // clearance cannot be measured through WSScreen directly. This pins the arithmetic; the
    // proof that the clearance is actually enough is the end-of-scroll tap in
    // FloatingTabBarUITests, which is the only thing that really shows it.
    func testFootprintIsTheCapsulePlusItsGap() {
        XCTAssertEqual(WSTabBar.footprint, WSTabBar.height + WSTabBar.gap, accuracy: 0.001)
        XCTAssertGreaterThan(WSTabBar.footprint, 0)
    }

    func testTabHeightClearsTheFortyFourPointFloor() {
        XCTAssertGreaterThanOrEqual(WSTabBar.height, 44)
    }
}
