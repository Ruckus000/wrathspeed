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
                        .stroke(color, lineWidth: 1.5)
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
            HStack {
                Text(title)
                    .wsType(.body)
                    .foregroundStyle(WSColor.text)
                Spacer(minLength: 12)
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            // Label and value sit side by side until the text is large enough that sharing a
            // line would squeeze either of them narrower than its own longest word -- which is
            // what produces mid-word breaks like "STR/ENG/TH". Apple's rule for this is to wrap
            // side-by-side elements vertically rather than let them collide.
            layout {
                Text(label)
                    .wsType(.body)
                    .foregroundStyle(Color.white.opacity(0.60))
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }
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

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 0))
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

    /// The capsule itself. Four tabs divide it, so this is also each tap target's height.
    static let height: CGFloat = 56
    /// How far it floats above the safe area.
    static let gap: CGFloat = 8
    /// What a scroll view underneath has to clear.
    static var footprint: CGFloat { height + gap }

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
        .padding(.bottom, Self.gap)
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
        .frame(maxWidth: .infinity)
        .frame(height: Self.height - 12)
        .background {
            if isSelected {
                Capsule(style: .continuous)
                    .fill(WSColor.accent)
                    .matchedGeometryEffect(id: "activeTab", in: activeTab)
            }
        }
        .contentShape(Capsule(style: .continuous))
    }
}

private struct WSBottomBarInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// How much room the floating tab bar needs at the bottom of a scroll view so its last row
    /// is not trapped underneath. Zero on screens with no bar over them.
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
        .background(WSColor.bg.ignoresSafeArea())
    }
}
