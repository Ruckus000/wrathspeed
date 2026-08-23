import SwiftUI
import UIKit
import XCTest
@testable import Wrathspeed

/// The contract that makes `WSRow` trustworthy enough to put under every label/value row in the
/// app: it stacks when the pair genuinely will not fit, and it does *not* stack when it will.
///
/// A note on how these are written, because the obvious version does not work. Measuring the row's
/// height and asserting "it got taller" cannot distinguish stacking from squeezing — squeezed text
/// wraps, and wrapping makes the row taller too. The first draft of this file passed against a
/// plain `HStack`, which is the bug it exists to catch.
///
/// So the probes below are `.fixedSize(horizontal: true, ...)`: text that refuses to compress. That
/// removes wrapping as a confound and leaves exactly one signal — a horizontal arrangement overflows
/// its column, a stacked one does not. `testTheseTestsCanFail` pins that reasoning in place.
@MainActor
final class WSRowTests: XCTestCase {
    private let column: CGFloat = 375 - 48

    private func measure<V: View>(_ view: V, width: CGFloat, size: DynamicTypeSize) -> CGSize {
        let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, size))
        return host.sizeThatFits(in: CGSize(width: width, height: 10_000))
    }

    /// Text that will not compress, so the only way a pair fits a narrow column is by stacking.
    private func probe(_ s: String) -> some View {
        Text(s).wsType(.label, weight: .heavy).fixedSize(horizontal: true, vertical: false)
    }

    private func row(_ lead: String, _ trail: String) -> some View {
        WSRow { self.probe(lead) } trailing: { self.probe(trail) }
    }

    private func plainRow(_ lead: String, _ trail: String) -> some View {
        HStack(spacing: 0) { probe(lead); Spacer(minLength: 12); probe(trail) }
    }

    // MARK: - It stacks when it must

    /// Today's header, where the date and the STREAK pill shared a line and broke "STREAK" into
    /// "STREA" / "K". Stacked, the row fits its column; horizontal, it cannot.
    func testLongPairStacksOnTheNarrowestPhoneAtLargestText() {
        let measured = measure(row("SUN, AUG 23", "STREAK 0"), width: column, size: .accessibility5)
        XCTAssertLessThanOrEqual(measured.width, column + 0.5,
                                 "the row is \(measured.width)pt wide in a \(column)pt column — it did not stack")
    }

    /// The same thing stated as height, now that wrapping cannot confound it: stacked means two
    /// lines of non-compressible text.
    func testStackedRowIsTwoLinesTall() {
        let single = measure(probe("STREAK 0"), width: 10_000, size: .accessibility5).height
        let measured = measure(row("SUN, AUG 23", "STREAK 0"), width: column, size: .accessibility5)
        XCTAssertGreaterThan(measured.height, single * 1.8, "the row is still on one line")
    }

    // MARK: - It does not stack when it need not

    /// The half that proves the trigger measures rather than reacting to the text size. A threshold
    /// on `isAccessibilitySize` would stack this too, spending a line for nothing.
    func testShortPairKeepsOneLineEvenAtLargestText() {
        let single = measure(probe("MON"), width: 10_000, size: .accessibility5).height
        let measured = measure(row("MON", "3"), width: column, size: .accessibility5)
        XCTAssertLessThan(measured.height, single * 1.8,
                          "a pair this short should still fit on one line")
    }

    /// The same long pair on a wide screen at the default size has room, so it must stay inline.
    func testLongPairKeepsOneLineWhenThereIsRoom() {
        let single = measure(probe("STREAK 0"), width: 10_000, size: .large).height
        let measured = measure(row("SUN, AUG 23", "STREAK 0"), width: 440 - 48, size: .large)
        XCTAssertLessThan(measured.height, single * 1.8,
                          "the row stacked despite having room — the horizontal candidate is mismeasured")
    }

    // MARK: - The tests can fail

    /// Guards the reasoning above. A plain `HStack` — what every unmigrated row in the app still is
    /// — must fail the two assertions that matter, or they are not testing anything. Without this,
    /// a future refactor could quietly turn `WSRow` back into an `HStack` and the suite would stay
    /// green, which is exactly what happened to the first draft of this file.
    func testTheseTestsCanFail() {
        let plain = measure(plainRow("SUN, AUG 23", "STREAK 0"), width: column, size: .accessibility5)
        XCTAssertGreaterThan(plain.width, column + 0.5,
                             "a plain HStack fits the column, so the width assertion proves nothing")

        let single = measure(probe("STREAK 0"), width: 10_000, size: .accessibility5).height
        XCTAssertLessThan(plain.height, single * 1.8,
                          "a plain HStack is already two lines tall, so the height assertion proves nothing")
    }

    // MARK: - The property that actually prevents mid-word breaks

    /// A word breaks only when its container is narrower than the word. Stacked, each side gets the
    /// whole column — so this checks the column is wide enough for the longest word the app puts in
    /// one of these rows, at every size.
    func testColumnFitsTheLongestWordAtEverySize() {
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3, .accessibility5] {
            for word in ["STREAK", "MARATHON", "INTERMEDIATE", "KILOMETERS"] {
                let needed = measure(Text(word).wsType(.label, weight: .heavy), width: 10_000, size: size).width
                XCTAssertLessThanOrEqual(needed, column,
                                         "'\(word)' needs \(needed)pt at \(size), column is \(column)pt")
            }
        }
    }
}
