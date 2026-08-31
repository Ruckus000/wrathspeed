import SwiftUI
import WrathspeedCore

struct ContentLicensesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WSScreen {
            HStack {
                Button("← SETTINGS") { dismiss() }
                    .wsType(.body, weight: .heavy)
                    .foregroundStyle(WSColor.text50)
                Spacer()
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)
            Text("CONTENT\nLICENSES")
                .wsType(.displayM)
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            Text("Wrathspeed bundles 60 third-party demonstration clips. They were sourced for a private build, not for public release: the anatomical renders below are not cleared for redistribution. See Content/LICENSE.md before shipping.")
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text50)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 14)
            licenseBlock(
                title: "STRENGTH CATALOG",
                body: "Exercise names, cues, and timers are authored for Wrathspeed. Icons use SF Symbols."
            )
            licenseBlock(
                title: "MOBILITY CATALOG",
                body: "Pre-run, post-run, and recovery routines use local text cues. Eight of the nine movements show a bundled clip; Thoracic Rotation falls back to an SF Symbol."
            )
            licenseBlock(
                title: "DEMONSTRATION CLIPS",
                body: "55 anatomical renders: 32 from ExerciseGymGifsDB and 23 from fitnessprogramer.com. Both republish ExerciseDB-derived artwork whose terms restrict redistribution. 5 photographic demos from free-exercise-db, published under the Unlicense."
            )
            licenseBlock(
                title: "WGER MEDIA",
                body: "The wger allowlist is empty. Verified wger videos will appear here only after license, author, and source URL review."
            )
            Spacer()
        }
    }

    private func licenseBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .wsType(.body, weight: .heavy)
                .foregroundStyle(WSColor.accent)
            Text(body)
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text50)
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 20)
    }
}

struct ExerciseAboutView: View {
    @Environment(\.dismiss) private var dismiss
    let exerciseName: String
    let cue: String
    let symbolName: String
    /// Optional so the view still renders for an exercise with no clip; `MovementMediaView`
    /// falls back to the symbol on an id it does not know, and "" is such an id.
    var movementID: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button("✕") { dismiss() }
                    .wsType(.body, weight: .heavy)
                    .foregroundStyle(WSColor.text40)
                    .frame(minWidth: 44, minHeight: 44)
            }
            Text("ABOUT THIS EXERCISE")
                .wsType(.metricS, tracking: 1.5)
                .foregroundStyle(WSColor.text40)
            Text(exerciseName.uppercased())
                .wsType(.displayS)
                .foregroundStyle(WSColor.text)
                .padding(.top, 8)
            // This sheet is the one place a lifter stops to ask what the movement actually
            // is, so it gets the demo rather than the icon it used to show.
            MovementMediaView(movementID: movementID, symbolName: symbolName, height: 200)
                .padding(.top, 20)
            Text(cue)
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text50)
                .padding(.top, 16)
            Text("Cues are local Wrathspeed guidance. See Content Licenses for the clips.")
                .wsType(.metric)
                .foregroundStyle(WSColor.text40)
                .padding(.top, 20)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 40)
        .background(WSColor.bgSheet.ignoresSafeArea())
    }
}
