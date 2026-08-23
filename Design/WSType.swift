import SwiftUI

/// The Wrathspeed type ramp.
///
/// Every piece of text in the app resolves through here, so that how it responds to Dynamic
/// Type is one decision rather than 355 of them. Roles fall into three classes, taken from
/// Apple's Larger Text criteria for the App Store accessibility label:
///
/// - **Content** — body copy, list rows, button labels and every metric. Scales the whole
///   range with no ceiling. This is the text the criteria actually measure, and the class
///   that was frozen before: `WSFont.mono` took a `relativeTo:` and dropped it, so 129 paces,
///   splits and distances rendered at 9–15pt no matter what the reader had asked for.
/// - **Expressive** — the oversized display type the brand is built on, up to a 140pt pace
///   hero. It grows, but gently: the criterion is "200% *or the maximum font size for the
///   system*", and 140pt already exceeds the system's own largest style (`.largeTitle` tops
///   out at 60pt) more than twice over.
/// - **Chrome** — the tab bar and repeated navigation. Explicitly exempt, and must *not*
///   grow: a tab bar that scales would take a quarter of the screen. It gets the large
///   content viewer instead, wired up in `WSTabBar`.
///
/// Sizing is a pure function of `(profile, role, DynamicTypeSize)` — deliberately, so it can
/// be asserted in unit tests without a simulator, a host app or a screenshot.
enum WSTypeRole {
    // Expressive display, Anton.
    case heroXL      // 140 — live pace
    case hero        // 110 — celebration, countdown
    case displayXL   // 58  — screen headlines
    case displayL    // 46
    case displayM    // 42
    case displayS    // 32
    case displayXS   // 26  — sheet titles

    // Content, Archivo.
    case control     // 18 — button labels
    case body        // 14 — row titles, copy
    case label       // 12 — eyebrows, section headers
    case caption     // 10

    // Content, monospaced. Paces, splits, distances, dates.
    case metricL     // 24
    case metric      // 12
    case metricS     // 10

    // Chrome. Does not grow; see WSTabBar.
    case chrome      // 13 — back and close
    case chromeTab   // 11 — tab bar labels
}

enum WSTypeFace {
    case display, ui, mono
}

/// How one role renders: which face, its size at the default text setting, which Apple text
/// style its growth follows, and how far it may grow.
struct WSTypeSpec {
    var face: WSTypeFace
    var base: CGFloat
    var anchor: Font.TextStyle
    /// Ceiling as a multiple of `base`. `.infinity` for content — the accessibility win lives
    /// there and nothing should clamp it. `1` for chrome, which must not grow at all.
    var maxScale: CGFloat
    var weight: Font.Weight = .bold
    /// Letter-spacing at `base`. Almost every role is zero; call sites that want spacing pass
    /// `tracking:` to `wsType`, and it is scaled with the resolved size either way so it never
    /// reads tighter as the type grows.
    var tracking: CGFloat = 0
}

/// The three device tables. Roles and scaling behaviour are shared; only the sizes differ.
enum WSTypeProfile {
    /// iPhone.
    case phone
    /// watchOS. Screens are 162–205pt wide and the platform's largest Dynamic Type size is
    /// only about 140% of default, so the bases are smaller and the range is much narrower.
    case watch
    /// Widgets and Live Activities. Height-constrained and unable to reflow, so every role is
    /// treated as chrome-class with a tight ceiling.
    case widget

    func spec(for role: WSTypeRole) -> WSTypeSpec {
        switch self {
        case .phone: Self.phoneSpec(role)
        case .watch: Self.watchSpec(role)
        case .widget: Self.widgetSpec(role)
        }
    }

