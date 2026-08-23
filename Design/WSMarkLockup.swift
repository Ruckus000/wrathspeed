import SwiftUI

/// The three approved mark-plus-wordmark arrangements.
struct WSLockup: View {
    enum Arrangement {
        /// Mark beside the wordmark. The default lockup.
        case horizontal
        /// Mark over the wordmark, centred. For narrow and square placements.
        case stacked
        /// Boxed, small. Labels and footers.
        case caged
    }

    var arrangement: Arrangement = .horizontal
    var style: WSMarkStyle = .primary
    var wordmark: Color = WSColor.text

    init(_ arrangement: Arrangement = .horizontal, style: WSMarkStyle = .primary, wordmark: Color = WSColor.text) {
        self.arrangement = arrangement
        self.style = style
        self.wordmark = wordmark
    }

    @ScaledMetric(relativeTo: .largeTitle) private var markScale: CGFloat = 1

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Wrathspeed")
            .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private var content: some View {
        switch arrangement {
        case .horizontal:
            HStack(spacing: 26) {
                mark(92)
                word(.displayXL, tracking: -0.5)
            }
        case .stacked:
            VStack(spacing: 18) {
                mark(110)
                word(.displayL, tracking: -0.5)
            }
        case .caged:
            HStack(spacing: 14) {
                mark(38)
                word(.displayXS, tracking: 0.5)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .overlay(Rectangle().stroke(wordmark, lineWidth: 2))
        }
    }

    // The wordmark spells the name, so the mark beside it is decorative. The mark tracks the
    // type size so the lockup keeps its drawn proportions instead of the word outgrowing it.
    private func mark(_ size: CGFloat) -> some View {
        WSMark(size: size * min(markScale, 1.8), style: style, label: nil)
    }

    // No .fixedSize(): it forced the lockup to its ideal width, so the horizontal arrangement
    // measured 363pt against the 342pt a phone actually offers inside its gutters and clipped
    // rather than fitting. Letting it size to the space it is given is what keeps it on screen.
    private func word(_ role: WSTypeRole, tracking: CGFloat) -> some View {
        Text("WRATHSPEED")
            .wsType(role, tracking: tracking)
            .foregroundStyle(wordmark)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 32) {
        WSLockup(.horizontal)
        WSLockup(.stacked)
        WSLockup(.caged, style: .monoLight)
    }
    .padding(40)
    .background(WSColor.bg)
}
