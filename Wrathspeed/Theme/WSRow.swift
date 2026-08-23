import SwiftUI

/// A label-and-value row that stacks rather than squeezing.
///
/// The bug this exists to prevent: `HStack { label; Spacer(); value }` divides the width between
/// its two sides, and when either side ends up narrower than its own longest word, the text breaks
/// *inside* the word — `STREAK 0` rendering as `STREA` / `K 0`. Mid-word breaks are not a Dynamic
/// Type problem, they are a squeezing problem, and the fix is to stop squeezing rather than to wrap
/// more gracefully.
///
/// `ViewThatFits` measures rather than guesses. It proposes the ideal size to each candidate and
/// takes the first that fits, so the row stays on one line exactly when both sides genuinely fit
/// and stacks exactly when they don't — at any text size, on any screen width. An earlier pair of
/// fixes switched on `dynamicTypeSize.isAccessibilitySize`, which was wrong in both directions: it
/// stacked short pairs that fitted fine and missed squeezes below the accessibility threshold.
struct WSRow<Leading: View, Trailing: View>: View {
    var alignment: VerticalAlignment = .firstTextBaseline
    var spacing: CGFloat = 12
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Spacer(minLength:) rather than Spacer(): ViewThatFits compares each candidate's
            // *ideal* width, and a spacer's ideal is its minLength. A bare Spacer measures as
            // near-zero, so this candidate would always appear to fit and the row would never
            // stack.
            HStack(alignment: alignment, spacing: 0) {
                leading()
                Spacer(minLength: spacing)
                trailing()
            }
            // Last, deliberately: ViewThatFits falls back to the final candidate when none fit,
            // so the stacked arrangement has to be the one it lands on.
            VStack(alignment: .leading, spacing: 4) {
                leading().frame(maxWidth: .infinity, alignment: .leading)
                trailing().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
