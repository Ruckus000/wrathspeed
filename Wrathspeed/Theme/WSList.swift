import SwiftUI

/// The design's grouped-list idiom: an eyebrow, then a bordered card of hairline-separated
/// rows. Settings and the movement library are built from it.
///
/// This is a different idiom from `WSHairlineRow`, which is a bare row that draws its own
/// divider with no card around it -- the design uses that one too, on Run Detail, Pace Zones
/// and Week Detail. Both exist on purpose; pick by whether the rows sit in a card.
///
/// Values measured from the rendered design rather than read off the markup:
/// `rgb(19,19,21)` ground, `1px rgba(255,255,255,0.07)` edge, 10pt corners, 20pt side margin.
struct WSListCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WSColor.bgSheet, in: RoundedRectangle(cornerRadius: WSRadius.list, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WSRadius.list, style: .continuous)
                .stroke(WSColor.hairlineSoft, lineWidth: 1)
        )
        .padding(.horizontal, WSSpace.cardGutter)
    }
}

/// One row inside a `WSListCard`: a title, an optional second line, and trailing content --
/// a value, a chevron, or a control such as a segmented track.
///
/// `showDivider` follows the convention `WSHairlineRow` already set: the card cannot know
/// which of its children is last, so the caller turns it off on that one.
struct WSListRow<Trailing: View>: View {
    var title: String
    var hint: String?
    var showDivider: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            // WSRow, not a bare HStack -- it measures both sides and stacks them rather than
            // squeezing either narrower than its longest word. `WSRowAdoptionTests` enforces
            // this repo-wide.
            WSRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .wsType(.body, weight: .bold)
                        .foregroundStyle(WSColor.text)
                    if let hint, !hint.isEmpty {
                        Text(hint)
                            .wsType(.caption, weight: .medium)
                            .foregroundStyle(WSColor.text40)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } trailing: {
                trailing()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            if showDivider {
                Rectangle()
                    .fill(WSColor.hairlineSoft)
                    .frame(height: 1)
            }
        }
    }
}

extension WSListRow where Trailing == EmptyView {
    init(title: String, hint: String? = nil, showDivider: Bool = true) {
        self.init(title: title, hint: hint, showDivider: showDivider) { EmptyView() }
    }
}

/// A row whose trailing content is a chevron -- the design's "goes somewhere" row.
struct WSListNavRow: View {
    var title: String
    var hint: String?
    var showDivider: Bool = true

    var body: some View {
        WSListRow(title: title, hint: hint, showDivider: showDivider) {
            Text("›")
                .wsType(.control, weight: .heavy)
                .foregroundStyle(WSColor.text40)
        }
    }
}

/// The inset segmented control the design uses for the settings options.
///
/// Deliberately not `WSChip`: the design keeps free-standing pills everywhere else --
/// onboarding, Manage Plan, Instant Run, Missed Work, Move Workout, Not Feeling 100% and
/// Preflight -- and uses this track only in Settings and Strength Preferences. `WSChip` is
/// still the right control for those; this is a second, narrower one.
struct WSSegmentedControl<Value: Hashable>: View {
    var options: [Value]
    var label: (Value) -> String
    var isSelected: (Value) -> Bool
    var select: (Value) -> Void
    /// Settings sits its tracks on the screen ground (`trackGround`, 7pt); Strength
    /// Preferences sits them on the card ground (`bgSheet`, 8pt, with an edge). Same control,
    /// two grounds, because in each case the track has to read as inset against what is
    /// behind it.
    var ground: Color = WSColor.trackGround
    var cornerRadius: CGFloat = WSRadius.segmentTrack
    var bordered: Bool = false

    /// Segments are a fixed 40pt in the design. They still have to grow with the text, or the
    /// label clips at the accessibility sizes -- so this scales rather than being hardcoded.
    @ScaledMetric(relativeTo: .body) private var segmentHeight: CGFloat = 40

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                let selected = isSelected(option)
                Button {
                    select(option)
                } label: {
                    Text(label(option))
                        .wsType(.label, weight: .heavy, tracking: 0.8)
                        .foregroundStyle(selected ? .white : WSColor.text50)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        // Padding scales down as the track fills up. At 13pt a side, seven
                        // segments spend ~200pt of a ~330pt track on padding alone and every
                        // label truncates to a single letter. Width is already shared evenly
                        // by `maxWidth: .infinity`, so the padding is only breathing room.
                        .padding(.horizontal, options.count > 4 ? 4 : 8)
                        .frame(maxWidth: .infinity)
                        .frame(height: segmentHeight)
                        .background(
                            RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                                .fill(selected ? WSColor.accent : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(ground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if bordered {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(WSColor.hairlineSoft, lineWidth: 1)
            }
        }
    }
}
