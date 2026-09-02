import SwiftUI
import WrathspeedCore

/// The app's health statement, and until now it had none: nothing in the app told anyone when to
/// stop, and the movement instructions are guidance people follow under load.
///
/// Reached from Settings so it stays findable, and summarised in one line above `CONFIRM PLAN →`
/// during onboarding so it is seen in context at least once. Modelled on `ContentLicensesView`,
/// which is the same shape of screen: a title, a lead paragraph, then labelled blocks.
struct HealthSafetyView: View {
    @Environment(\.dismiss) private var dismiss
    /// Where the back button says it goes. Settings pushes this screen; the coach presents it as
    /// a sheet, and "← SETTINGS" over a coach conversation would be a lie.
    var backTitle: String = "← SETTINGS"
    var backAccessibilityLabel: String = "Back to settings"

    var body: some View {
        WSScreen {
            HStack {
                WSBackButton(title: backTitle, accessibilityLabel: backAccessibilityLabel) { dismiss() }
                Spacer()
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)

            Text("HEALTH\nAND SAFETY")
                .wsType(.displayM)
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)

            Text("Wrathspeed builds training plans and shows you how the movements are done. It is not medical advice, and it does not know anything about you beyond what you have told it.")
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text50)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 14)

            block(
                title: "BEFORE YOU START",
                body: "Talk to a doctor first if you have a health condition, are pregnant, are coming back from an injury that has not settled, or have been away from exercise for a long time."
            )
            block(
                title: "STOP IF IT HURTS",
                body: "Training is uncomfortable. It should not be sharp. Stop anything that stings, shoots, or sends pins and needles down a limb, and stop a set once your form falls apart."
            )
            block(
                title: "BUILD UP GRADUALLY",
                body: "Doing too much too soon is one of the most common causes of running injury. The plan adds distance slowly on purpose. If a week feels like too much, use NOT FEELING 100% rather than pushing through it."
            )
            // Says what the guidance actually does. The first version claimed the instructions
            // flag unsettled evidence where it exists; they do not. What they do is pick wording
            // that holds up whichever way a live debate lands -- which is a different promise,
            // and the one that is true.
            block(
                title: "THE MOVEMENT GUIDANCE",
                body: "The instructions on each movement are written for a general beginner audience, and cannot account for your history. Some of what they teach is genuinely debated among coaches and physiotherapists; where that is true, the wording aims to be safe whichever way the debate lands rather than taking a side. If a physio has told you something different about your own body, follow the physio."
            )

            Spacer(minLength: 34)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func block(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .wsType(.body, weight: .heavy)
                .foregroundStyle(WSColor.accent)
            Text(body)
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text50)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 20)
    }
}
