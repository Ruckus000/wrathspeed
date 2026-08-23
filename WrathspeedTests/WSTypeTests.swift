import SwiftUI
import XCTest
@testable import Wrathspeed

/// The type ramp is a pure function of (profile, role, size), so its contract is asserted
/// here rather than inferred from screenshots. The repo's previous Dynamic Type test set
/// `UIPreferredContentSizeCategoryName` in `launchEnvironment`, which does nothing — it was
/// green no matter how the app behaved. These cannot be.
final class WSTypeTests: XCTestCase {
    private let contentRoles: [WSTypeRole] = [.control, .body, .label, .caption, .metricL, .metric, .metricS]
    private let expressiveRoles: [WSTypeRole] = [.heroXL, .hero, .displayXL, .displayL, .displayM, .displayS, .displayXS]
    private let chromeRoles: [WSTypeRole] = [.chrome, .chromeTab]

    // MARK: - The criteria

    /// Apple's Larger Text criteria ask for body text past 200% at AX3 and past 300% at AX5.
    /// Content roles carry that; nothing may cap them.
    func testContentRolesMeetTheLargerTextThresholds() {
        for role in contentRoles {
            let base = WSTypeProfile.phone.size(for: role, at: .large)
            let ax3 = WSTypeProfile.phone.size(for: role, at: .accessibility3)
            let ax5 = WSTypeProfile.phone.size(for: role, at: .accessibility5)
            XCTAssertGreaterThan(ax3 / base, 2.0, "\(role) only reaches \(ax3 / base)x at AX3")
            XCTAssertGreaterThan(ax5 / base, 2.9, "\(role) only reaches \(ax5 / base)x at AX5")
        }
    }

    /// The regression that started this: mono took a `relativeTo:` and dropped it, so every
    /// pace, split and distance was frozen. Named explicitly so it cannot come back quietly.
    func testMetricsAreNotFrozen() {
        for role in [WSTypeRole.metricL, .metric, .metricS] {
            let base = WSTypeProfile.phone.size(for: role, at: .large)
            let ax5 = WSTypeProfile.phone.size(for: role, at: .accessibility5)
            XCTAssertGreaterThan(ax5, base * 2, "\(role) is not scaling — mono lost its anchor again")
        }
    }

    /// Chrome is exempt and must not grow: a tab bar that scaled would take a quarter of the
    /// screen. Reachability comes from the large content viewer instead, in WSTabBar.
    func testChromeNeverGrows() {
        for role in chromeRoles {
            let base = WSTypeProfile.phone.size(for: role, at: .large)
            for size in WSTypeMetrics.order {
                XCTAssertEqual(WSTypeProfile.phone.size(for: role, at: size), base, accuracy: 0.01,
                               "\(role) grew at \(size)")
            }
        }
    }

    /// Expressive display grows, but is ceilinged — 140pt already exceeds the system's own
    /// largest style twice over, so it does not need to double again.
    func testExpressiveDisplayGrowsButIsCeilinged() {
        for role in expressiveRoles {
            let base = WSTypeProfile.phone.size(for: role, at: .large)
            let ax5 = WSTypeProfile.phone.size(for: role, at: .accessibility5)
            XCTAssertGreaterThan(ax5, base, "\(role) does not grow at all")
            XCTAssertLessThanOrEqual(ax5 / base, 1.8, "\(role) grows past its ceiling")
        }
    }

    /// Every display role must still clear the system's largest text style, so display type
    /// is never smaller than body text a reader has already asked to be enlarged.
    func testDisplayStaysAheadOfSystemMaximum() {
        let systemMaxBody = WSTypeProfile.phone.size(for: .body, at: .accessibility5)
        for role in expressiveRoles {
            let ax5 = WSTypeProfile.phone.size(for: role, at: .accessibility5)
            XCTAssertGreaterThan(ax5, systemMaxBody, "\(role) falls below body text at AX5")
        }
    }

    // MARK: - Shape of the ramp

