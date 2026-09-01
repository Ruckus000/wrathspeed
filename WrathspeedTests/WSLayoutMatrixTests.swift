import SwiftUI
import UIKit
import XCTest
@testable import Wrathspeed

/// Measures the shared components across every supported width and text size, and asserts the
/// things Apple's Larger Text criteria actually require: nothing spills out of the content
/// column, nothing truncates, and touch targets stay reachable.
///
/// The worst case — narrowest screen at the largest text — is the one that catches the most,
/// so it is in the matrix rather than assumed.
@MainActor
final class WSLayoutMatrixTests: XCTestCase {
    /// Portrait iPhone widths from the smallest device on iOS 26 to the largest.
    private let widths: [CGFloat] = [375, 390, 402, 440]
    private let textSizes: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility1, .accessibility3, .accessibility5]

    private func measure<V: View>(_ view: V, width: CGFloat, size: DynamicTypeSize) -> CGSize {
        let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, size))
        return host.sizeThatFits(in: CGSize(width: width, height: 10_000))
    }

    /// The gutters are fixed, so this is what a component actually gets to live in.
    private func content(_ width: CGFloat) -> CGFloat { width - WSSpace.gutter * 2 }

    // MARK: - Grouped list and segmented control

    /// The segmented track is the design's settings control, and its segments carry a fixed
    /// design height. A fixed height plus growing text is exactly the case that clips, so it
    /// is measured here rather than trusted.
    func testSegmentedControlStaysInsideItsCard() {
        // Two worst cases, and the second is the one that actually bit: three long options,
        // and seven short ones. Seven segments spent so much width on padding that every day
        // truncated to a single letter -- and a three-option test could never have seen it.
        let cases: [[String]] = [
            ["Minimal", "Standard", "Drill Sergeant"],
            ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"],
        ]
        for options in cases {
        for width in widths {
            for size in textSizes {
                let control = WSSegmentedControl(
                    options: options,
                    label: { $0 },
                    isSelected: { $0 == options[1] },
                    select: { _ in }
                )
                // A track lives inside a card row, which is inset from the card gutter.
                let available = width - WSSpace.cardGutter * 2 - 32
                let measured = measure(control, width: available, size: size)
                XCTAssertLessThanOrEqual(
                    measured.width, available + 0.5,
                    "segmented control spills at \(width)pt / \(size)"
                )
                XCTAssertGreaterThan(
                    measured.height, 0,
                    "segmented control collapsed at \(width)pt / \(size)"
                )
                // Each segment must keep enough width for its own label. Below this the text
                // truncates to an ellipsis, which is what "S…" and "M…" looked like.
                let perSegment = (available - CGFloat(options.count - 1) * 3 - 6) / CGFloat(options.count)
                XCTAssertGreaterThanOrEqual(
                    perSegment, 30,
                    "segments squeezed to \(perSegment)pt with \(options.count) options at \(width)pt / \(size)"
                )
            }
        }
        }
    }

    /// A list row puts a title and a value on opposite ends. `WSRow` should stack them rather
    /// than squeeze either, and the row must never fall under the 44pt touch minimum.
    func testListRowsKeepTheirTouchTargetAndDoNotSpill() {
        for width in widths {
            for size in textSizes {
                let row = WSListRow(title: "CONTENT LICENSES", hint: "WHERE THE BUNDLED MEDIA COMES FROM") {
                    Text("45.0 ›").wsType(.metric, weight: .bold)
                }
                let available = width - WSSpace.cardGutter * 2
                let measured = measure(row, width: available, size: size)
                XCTAssertLessThanOrEqual(
                    measured.width, available + 0.5,
                    "list row spills at \(width)pt / \(size)"
                )
                XCTAssertGreaterThanOrEqual(
                    measured.height, 44,
                    "list row fell under the 44pt touch minimum at \(width)pt / \(size)"
                )
            }
        }
    }

    /// The pill is chrome and does not grow, but it still has to clear 44pt and stay inside
    /// the column at the narrowest width.
    func testNavigationPillsStayReachable() {
        for width in widths {
            for size in textSizes {
                for title in ["← SETTINGS", "WEEKLY CALENDAR", "MANAGE PLAN"] {
                    let measured = measure(WSPillLabel(title: title), width: content(width), size: size)
                    XCTAssertGreaterThanOrEqual(
                        measured.height, 44,
                        "pill '\(title)' fell under 44pt at \(width)pt / \(size)"
                    )
                    XCTAssertLessThanOrEqual(
                        measured.width, content(width) + 0.5,
                        "pill '\(title)' spills at \(width)pt / \(size)"
                    )
                }
            }
        }
    }

    // MARK: - Nothing spills out of the content column

    func testButtonsStayInsideTheContentColumn() {
        for width in widths {
            for size in textSizes {
                for title in ["START RUN →", "REBUILD WEEKS", "IMPORT FROM HEALTH", "PREVIEW CHANGES"] {
                    let primary = measure(WSPrimaryButton(title: title) {}, width: content(width), size: size)
                    XCTAssertLessThanOrEqual(primary.width, content(width) + 0.5,
                                             "primary '\(title)' spills at \(width)pt / \(size)")
                    let outline = measure(WSOutlineButton(title: title) {}, width: content(width), size: size)
                    XCTAssertLessThanOrEqual(outline.width, content(width) + 0.5,
                                             "outline '\(title)' spills at \(width)pt / \(size)")
                }
            }
        }
    }

    /// The failure that started this: three chips in a fixed HStack each got less width than
    /// their own longest word, so "STRENGTH" rendered as "STR/ENG/TH". A flow breaks between
    /// chips instead, so every chip keeps at least its intrinsic width.
    func testChipsAreNeverSqueezedBelowTheirOwnWidth() {
        let titles = ["Runs", "Strength", "Mobility", "Kilometers", "Drill Sergeant"]
        for width in widths {
            for size in textSizes {
                for title in titles {
                    let alone = measure(WSChip(title: title, selected: false) {}, width: 10_000, size: size)
                    let inRow = measure(
                        WSChipRow { ForEach(titles, id: \.self) { WSChip(title: $0, selected: false) {} } },
                        width: content(width), size: size
                    )
                    XCTAssertLessThanOrEqual(alone.width, content(width) + 0.5,
                                             "chip '\(title)' cannot fit even alone at \(width)pt / \(size)")
                    XCTAssertLessThanOrEqual(inRow.width, content(width) + 0.5,
                                             "chip row spills at \(width)pt / \(size)")
                }
            }
        }
    }

    /// A flow that wraps has to get taller as the type grows, not silently clip.
    func testChipRowGrowsTallerRatherThanClipping() {
        let row = WSChipRow {
            ForEach(["Beginner", "Intermediate", "Advanced"], id: \.self) {
                WSChip(title: $0, selected: false) {}
            }
        }
        let small = measure(row, width: content(375), size: .large)
        let large = measure(row, width: content(375), size: .accessibility5)
        XCTAssertGreaterThan(large.height, small.height,
                             "the chip row did not reflow — it is squeezing instead of wrapping")
    }

    func testLabelValueRowsStayInsideTheContentColumn() {
        for width in widths {
            for size in textSizes {
                let row = WSHairlineRow(label: "LONGEST RUN RECENTLY", value: "10.0 MI")
                let measured = measure(row, width: content(width), size: size)
                XCTAssertLessThanOrEqual(measured.width, content(width) + 0.5,
                                         "hairline row spills at \(width)pt / \(size)")
            }
        }
    }

    /// Label and value share a line until they would have to squeeze, then stack. Proving the
    /// row got taller proves the axis actually switched.
    func testLabelValueRowSwitchesAxisRatherThanSqueezing() {
        let row = WSHairlineRow(label: "LONGEST RUN RECENTLY", value: "10.0 MI")
        let horizontal = measure(row, width: content(375), size: .large)
        let vertical = measure(row, width: content(375), size: .accessibility5)
        XCTAssertGreaterThan(vertical.height, horizontal.height * 2,
                             "the row did not stack — label and value are still sharing a line")
    }

    // MARK: - Chrome

    /// Apple exempts the tab bar, and the app depends on that: a bar that grew would take about
    /// a quarter of the screen and was clipping START RUN on Today.
    func testTabBarHeightIsIdenticalAtEveryTextSize() {
        var selection = AppTab.today
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let baseline = measure(WSTabBar(selection: binding), width: 375, size: .large).height
        for width in widths {
            for size in textSizes {
                let height = measure(WSTabBar(selection: binding), width: width, size: size).height
                XCTAssertEqual(height, baseline, accuracy: 0.5,
                               "tab bar changed height at \(width)pt / \(size)")
            }
        }
    }

    /// Ties the bar's rendered geometry to the reach it advertises. `MainTabView` derives every
    /// scroll view's bottom inset from `WSTabBar.topEdgeFromScreenBottom`, so if the rendered
    /// height ever drifts from that constant, every screen's clearance is silently wrong by the
    /// difference.
    ///
    /// Note this measures the *bar*, not the individual buttons — a tab whose content is smaller
    /// than its cell would still pass here, so the real per-tab hit region is asserted in
    /// FloatingTabBarUITests.testEveryTabPresentsA44PointTarget.
    func testBarRendersAtItsDeclaredFootprintWithReachableTabs() {
        var selection = AppTab.today
        let binding = Binding(get: { selection }, set: { selection = $0 })
        for width in widths {
            for size in textSizes {
                let bar = measure(WSTabBar(selection: binding), width: width, size: size)
                XCTAssertEqual(bar.height, WSTabBar.topEdgeFromScreenBottom, accuracy: 0.5,
                               "bar renders \(bar.height)pt but advertises \(WSTabBar.topEdgeFromScreenBottom)pt at \(width)pt / \(size)")
                XCTAssertGreaterThanOrEqual(bar.width / CGFloat(AppTab.allCases.count), 44,
                                            "tabs are narrower than 44pt at \(width)pt / \(size)")
            }
        }
    }

    // MARK: - Touch targets

    /// The criteria and the HIG both put the floor at 44pt, and TapTargetUITests guards the
    /// live screens; this covers the components at sizes that suite does not reach.
    func testTouchTargetsStayAtLeast44Points() {
        for size in textSizes {
            let chip = measure(WSChip(title: "Runs", selected: false) {}, width: 10_000, size: size)
            XCTAssertGreaterThanOrEqual(chip.height, 44, "chip is under 44pt at \(size)")
            let button = measure(WSPrimaryButton(title: "START") {}, width: content(375), size: size)
            XCTAssertGreaterThanOrEqual(button.height, 44, "primary button is under 44pt at \(size)")
        }
    }

    /// Buttons must grow to fit their label rather than clip it — the fixed height was what
    /// produced "REBUILD FUT…".
    func testButtonsGrowToFitTheirLabel() {
        let button = WSPrimaryButton(title: "IMPORT FROM HEALTH") {}
        let small = measure(button, width: content(375), size: .large)
        let large = measure(button, width: content(375), size: .accessibility5)
        XCTAssertGreaterThan(large.height, small.height * 1.5,
                             "the button did not grow — its label is being clipped")
    }
}
