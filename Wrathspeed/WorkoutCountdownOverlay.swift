import SwiftUI

/// The three seconds between tapping start and the workout actually recording.
///
/// The pause itself is not new -- `WorkoutSessionController` has always held here while the
/// HealthKit session comes up -- but nothing was drawn during it, so a start looked like a
/// stalled screen. This gives the wait a number.
///
/// It is never shown when the countdown is skipped: Reduce Motion, and the UI-test skip flag,
/// both leave `countdownRemaining` nil and the overlay unmounted. The footnote says so, since
/// a person who has turned Reduce Motion on is the one most likely to wonder where the
/// countdown went.
struct WorkoutCountdownOverlay: View {
    let remaining: Int
    let title: String

    var body: some View {
        ZStack {
            WSColor.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Text(title.uppercased())
                    .wsType(.label, weight: .heavy, tracking: 3)
                    .foregroundStyle(WSColor.accent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, WSSpace.gutter)
                Text("\(remaining)")
                    .wsType(.hero)
                    .foregroundStyle(WSColor.text)
                    .padding(.top, 6)
                    // Without this the digit re-announces on every tick and talks over
                    // itself; the label below carries the meaning once.
                    .accessibilityHidden(true)
                Text("REDUCE MOTION SKIPS THE COUNTDOWN")
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text40)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 10)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Starting in \(remaining)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}