    func testSizesAreMonotonicAcrossEveryStep() {
        for profile in [WSTypeProfile.phone, .watch, .widget] {
            for role in contentRoles + expressiveRoles + chromeRoles {
                var previous: CGFloat = 0
                for size in WSTypeMetrics.order {
                    let current = profile.size(for: role, at: size)
                    XCTAssertGreaterThanOrEqual(current, previous,
                                                "\(profile) \(role) shrinks at \(size)")
                    previous = current
                }
            }
        }
    }

    /// The hierarchy has to survive scaling: a role larger than another at the default size
    /// stays larger at every size. Otherwise headings and body cross over at the extremes.
    func testHierarchyHoldsAtEverySize() {
        let ranked: [WSTypeRole] = [.heroXL, .hero, .displayXL, .displayL, .displayM, .displayS, .displayXS]
        for size in WSTypeMetrics.order {
            let sizes = ranked.map { WSTypeProfile.phone.size(for: $0, at: size) }
            XCTAssertEqual(sizes, sizes.sorted(by: >), "display hierarchy inverts at \(size)")
        }
    }

    /// Letter-spacing is part of the role, so it tracks the rendered size instead of reading
    /// progressively tighter as type grows.
    func testTrackingScalesWithSize() {
        let base = WSTypeProfile.phone.tracking(for: .label, at: .large, override: 3)
        let ax5 = WSTypeProfile.phone.tracking(for: .label, at: .accessibility5, override: 3)
        XCTAssertEqual(base, 3, accuracy: 0.001)
        XCTAssertGreaterThan(ax5, base * 2)
        XCTAssertEqual(WSTypeProfile.phone.tracking(for: .body, at: .accessibility5), 0,
                       "a role with no tracking of its own should stay at zero")
    }

    // MARK: - Other profiles

    /// watchOS tops out around 140% of default and its screens are 162–205pt wide, so the
    /// watch ramp has to stay far tighter than the phone's.
    func testWatchRampStaysWithinItsScreen() {
        for role in expressiveRoles {
            XCTAssertLessThanOrEqual(WSTypeProfile.watch.size(for: role, at: .accessibility5), 60,
                                     "\(role) is too large for a watch screen")
        }
        XCTAssertLessThan(WSTypeProfile.watch.size(for: .displayXL, at: .large),
                          WSTypeProfile.phone.size(for: .displayXL, at: .large))
    }

    /// A Live Activity has a fixed height and nowhere to reflow, so every role is capped.
    func testWidgetProfileCapsEveryRole() {
        for role in contentRoles + expressiveRoles + chromeRoles {
            let base = WSTypeProfile.widget.size(for: role, at: .large)
            let ax5 = WSTypeProfile.widget.size(for: role, at: .accessibility5)
            XCTAssertLessThanOrEqual(ax5 / base, 1.3 + 0.001, "\(role) is uncapped in a widget")
        }
    }

    // MARK: - The metrics table

    /// Guards the transcription of Apple's published point sizes, and documents the property
    /// the whole ramp leans on: the small content styles grow around 3x while largeTitle grows
    /// under 1.8x, so anchoring a role correctly does most of the work and the ceilings only
    /// have to catch the display type. Body and caption are near enough to each other that
    /// their order is not something to lean on.
    func testAppleCurveFavoursSmallText() {
        let largeTitle = WSTypeMetrics.scale(.largeTitle, at: .accessibility5)
        let body = WSTypeMetrics.scale(.body, at: .accessibility5)
        let caption = WSTypeMetrics.scale(.caption, at: .accessibility5)
        XCTAssertEqual(largeTitle, 60.0 / 34.0, accuracy: 0.001)
        XCTAssertEqual(body, 53.0 / 17.0, accuracy: 0.001)
        XCTAssertEqual(caption, 36.0 / 12.0, accuracy: 0.001)
        XCTAssertGreaterThan(body, largeTitle * 1.7)
        XCTAssertGreaterThan(caption, largeTitle * 1.6)
    }

    func testDefaultSizeIsUnscaled() {
        for role in contentRoles + expressiveRoles + chromeRoles {
            let spec = WSTypeProfile.phone.spec(for: role)
            XCTAssertEqual(WSTypeProfile.phone.size(for: role, at: .large), spec.base, accuracy: 0.01,
                           "\(role) does not render at its base size by default")
        }
    }
}
