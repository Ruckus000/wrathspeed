import SwiftUI

struct WSEyebrow: View {
    var text: String
    var color: Color = WSColor.accent

    var body: some View {
        Text(text)
            .wsType(.label, tracking: 3)
            .foregroundStyle(color)
    }
}

/// The bordered pill the design uses for screen-level navigation: back at the top of a
/// screen, and the two links out of Plan. 44pt tall, 15pt sides, hairline edge, capsule.
///
/// The label carries the frame, not the Button that wraps it: applied outside, the hit region
/// collapses to the glyph run and the control becomes a thin strip that a test still finds
/// and a finger misses. This repo has been bitten by that twice.
///
/// `.chrome` is the role the ramp reserves for "back and close", and like the tab bar it
/// deliberately does not grow with Dynamic Type.
struct WSPillLabel: View {
    var title: String

    var body: some View {
        Text(title)
            .wsType(.chrome, tracking: 1.2)
            .foregroundStyle(WSColor.text70)
            .padding(.horizontal, 15)
            .frame(height: 44)
            .overlay(Capsule(style: .continuous).stroke(WSColor.border, lineWidth: 1))
            .contentShape(Capsule(style: .continuous))
    }
}

/// The back affordance every screen uses: a bordered pill, not bare text.
///
/// The design draws this identically in eleven places -- Settings, the library and its
/// detail, both history details, Plan, the weekly calendar, Manage Plan, Content Licenses and
/// onboarding -- and it was bare text in all of them. A pill reads as something you press; a
/// grey word at the top of a screen reads as a heading, especially in a design where headings
/// are also grey and uppercase.
struct WSBackButton: View {
    var title: String
    /// Spoken label. Defaults to the visible title, which is also how several UI tests find
    /// these. Deriving it from the title instead produced "Back to BACK" and broke five
    /// queries, so it stays explicit wherever the screen already had a considered one.
    var accessibilityLabel: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            WSPillLabel(title: title)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

struct WSPrimaryButton: View {
    var title: String
    var height: CGFloat = 62
    var role: WSTypeRole = .displayXS
    var fill: Color = WSColor.accent
    var textColor: Color = .white
    var action: () -> Void

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        Button(action: action) {
            Text(title)
                .wsType(role)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                // minHeight, not height: a fixed height truncated the label to "REBUILD FUT…"
                // once the type grew. Apple's Larger Text criteria do not permit truncating a
                // primary action, and prefer wrapping to two lines over shrinking the text.
                .frame(minHeight: height * min(scale, 1.4))
                .background(fill, in: RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct WSOutlineButton: View {
    var title: String
    var height: CGFloat = 52
    var color: Color = WSColor.accent
    /// Edge colour, when it differs from the label's. The diagnostics button is measured in
    /// the design as accent text inside a white-18% border -- one `color` cannot say that,
    /// and using the border colour for both made the label almost invisible.
    var borderColor: Color?
    var action: () -> Void

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        Button(action: action) {
            Text(title)
                .wsType(.body, weight: .heavy, tracking: 1.5)
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .frame(minHeight: height * min(scale, 1.4))
                .overlay(
                    RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                        .stroke(borderColor ?? color, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct WSChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .wsType(.body, weight: .heavy)
                .foregroundStyle(WSColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? WSColor.accentTint : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(selected ? WSColor.accent : WSColor.border, lineWidth: selected ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Lays subviews out in rows, starting a new row when the next one will not fit.
///
/// Chip groups used to be fixed `HStack`s, so three chips split the screen width between them
/// and each got less room than its own longest word -- which is what turned "STRENGTH" into
/// "STR/ENG/TH" at large text sizes. A flow breaks *between* chips instead of inside a word,
/// and needs no size threshold: at small sizes chips pack several to a row, at large sizes each
/// simply takes a row of its own.
struct WSFlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(within: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(within: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(within maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, needed > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// A group of chips that wraps instead of squeezing. Use this anywhere chips appear -- a bare
/// `HStack` will squeeze them at large text sizes.
struct WSChipRow<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        WSFlowLayout(spacing: spacing, rowSpacing: spacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WSSelectRow<Accessory: View>: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        Button(action: action) {
            WSRow {
                Text(title)
                    .wsType(.body)
                    .foregroundStyle(WSColor.text)
            } trailing: {
                accessory()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                    .fill(selected ? WSColor.accentTint : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                    .stroke(selected ? WSColor.accent : WSColor.border, lineWidth: selected ? 1.5 : 1)
            )
            // The row is mostly Spacer. A background shape is not enough on its own here,
            // so the tap target has to be declared explicitly.
            .contentShape(RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        // Matches WSChip. Without these the row renders its selection only as a tint, so
        // VoiceOver cannot tell which option is chosen.
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct WSStepperControl: View {
    var valueText: String
    var decrement: () -> Void
    var increment: () -> Void

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 18) {
            circleButton("−", outlined: true, label: "Decrease", action: decrement)
            Text(valueText)
                .wsType(.displayS)
                .foregroundStyle(WSColor.text)
                .frame(minWidth: 28 * scale)
                .multilineTextAlignment(.center)
            circleButton("+", outlined: false, label: "Increase", action: increment)
        }
    }

    private func circleButton(_ title: String, outlined: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .wsType(.control)
                .foregroundStyle(outlined ? WSColor.text : WSColor.accent)
                .frame(minWidth: 44 * scale, minHeight: 44 * scale)
                .overlay(
                    Circle().stroke(outlined ? Color.white.opacity(0.3) : WSColor.accent, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct WSHairlineRow: View {
    var label: String
    var value: String
    var valueColor: Color = WSColor.text
    var showDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Was an isAccessibilitySize threshold, now WSRow. The threshold was wrong in both
            // directions: it stacked short pairs that fitted fine, and missed squeezes below the
            // accessibility sizes. WSRow measures instead.
            WSRow {
                Text(label)
                    .wsType(.body)
                    .foregroundStyle(Color.white.opacity(0.60))
            } trailing: {
                Text(value)
                    .wsType(.metric, weight: .bold)
                    .foregroundStyle(valueColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            if showDivider {
                Rectangle().fill(WSColor.hairline).frame(height: 1)
            }
        }
    }
}

struct WSProgressBar: View {
    var progress: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WSColor.surface1)
                Capsule()
                    .fill(WSColor.accent)
                    .frame(width: max(0, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: height)
    }
}

struct WSToast: View {
    var text: String

    var body: some View {
        Text(text)
            .wsType(.body, weight: .heavy)
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
    }
}

struct WSAlert: View {
    var message: String
    var onOK: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Text("SOMETHING WENT WRONG")
                    .wsType(.displayXS)
                    .foregroundStyle(WSColor.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                Text(message)
                    .wsType(.body, weight: .medium)
                    .foregroundStyle(WSColor.text70)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                Button(action: onOK) {
                    Text("OK")
                        .wsType(.body, weight: .heavy)
                        .foregroundStyle(WSColor.accent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
                .overlay(alignment: .top) {
                    Rectangle().fill(WSColor.hairlineStrong).frame(height: 1)
                }
            }
            .background(WSColor.bgAlert, in: RoundedRectangle(cornerRadius: WSRadius.alert, style: .continuous))
            .padding(.horizontal, 40)
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case today, plan, history, settings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: "TODAY"
        case .plan: "PLAN"
        case .history: "HISTORY"
        case .settings: "SETTINGS"
        }
    }
    var symbol: String {
        switch self {
        case .today: "bolt.fill"
        case .plan: "calendar"
        case .history: "chart.line.uptrend.xyaxis"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct WSTabBar: View {
    @Binding var selection: AppTab

    /// The capsule itself. Each tab fills its full height, so this is also each tap target's
    /// height.
    static let height: CGFloat = 56

    /// Width of a tab that is not selected.
    ///
    /// The design sizes the bar asymmetrically: every unselected tab is a fixed 46pt icon
    /// button and the selected one absorbs whatever is left, which on a 390pt screen makes
    /// the active pill about 198pt -- well over half the bar. Giving all four an equal share
    /// instead, as this did, shrank the pill to roughly 130pt and pushed the three icons
    /// apart, which is the difference you see against the drawing.
    static let inactiveTabWidth: CGFloat = 46

    /// How far the capsule's bottom edge sits above the *physical* bottom of the screen —
    /// not above the safe area.
    ///
    /// Floating above the whole 34pt home-indicator inset is what left the bar stranded: its
    /// bottom edge landed 42pt up, with a band of scrolling content still visible underneath,
    /// so it read as a widget parked mid-screen rather than as the bar. A floating bar is meant
    /// to sit beside the home indicator, which is what iOS 26's own does.
    ///
    /// The home indicator occupies roughly the bottom 13pt, so this is about as low as the
    /// capsule goes: one point clear of it. Anything smaller and the two touch, which reads as
    /// a rendering fault rather than as a margin.
    static let bottomClearance: CGFloat = 14

    /// How far the bar reaches above the bottom safe area, which is what a scroll view laid out
    /// inside that safe area has to clear.
    ///
    /// This has to be measured rather than declared, because it depends on the device: a phone
    /// with a home indicator hands back 34pt of the bar's height, and one with a home button
    /// hands back none. The app still supports both — `TARGETED_DEVICE_FAMILY` is iPhone, and
    /// the SE runs iOS 26 — so a single constant would be wrong on one of them.
    static func contentInset(safeAreaBottom: CGFloat) -> CGFloat {
        max(0, bottomClearance + height - safeAreaBottom)
    }

    /// Where the bar's top edge sits above the physical bottom. For anything that, like the bar,
    /// positions itself from the screen edge rather than from the safe area.
    static var topEdgeFromScreenBottom: CGFloat { bottomClearance + height }

    @Namespace private var activeTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = tab }
                } label: {
                    tabContent(tab)
                }
                .buttonStyle(.plain)
                // Inactive tabs show no text at all, so the name has to be declared. The UI
                // suites navigate by tab name and would otherwise lose three of four queries.
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
                // The bar deliberately does not grow with Dynamic Type -- Apple exempts tab bars
                // from the Larger Text criteria because a bar that scaled would take roughly a
                // quarter of the screen. Long-press shows the icon and the label at full size.
                .accessibilityShowsLargeContentViewer {
                    Label(tab.label, systemImage: tab.symbol)
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .background(WSColor.bgAlert, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(WSColor.hairlineStrong, lineWidth: 1))
        .padding(.horizontal, 16)
        // The bar's own bottom margin. `MainTabView` then offsets the whole thing down through
        // the safe area, so this ends up measured from the screen edge on every device.
        .padding(.bottom, Self.bottomClearance)
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        HStack(spacing: 7) {
            Image(systemName: tab.symbol)
                // Fixed, like the label: this is chrome, not content.
                .font(.system(size: 20, weight: .semibold))
                .accessibilityHidden(true)
            if isSelected {
                Text(tab.label)
                    .wsType(.chromeTab)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(isSelected ? WSColor.bg : WSColor.text50)
        // Fills the capsule's full height so the whole cell is tappable. Sizing the content to
        // 44pt instead would leave a dead strip top and bottom that still looks like part of
        // the bar, and would put the tap target exactly on the 44pt floor with nothing spare.
        //
        // Width is asymmetric on purpose -- see `inactiveTabWidth`. A 46pt cell still clears
        // the 44pt minimum target.
        .frame(maxWidth: isSelected ? .infinity : nil, maxHeight: .infinity)
        .frame(width: isSelected ? nil : Self.inactiveTabWidth)
        .background {
            if isSelected {
                Capsule(style: .continuous)
                    .fill(WSColor.accent)
                    // Inset so the accent pill still reads as 44pt inside the 56pt bar; the
                    // tap target stays the full cell.
                    .padding(.vertical, 6)
                    .matchedGeometryEffect(id: "activeTab", in: activeTab)
            }
        }
        // Rectangle, not Capsule: a capsule hit region narrows to a point at each tab seam,
        // which is where two icons are closest together.
        .contentShape(Rectangle())
    }
}

private struct WSBottomBarInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// How much room the floating tab bar needs at the bottom of a scroll view so its last row
    /// is not trapped underneath. Zero on screens with no bar over them.
    ///
    /// Note this propagates into sheets and covers presented from inside the tab content —
    /// PlanView's workout sheets, TodayView's players — where the bar is not actually visible.
    /// None of them uses WSScreen today; one that did would get clearance for a bar that isn't
    /// there, and should set this back to 0.
    var wsBottomBarInset: CGFloat {
        get { self[WSBottomBarInsetKey.self] }
        set { self[WSBottomBarInsetKey.self] = newValue }
    }
}

struct WSScreen<Content: View>: View {
    var topPadding: CGFloat = 10
    @ViewBuilder var content: () -> Content

    @Environment(\.wsBottomBarInset) private var bottomBarInset

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.top, topPadding)
            .padding(.bottom, 28 + bottomBarInset)
        }
        .scrollIndicators(.hidden)
        // Identified so UI tests can target the screen's own scroll view rather than
        // app.scrollViews.firstMatch, which is ambiguous wherever a screen nests a horizontal
        // scroll view inside this one -- PlanView's week strip does exactly that.
        .accessibilityIdentifier("ws.screen.scroll")
        .background(WSColor.bg.ignoresSafeArea())
    }
}