    // Display ceilings: 1.8x for headlines, 1.15x for the heroes that are already far past
    // any system size. Content is uncapped. 1.8 rather than a rounder 1.6 because body text
    // reaches 3.1x at AX5 -- at 1.6 the smallest display role renders *smaller* than the body
    // copy beneath it and the hierarchy inverts.
    private static func phoneSpec(_ role: WSTypeRole) -> WSTypeSpec {
        switch role {
        case .heroXL: WSTypeSpec(face: .display, base: 140, anchor: .largeTitle, maxScale: 1.15)
        case .hero: WSTypeSpec(face: .display, base: 110, anchor: .largeTitle, maxScale: 1.15)
        case .displayXL: WSTypeSpec(face: .display, base: 58, anchor: .largeTitle, maxScale: 1.8)
        case .displayL: WSTypeSpec(face: .display, base: 46, anchor: .largeTitle, maxScale: 1.8)
        case .displayM: WSTypeSpec(face: .display, base: 42, anchor: .largeTitle, maxScale: 1.8)
        case .displayS: WSTypeSpec(face: .display, base: 32, anchor: .largeTitle, maxScale: 1.8)
        case .displayXS: WSTypeSpec(face: .display, base: 26, anchor: .largeTitle, maxScale: 1.8)
        case .control: WSTypeSpec(face: .ui, base: 18, anchor: .body, maxScale: .infinity, weight: .heavy)
        case .body: WSTypeSpec(face: .ui, base: 14, anchor: .body, maxScale: .infinity, weight: .bold)
        case .label: WSTypeSpec(face: .ui, base: 12, anchor: .caption, maxScale: .infinity, weight: .heavy)
        case .caption: WSTypeSpec(face: .ui, base: 10, anchor: .caption2, maxScale: .infinity, weight: .bold)
        case .metricL: WSTypeSpec(face: .mono, base: 24, anchor: .body, maxScale: .infinity, weight: .semibold)
        case .metric: WSTypeSpec(face: .mono, base: 12, anchor: .caption, maxScale: .infinity, weight: .semibold)
        case .metricS: WSTypeSpec(face: .mono, base: 10, anchor: .caption2, maxScale: .infinity, weight: .semibold)
        case .chrome: WSTypeSpec(face: .ui, base: 13, anchor: .body, maxScale: 1, weight: .heavy)
        case .chromeTab: WSTypeSpec(face: .ui, base: 11, anchor: .caption, maxScale: 1, weight: .heavy, tracking: 1.5)
        }
    }

    private static func watchSpec(_ role: WSTypeRole) -> WSTypeSpec {
        switch role {
        case .heroXL, .hero: WSTypeSpec(face: .display, base: 44, anchor: .largeTitle, maxScale: 1.2)
        case .displayXL, .displayL: WSTypeSpec(face: .display, base: 32, anchor: .largeTitle, maxScale: 1.3)
        case .displayM, .displayS: WSTypeSpec(face: .display, base: 28, anchor: .largeTitle, maxScale: 1.3)
        case .displayXS: WSTypeSpec(face: .display, base: 22, anchor: .largeTitle, maxScale: 1.3)
        case .control: WSTypeSpec(face: .ui, base: 14, anchor: .body, maxScale: .infinity, weight: .heavy)
        case .body: WSTypeSpec(face: .ui, base: 13, anchor: .body, maxScale: .infinity, weight: .bold)
        case .label: WSTypeSpec(face: .ui, base: 11, anchor: .caption, maxScale: .infinity, weight: .heavy)
        case .caption: WSTypeSpec(face: .ui, base: 9, anchor: .caption2, maxScale: .infinity, weight: .bold)
        case .metricL: WSTypeSpec(face: .mono, base: 16, anchor: .body, maxScale: .infinity, weight: .semibold)
        case .metric: WSTypeSpec(face: .mono, base: 11, anchor: .caption, maxScale: .infinity, weight: .semibold)
        case .metricS: WSTypeSpec(face: .mono, base: 10, anchor: .caption2, maxScale: .infinity, weight: .semibold)
        case .chrome: WSTypeSpec(face: .ui, base: 12, anchor: .body, maxScale: 1, weight: .heavy)
        case .chromeTab: WSTypeSpec(face: .ui, base: 10, anchor: .caption, maxScale: 1, weight: .heavy, tracking: 1)
        }
    }

    // A Live Activity has a fixed height and nowhere to reflow to, so nothing here grows much.
    private static func widgetSpec(_ role: WSTypeRole) -> WSTypeSpec {
        var spec = phoneSpec(role)
        spec.maxScale = min(spec.maxScale, 1.3)
        return spec
    }
}

// MARK: - Resolution

