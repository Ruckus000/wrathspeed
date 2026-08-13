import SwiftUI
import WrathspeedCore

struct NotFeeling100View: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var days = 7
    @State private var mode: N100Mode = .reducedDifficulty
    @State private var returnPace: N100Return = .balanced

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOT FEELING 100%")
                .font(WSFont.display(30))
                .foregroundStyle(WSColor.text)
            HStack {
                Text("DAYS")
                    .font(WSFont.ui(14, weight: .heavy))
                Spacer()
                WSStepperControl(
                    valueText: "\(days)",
                    decrement: { days = max(3, days - 1) },
                    increment: { days = min(14, days + 1) }
                )
            }
            .padding(.top, 18)
            Text("MODE")
                .font(WSFont.mono(10))
                .tracking(1.5)
                .foregroundStyle(WSColor.accent)
                .padding(.top, 16)
            VStack(spacing: 8) {
                ForEach(N100Mode.allCases, id: \.self) { item in
                    WSSelectRow(title: item.title, selected: mode == item) { mode = item } accessory: { EmptyView() }
                }
            }
            .padding(.top, 10)
            Text("RETURN PACE")
                .font(WSFont.mono(10))
                .tracking(1.5)
                .foregroundStyle(WSColor.accent)
                .padding(.top, 16)
            HStack(spacing: 8) {
                ForEach(N100Return.allCases, id: \.self) { item in
                    WSChip(title: item.title, selected: returnPace == item) { returnPace = item }
                }
            }
            .padding(.top, 10)
            WSPrimaryButton(title: "APPLY", height: 54, fontSize: 19) {
                store.applyNotFeeling100(
                    N100Adjustment(start: Date(), dayCount: days, mode: mode, returnPace: returnPace)
                )
                dismiss()
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 52)
        .background(WSColor.bgSheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(WSColor.bgSheet)
    }
}

struct InstantRunView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: WorkoutKind = .easy
    @State private var location: RunLocation = .outdoor
    @State private var targetMode: InstantTargetMode = .distance
    @State private var distanceKm: Double = 5
    @State private var durationMinutes: Double = 30
    @State private var preview: WorkoutBlueprint?
    @State private var buildError: String?

    private let kinds: [WorkoutKind] = [.easy, .intervals, .tempo, .longRun, .walkRun, .freeRun]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("INSTANT RUN")
                .font(WSFont.display(30))
                .foregroundStyle(WSColor.text)
                .accessibilityAddTraits(.isHeader)
            builderSection
            if let preview {
                previewSection(preview)
            }
            if let buildError {
                Text(buildError)
                    .font(WSFont.mono(12))
                    .foregroundStyle(WSColor.accent)
                    .padding(.top, 8)
            }
            WSOutlineButton(title: "PREVIEW WORKOUT") { rebuildPreview() }
                .padding(.top, 16)
            WSPrimaryButton(title: "CONTINUE →", height: 54, fontSize: 19) {
                guard let preview else { rebuildPreview(); return }
                store.presentPreflight(blueprint: preview, source: .instant)
                dismiss()
            }
            .disabled(preview == nil)
            .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 52)
        .background(WSColor.bgSheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(WSColor.bgSheet)
        .onAppear { rebuildPreview() }
    }

    @ViewBuilder
    private var builderSection: some View {
        Text("WORKOUT")
            .font(WSFont.mono(10))
            .tracking(1.5)
            .foregroundStyle(WSColor.accent)
            .padding(.top, 16)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(kinds, id: \.self) { item in
                    WSChip(title: item.instantLabel, selected: kind == item) { kind = item; rebuildPreview() }
                }
            }
        }
        Text("LOCATION")
            .font(WSFont.mono(10))
            .tracking(1.5)
            .foregroundStyle(WSColor.accent)
            .padding(.top, 16)
        HStack(spacing: 8) {
            ForEach(RunLocation.allCases, id: \.self) { item in
                WSChip(title: item.title, selected: location == item) { location = item; rebuildPreview() }
            }
        }
        .padding(.top, 10)
        Text("TARGET")
            .font(WSFont.mono(10))
            .tracking(1.5)
            .foregroundStyle(WSColor.accent)
            .padding(.top, 16)
        HStack(spacing: 8) {
            WSChip(title: "DISTANCE", selected: targetMode == .distance) { targetMode = .distance; rebuildPreview() }
            WSChip(title: "TIME", selected: targetMode == .duration) { targetMode = .duration; rebuildPreview() }
        }
        .padding(.top, 10)
        if targetMode == .distance {
            HStack {
                Text("DISTANCE")
                    .font(WSFont.ui(14, weight: .heavy))
                Spacer()
                WSStepperControl(
                    valueText: String(format: "%.1f %@", distanceKm, WSFormat.unitLabel(store.unit)),
                    decrement: { distanceKm = max(1, distanceKm - 0.5); rebuildPreview() },
                    increment: { distanceKm = min(42, distanceKm + 0.5); rebuildPreview() }
                )
            }
            .padding(.top, 12)
        } else {
            HStack {
                Text("DURATION")
                    .font(WSFont.ui(14, weight: .heavy))
                Spacer()
                WSStepperControl(
                    valueText: "\(Int(durationMinutes)) MIN",
                    decrement: { durationMinutes = max(10, durationMinutes - 5); rebuildPreview() },
                    increment: { durationMinutes = min(180, durationMinutes + 5); rebuildPreview() }
                )
            }
            .padding(.top, 12)
        }
    }

    private func previewSection(_ blueprint: WorkoutBlueprint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PREVIEW")
                .font(WSFont.mono(10))
                .tracking(1.5)
                .foregroundStyle(WSColor.text40)
                .padding(.top, 18)
            Text(blueprint.title.uppercased())
                .font(WSFont.ui(16, weight: .heavy))
            ForEach(blueprint.steps.prefix(4)) { step in
                HStack {
                    Text(step.name)
                    Spacer()
                    Text(stepLabel(step))
                        .font(WSFont.mono(11))
                        .foregroundStyle(WSColor.text50)
                }
                .font(WSFont.ui(13, weight: .bold))
            }
            if blueprint.steps.count > 4 {
                Text("+\(blueprint.steps.count - 4) MORE STEPS")
                    .font(WSFont.mono(11))
                    .foregroundStyle(WSColor.text40)
            }
        }
    }

    private func stepLabel(_ step: WorkoutStep) -> String {
        switch step.target {
        case .distance(let meters): WSFormat.distance(meters, unit: store.unit)
        case .duration(let seconds): Units.formatDuration(seconds)
        }
    }

    private func rebuildPreview() {
        let meters = store.unit == .miles ? distanceKm * 1_609.344 : distanceKm * 1_000
        let request = InstantWorkoutRequest(
            kind: kind,
            location: location,
            targetMode: targetMode,
            distanceMeters: targetMode == .distance ? meters : nil,
            durationSeconds: targetMode == .duration ? durationMinutes * 60 : nil
        )
        do {
            try InstantWorkoutValidation.validate(request)
            preview = try InstantWorkoutBuilder.build(request)
            buildError = nil
        } catch {
            preview = nil
            buildError = error.localizedDescription
        }
    }
}
