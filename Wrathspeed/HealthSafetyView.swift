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

    var body: some View {
        WSScreen {
            HStack {
                WSBackButton(title: "← SETTINGS", accessibilityLabel: "Back to settings") { dismiss() }
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
                body: "Training is uncomfortable. It should not be sharp. Stop anything that stings, shoots, or sends pins and needles down a limb, and stop a set the moment your form falls apart — a rep done badly is worth less than the rep you did not do."
            )
            block(
                title: "BUILD UP GRADUALLY",
                body: "Most running injuries come from doing too much too soon rather than from doing it wrong. The plan adds distance slowly on purpose. If a week feels like too much, use NOT FEELING 100% rather than pushing through it."
            )
            block(
                title: "THE MOVEMENT GUIDANCE",
                body: "The instructions on each movement are written for a general beginner audience. They cannot account for your history, and where the evidence is genuinely unsettled they say so rather than picking a side. If a physio has told you something different about your own body, follow the physio."
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
