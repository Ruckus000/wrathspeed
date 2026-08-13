import SwiftUI
import WrathspeedCore

struct WorkoutPreflightView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let blueprint: WorkoutBlueprint
    let source: WorkoutSource
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PREFLIGHT")
                .font(WSFont.display(34))
                .foregroundStyle(WSColor.text)
                .accessibilityAddTraits(.isHeader)
            Text(blueprint.title.uppercased())
                .font(WSFont.mono(12))
                .foregroundStyle(WSColor.text45)
                .padding(.top, 8)
            preflightRow("LOCATION", blueprint.location.title.uppercased())
            preflightRow("STEPS", "\(blueprint.steps.count)")
            preflightRow("PLANNED", WSFormat.distance(blueprint.plannedDistanceMeters, unit: store.unit))
            preflightRow("WATCH", WCSessionBridge.isWatchAppInstalled ? "AVAILABLE" : "NOT INSTALLED")
            preflightRow("GPS", blueprint.location == .outdoor ? "REQUIRED" : "NOT REQUIRED")
            VStack(alignment: .leading, spacing: 6) {
                Text("STRUCTURE")
                    .font(WSFont.mono(10))
                    .tracking(1.5)
                    .foregroundStyle(WSColor.text40)
                    .padding(.top, 16)
                ForEach(blueprint.steps.prefix(6)) { step in
                    HStack {
                        Text(step.name)
                            .font(WSFont.ui(13, weight: .bold))
                        Spacer()
                        Text(stepSummary(step))
                            .font(WSFont.mono(11))
                            .foregroundStyle(WSColor.text50)
                    }
                    .accessibilityElement(children: .combine)
                }
                if blueprint.steps.count > 6 {
                    Text("+\(blueprint.steps.count - 6) MORE")
                        .font(WSFont.mono(11))
                        .foregroundStyle(WSColor.text40)
                }
            }
            Spacer(minLength: 20)
            WSPrimaryButton(title: "START WORKOUT") {
                onStart()
                dismiss()
            }
            .accessibilityLabel("Start workout")
            .padding(.top, 12)
            Button("CANCEL") { dismiss() }
                .font(WSFont.ui(12, weight: .heavy))
                .foregroundStyle(WSColor.text50)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 8)
                .accessibilityLabel("Cancel preflight")
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 40)
        .background(WSColor.bgSheet.ignoresSafeArea())
    }

    private func preflightRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(WSFont.ui(12, weight: .heavy))
                .foregroundStyle(WSColor.text45)
            Spacer()
            Text(value)
                .font(WSFont.mono(12))
                .foregroundStyle(WSColor.text)
        }
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }

    private func stepSummary(_ step: WorkoutStep) -> String {
        switch step.target {
        case .distance(let meters): WSFormat.distance(meters, unit: store.unit)
        case .duration(let seconds): Units.formatDuration(seconds)
        }
    }
}
