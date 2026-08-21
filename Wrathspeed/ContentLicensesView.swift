import SwiftUI
import WrathspeedCore

struct ContentLicensesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WSScreen {
            HStack {
                Button("← BACK") { dismiss() }
                    .font(WSFont.ui(13, weight: .heavy))
                    .foregroundStyle(WSColor.text50)
                Spacer()
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)
            Text("CONTENT\nLICENSES")
                .font(WSFont.display(42))
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            Text("Wrathspeed bundles 58 third-party demonstration clips. They were sourced for a private build, not for public release: the anatomical renders below are not cleared for redistribution. See Content/LICENSE.md before shipping.")
                .font(WSFont.ui(14, weight: .medium))
                .foregroundStyle(WSColor.text50)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 14)
            licenseBlock(
                title: "STRENGTH CATALOG",
                body: "Exercise names, cues, and timers are authored for Wrathspeed. Icons use SF Symbols."
            )
            licenseBlock(
                title: "MOBILITY CATALOG",
                body: "Pre-run, post-run, and recovery routines use local text cues and SF Symbol illustrations."
            )
            licenseBlock(
                title: "DEMONSTRATION CLIPS",
                body: "30 anatomical renders from ExerciseGymGifsDB, which republishes ExerciseDB-derived artwork whose terms restrict redistribution. 27 photographic demos from free-exercise-db, published under the Unlicense."
            )
            licenseBlock(
                title: "EXERCISE DATA BY REPDB (REPDB.CO)",
                body: "The bird dog illustration comes from RepDB's free tier, which permits use inside applications with attribution. Its background is recoloured to white, which that licence allows."
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
                .font(WSFont.ui(13, weight: .heavy))
                .foregroundStyle(WSColor.accent)
            Text(body)
                .font(WSFont.ui(14, weight: .medium))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button("✕") { dismiss() }
                    .font(WSFont.ui(13, weight: .heavy))
                    .foregroundStyle(WSColor.text40)
                    .frame(minWidth: 44, minHeight: 44)
            }
            Text("ABOUT THIS EXERCISE")
                .font(WSFont.mono(10))
                .tracking(1.5)
                .foregroundStyle(WSColor.text40)
            Text(exerciseName.uppercased())
                .font(WSFont.display(32))
                .foregroundStyle(WSColor.text)
                .padding(.top, 8)
            Image(systemName: symbolName)
                .font(.system(size: 48))
                .foregroundStyle(WSColor.accent)
                .padding(.top, 20)
                .accessibilityHidden(true)
            Text(cue)
                .font(WSFont.ui(15, weight: .medium))
                .foregroundStyle(WSColor.text50)
                .padding(.top, 16)
            Text("Local Wrathspeed guidance. No external media bundled.")
                .font(WSFont.mono(11))
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