/// Apple's published point sizes per text style, indexed by `DynamicTypeSize`. Hardcoding the
/// table rather than reading `UIFontMetrics` buys two things the app needs: it compiles on
/// watchOS, where `UIFontMetrics` does not exist, and it makes every size assertable in a
/// plain unit test.
enum WSTypeMetrics {
    static let order: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
    ]

    private static let table: [Font.TextStyle: [CGFloat]] = [
        .largeTitle: [31, 32, 33, 34, 36, 38, 40, 44, 48, 52, 56, 60],
        .title: [25, 26, 27, 28, 30, 32, 34, 38, 42, 46, 50, 54],
        .title2: [19, 20, 21, 22, 24, 26, 28, 34, 38, 42, 46, 50],
        .title3: [17, 18, 19, 20, 22, 24, 26, 31, 35, 39, 43, 47],
        .body: [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53],
        .callout: [13, 14, 15, 16, 18, 20, 22, 26, 32, 38, 44, 50],
        .subheadline: [12, 13, 14, 15, 17, 19, 21, 25, 30, 36, 42, 49],
        .footnote: [12, 12, 12, 13, 15, 17, 19, 23, 27, 33, 38, 44],
        .caption: [11, 11, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36],
        .caption2: [11, 11, 11, 11, 13, 15, 17, 19, 23, 27, 31, 35],
    ]

    /// How much `style` has grown at `size`, relative to its size at the default setting.
    static func scale(_ style: Font.TextStyle, at size: DynamicTypeSize) -> CGFloat {
        guard let sizes = table[style],
              let index = order.firstIndex(of: size),
              let defaultIndex = order.firstIndex(of: .large)
        else { return 1 }
        return sizes[index] / sizes[defaultIndex]
    }
}

extension WSTypeProfile {
    /// The rendered point size for a role. Pure, so tests can walk every role across every
    /// step without a running app.
    func size(for role: WSTypeRole, at dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let spec = spec(for: role)
        // Chrome is exempt in both directions. Capping only the top would still let the tab
        // bar shrink below the size the design specifies at the smaller settings.
        guard spec.maxScale > 1 else { return spec.base }
        let scaled = spec.base * WSTypeMetrics.scale(spec.anchor, at: dynamicTypeSize)
        return min(scaled, spec.base * spec.maxScale)
    }

    func font(for role: WSTypeRole, at dynamicTypeSize: DynamicTypeSize) -> Font {
        let spec = spec(for: role)
        let size = size(for: role, at: dynamicTypeSize)
        switch spec.face {
        // fixedSize, not relativeTo: the scaling has already been applied above, and
        // relativeTo would apply the platform curve a second time on top of it.
        case .display: return .custom("Anton", fixedSize: size)
        case .ui: return .custom("Archivo", fixedSize: size).weight(spec.weight)
        case .mono: return .system(size: size, weight: spec.weight, design: .monospaced).leading(.loose)
        }
    }

    /// Letter-spacing, scaled by however far the role's size has grown. `override` lets a call
    /// site keep spacing the role does not carry by default.
    func tracking(for role: WSTypeRole, at dynamicTypeSize: DynamicTypeSize, override: CGFloat? = nil) -> CGFloat {
        let spec = spec(for: role)
        let base = override ?? spec.tracking
        guard base != 0 else { return 0 }
        return base * (size(for: role, at: dynamicTypeSize) / spec.base)
    }
}

// MARK: - Applying it

private struct WSTypeProfileKey: EnvironmentKey {
    static let defaultValue: WSTypeProfile = {
        #if os(watchOS)
        .watch
        #else
        .phone
        #endif
    }()
}

extension EnvironmentValues {
    var wsTypeProfile: WSTypeProfile {
        get { self[WSTypeProfileKey.self] }
        set { self[WSTypeProfileKey.self] = newValue }
    }
}

private struct WSTypeModifier: ViewModifier {
    var role: WSTypeRole
    var weight: Font.Weight?
    var tracking: CGFloat?

    @Environment(\.wsTypeProfile) private var profile
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        var font = profile.font(for: role, at: dynamicTypeSize)
        if let weight { font = font.weight(weight) }
        return content
            .font(font)
            .tracking(profile.tracking(for: role, at: dynamicTypeSize, override: tracking))
    }
}

extension View {
    /// Apply a type role. Pass `weight` or `tracking` only where a call site genuinely differs
    /// from the role's own; both scale with the role.
    func wsType(_ role: WSTypeRole, weight: Font.Weight? = nil, tracking: CGFloat? = nil) -> some View {
        modifier(WSTypeModifier(role: role, weight: weight, tracking: tracking))
    }

    /// Set the type profile for a subtree. The widget root needs this; the phone and watch
    /// defaults are correct on their own.
    func wsTypeProfile(_ profile: WSTypeProfile) -> some View {
        environment(\.wsTypeProfile, profile)
    }
}
