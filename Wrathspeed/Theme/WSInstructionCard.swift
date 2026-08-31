import SwiftUI
import WrathspeedCore

/// The four instruction fields, as a protocol, so the strength catalog, the movement catalog
/// and the library's normalised row can each hand themselves to the card without conversion.
protocol MovementInstructions {
    var howToDoIt: [String]? { get }
    var shouldFeel: String? { get }
    var commonMistake: String? { get }
    var easier: String? { get }
}

extension View {
    /// The inset-card chrome the redesign uses throughout: sheet ground, hairline edge,
    /// 12pt corners. `accent: true` swaps the edge for a tinted accent, which the strength
    /// player's mode card uses to pull the eye to the thing you act on.
    func wsCard(accent: Bool = false) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WSColor.bgSheet, in: RoundedRectangle(cornerRadius: WSRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WSRadius.card, style: .continuous)
                    .stroke(accent ? WSColor.accent.opacity(0.30) : WSColor.hairline, lineWidth: 1)
            )
    }
}

/// A titled block of copy in card chrome -- the design's `CUE` block, and any other short
/// labelled passage that wants the same treatment.
struct WSLabeledCard: View {
    var label: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .wsType(.metricS, tracking: 1.5)
                .foregroundStyle(WSColor.accent)
            Text(text)
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .wsCard()
        .accessibilityElement(children: .combine)
    }
}

/// Beginner instructions for one movement: numbered steps, then what it should feel like,
/// the mistake to avoid, and the regression to fall back on.
///
/// Shared by every surface that explains a movement -- the strength player, the mobility
/// player, and Movement Detail -- so the same wording reaches the reader whether they are
/// mid-set or browsing.
///
/// Renders **nothing** when all four are empty. The catalog is being filled in a movement at
/// a time, and an empty card is worse than no card: it promises help and delivers a blank
/// box. Callers can place it unconditionally.
struct WSInstructionCard: View {
    var howToDoIt: [String]?
    var shouldFeel: String?
    var commonMistake: String?
    var easier: String?

    /// The numbered bullet is a fixed circle, so it has to grow with the text or the digit
    /// clips out of it at the larger settings.
    @ScaledMetric(relativeTo: .body) private var bulletSize: CGFloat = 20

    init(howToDoIt: [String]? = nil, shouldFeel: String? = nil, commonMistake: String? = nil, easier: String? = nil) {
        self.howToDoIt = howToDoIt
        self.shouldFeel = shouldFeel
        self.commonMistake = commonMistake
        self.easier = easier
    }

    init(_ source: MovementInstructions) {
        self.init(
            howToDoIt: source.howToDoIt,
            shouldFeel: source.shouldFeel,
            commonMistake: source.commonMistake,
            easier: source.easier
        )
    }

    private var steps: [String] { (howToDoIt ?? []).filter { !$0.isEmpty } }

    private var footnotes: [(label: String, value: String, accent: Bool)] {
        [
            ("SHOULD FEEL", shouldFeel, false),
            ("COMMON MISTAKE", commonMistake, false),
            ("TOO HARD? DO THIS", easier, true),
        ].compactMap { label, value, accent in
            guard let value, !value.isEmpty else { return nil }
            return (label, value, accent)
        }
    }

    var body: some View {
        if !steps.isEmpty || !footnotes.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if !steps.isEmpty {
                    Text("HOW TO DO IT")
                        .wsType(.metricS, tracking: 1.5)
                        .foregroundStyle(WSColor.accent)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            stepRow(number: index + 1, text: step)
                        }
                    }
                    .padding(.top, 12)
                }
                if !footnotes.isEmpty {
                    // The rule only earns its keep when steps sit above it, and it wants an
                    // equal gap either side rather than sitting flush against the last step.
                    if !steps.isEmpty {
                        Rectangle()
                            .fill(WSColor.hairline)
                            .frame(height: 1)
                            .padding(.top, 14)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(footnotes, id: \.label) { item in
                            footnote(item.label, item.value, accent: item.accent)
                        }
                    }
                    .padding(.top, steps.isEmpty ? 0 : 14)
                }
            }
            .wsCard()
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(number)")
                .wsType(.caption, weight: .heavy)
                .foregroundStyle(WSColor.accent)
                .frame(width: bulletSize, height: bulletSize)
                .background(Circle().fill(WSColor.accentTint))
            Text(text)
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text85)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Read as "Step 1. <text>" rather than letting VoiceOver announce a bare numeral and
        // the sentence as two unrelated elements.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number). \(text)")
    }

    private func footnote(_ label: String, _ value: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .wsType(.metricS, tracking: 1.2)
                .foregroundStyle(accent ? WSColor.accent : WSColor.text40)
            Text(value)
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text70)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// Both catalog types already spell the four fields identically, so these are empty.
extension StrengthExercise: MovementInstructions {}
extension Movement: MovementInstructions {}
