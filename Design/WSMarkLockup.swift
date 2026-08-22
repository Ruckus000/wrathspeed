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
                word(52, tracking: -0.5)
            }
        case .stacked:
            VStack(spacing: 18) {
                mark(110)
                word(44, tracking: -0.5)
            }
        case .caged:
            HStack(spacing: 14) {
                mark(38)
                word(24, tracking: 0.5)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .overlay(Rectangle().stroke(wordmark, lineWidth: 2))
        }
    }

    // The wordmark spells the name, so the mark beside it is decorative.
    private func mark(_ size: CGFloat) -> some View {
        WSMark(size: size, style: style, label: nil)
    }

    private func word(_ size: CGFloat, tracking: CGFloat) -> some View {
        Text("WRATHSPEED")
            .font(WSFont.display(size))
            .tracking(tracking)
            .foregroundStyle(wordmark)
            .fixedSize()
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
