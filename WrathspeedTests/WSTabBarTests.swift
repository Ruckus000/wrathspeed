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
}
