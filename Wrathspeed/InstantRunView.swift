import SwiftUI
import WrathspeedCore

struct InstantRunView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: WorkoutKind = .easy
    @State private var location: RunLocation = .outdoor
    @State private var targetMode: InstantTargetMode = .distance
    @State private var distanceDisplay: Double = 5
    @State private var durationMinutes: Double = 30
    @State private var tempoWarmupDisplay: Double = 1.5
    @State private var tempoWorkDisplay: Double = 5
    @State private var tempoCooldownDisplay: Double = 1
    @State private var intervalReps: Int = 6
    @State private var intervalWorkDisplay: Double = 0.4
    @State private var intervalRecoveryDisplay: Double = 0.2
    @State private var intervalWarmupDisplay: Double = 1.5
    @State private var intervalCooldownDisplay: Double = 1
    @State private var intervalIncludeExtras = true
    @State private var walkRunMinutes: Double = 1
    @State private var walkRestMinutes: Double = 1.5
    @State private var walkRunReps: Int = 8
    @State private var preview: WorkoutBlueprint?
    @State private var buildError: String?

    private let kinds: [WorkoutKind] = [.easy, .intervals, .tempo, .longRun, .walkRun, .freeRun, .race]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("INSTANT RUN")
                .wsType(.displayS)
                .foregroundStyle(WSColor.text)
                .accessibilityAddTraits(.isHeader)
            builderSection
            if let preview {
                previewSection(preview)
            }
            if let buildError {
                Text(buildError)
                    .wsType(.metric)
                    .foregroundStyle(WSColor.accent)
                    .padding(.top, 8)
                    .accessibilityLabel(buildError)
                    .accessibilityAddTraits(.isStaticText)
            }
            WSOutlineButton(title: "PREVIEW WORKOUT") { rebuildPreview() }
                .padding(.top, 16)
            WSPrimaryButton(title: "CONTINUE →", height: 54, role: .control) {
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
            .wsType(.metricS, tracking: 1.5)
            .foregroundStyle(WSColor.accent)
            .padding(.top, 16)
        ScrollView(.horizontal, showsIndicators: false) {
            WSChipRow {
                ForEach(kinds, id: \.self) { item in
                    WSChip(title: item.instantLabel, selected: kind == item) {
                        kind = item
                        if item == .race { targetMode = .distance }
                        rebuildPreview()
                    }
                }
            }
        }
        Text("LOCATION")
            .wsType(.metricS, tracking: 1.5)
            .foregroundStyle(WSColor.accent)
            .padding(.top, 16)
        HStack(spacing: 8) {
            ForEach(RunLocation.allCases, id: \.self) { item in
                WSChip(title: item.title, selected: location == item) { location = item; rebuildPreview() }
            }
        }
        .padding(.top, 10)
        kindControls
    }

    @ViewBuilder
    private var kindControls: some View {
        switch kind {
        case .easy, .longRun, .freeRun:
            distanceOrDurationControls
        case .race:
            raceDistanceControls
        case .tempo:
            tempoControls
        case .intervals:
            intervalControls
        case .walkRun:
            walkRunControls
        case .strength:
            EmptyView()
        }
    }

    private var distanceOrDurationControls: some View {
        Group {
            Text("TARGET")
                .wsType(.metricS, tracking: 1.5)
                .foregroundStyle(WSColor.accent)
                .padding(.top, 16)
            HStack(spacing: 8) {
                WSChip(title: "DISTANCE", selected: targetMode == .distance) { targetMode = .distance; rebuildPreview() }
                WSChip(title: "TIME", selected: targetMode == .duration) { targetMode = .duration; rebuildPreview() }
            }
            .padding(.top, 10)
            if targetMode == .distance {
                displayDistanceStepper(label: "DISTANCE", value: $distanceDisplay, range: 1...42)
            } else {
                durationStepper
            }
        }
    }

    private var raceDistanceControls: some View {
        Group {
            Text("TARGET")
                .wsType(.metricS, tracking: 1.5)
                .foregroundStyle(WSColor.accent)
                .padding(.top, 16)
            displayDistanceStepper(label: "DISTANCE", value: $distanceDisplay, range: 1...42)
        }
    }

    private var tempoControls: some View {
        Group {
            displayDistanceStepper(label: "WARM UP", value: $tempoWarmupDisplay, range: 0.5...5)
            displayDistanceStepper(label: "TEMPO", value: $tempoWorkDisplay, range: 1...20)
            displayDistanceStepper(label: "COOL DOWN", value: $tempoCooldownDisplay, range: 0.5...5)
        }
    }

    private var intervalControls: some View {
        Group {
            repsStepper(label: "REPETITIONS", value: $intervalReps)
            displayDistanceStepper(label: "WORK", value: $intervalWorkDisplay, range: 0.1...2)
            displayDistanceStepper(label: "RECOVERY", value: $intervalRecoveryDisplay, range: 0.1...2)
            Toggle("Include warm up / cool down", isOn: $intervalIncludeExtras)
                .wsType(.body, weight: .medium)
                .tint(WSColor.accent)
                .padding(.top, 12)
                .onChange(of: intervalIncludeExtras) { _, _ in rebuildPreview() }
            if intervalIncludeExtras {
                displayDistanceStepper(label: "WARM UP", value: $intervalWarmupDisplay, range: 0.5...5)
                displayDistanceStepper(label: "COOL DOWN", value: $intervalCooldownDisplay, range: 0.5...5)
            }
        }
    }

    private var walkRunControls: some View {
        Group {
            minuteStepper(label: "RUN", value: $walkRunMinutes, range: 0.5...10)
            minuteStepper(label: "WALK", value: $walkRestMinutes, range: 0.5...10)
            repsStepper(label: "REPETITIONS", value: $walkRunReps)
        }
    }

    private func displayDistanceStepper(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack {
            Text(label)
                .wsType(.body, weight: .heavy)
            Spacer()
            WSStepperControl(
                valueText: String(format: "%.1f %@", value.wrappedValue, WSFormat.unitLabel(store.unit)),
                decrement: { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 0.5) ; rebuildPreview() },
                increment: { value.wrappedValue = min(range.upperBound, value.wrappedValue + 0.5) ; rebuildPreview() }
            )
        }
        .padding(.top, 12)
    }

    private var durationStepper: some View {
        HStack {
            Text("DURATION")
                .wsType(.body, weight: .heavy)
            Spacer()
            WSStepperControl(
                valueText: "\(Int(durationMinutes)) MIN",
                decrement: { durationMinutes = max(10, durationMinutes - 5); rebuildPreview() },
                increment: { durationMinutes = min(180, durationMinutes + 5); rebuildPreview() }
            )
        }
        .padding(.top, 12)
    }

    private func minuteStepper(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .wsType(.body, weight: .heavy)
            Spacer()
            WSStepperControl(
                valueText: minuteLabel(value.wrappedValue),
                decrement: { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 0.5); rebuildPreview() },
                increment: { value.wrappedValue = min(range.upperBound, value.wrappedValue + 0.5); rebuildPreview() }
            )
        }
        .padding(.top, 12)
    }

    private func minuteLabel(_ minutes: Double) -> String {
        let tenths = (minutes * 10).rounded() / 10
        if tenths.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f MIN", tenths)
        }
        return String(format: "%.1f MIN", tenths)
    }

    private func repsStepper(label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .wsType(.body, weight: .heavy)
            Spacer()
            WSStepperControl(
                valueText: "\(value.wrappedValue)",
                decrement: { value.wrappedValue = max(1, value.wrappedValue - 1); rebuildPreview() },
                increment: { value.wrappedValue = min(30, value.wrappedValue + 1); rebuildPreview() }
            )
        }
        .padding(.top, 12)
    }

    private func previewSection(_ blueprint: WorkoutBlueprint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PREVIEW")
                .wsType(.metricS, tracking: 1.5)
                .foregroundStyle(WSColor.text40)
                .padding(.top, 18)
            Text(blueprint.title.uppercased())
                .wsType(.control, weight: .heavy)
            Text(blueprint.location.title.uppercased())
                .wsType(.metric)
                .foregroundStyle(WSColor.text50)
            ForEach(blueprint.steps.prefix(4)) { step in
                HStack {
                    Text(step.name)
                    Spacer()
                    Text(stepLabel(step))
                        .wsType(.metric)
                        .foregroundStyle(WSColor.text50)
                }
                .wsType(.body, weight: .bold)
            }
            if blueprint.steps.count > 4 {
                Text("+\(blueprint.steps.count - 4) MORE STEPS")
                    .wsType(.metric)
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
        let input = buildInput()
        do {
            try InstantWorkoutValidation.validate(input)
            preview = try InstantWorkoutBuilder.build(input)
            buildError = nil
        } catch {
            preview = nil
            buildError = error.localizedDescription
        }
    }

    private func buildInput() -> InstantWorkoutBuildInput {
        let meters = Units.meters(fromDisplay: distanceDisplay, unit: store.unit)
        let resolvedMode: InstantTargetMode = kind == .race ? .distance : targetMode
        var request = InstantWorkoutRequest(
            kind: kind,
            location: location,
            targetMode: resolvedMode,
            distanceMeters: resolvedMode == .distance ? meters : nil,
            durationSeconds: resolvedMode == .duration ? durationMinutes * 60 : nil
        )
        switch kind {
        case .tempo:
            break
        case .intervals:
            let warmupMeters = intervalIncludeExtras
                ? Units.meters(fromDisplay: intervalWarmupDisplay, unit: store.unit) : nil
            let cooldownMeters = intervalIncludeExtras
                ? Units.meters(fromDisplay: intervalCooldownDisplay, unit: store.unit) : nil
            request.intervalParams = InstantIntervalParams(
                reps: intervalReps,
                workTarget: .distance(meters: Units.meters(fromDisplay: intervalWorkDisplay, unit: store.unit)),
                recoveryTarget: .distance(meters: Units.meters(fromDisplay: intervalRecoveryDisplay, unit: store.unit)),
                warmupMeters: warmupMeters,
                cooldownMeters: cooldownMeters
            )
        case .walkRun:
            request.walkRunWorkSeconds = walkRunMinutes * 60
            request.walkRunRestSeconds = walkRestMinutes * 60
            request.walkRunReps = walkRunReps
        case .race:
            request.distanceMeters = meters
            request.targetMode = .distance
        default:
            break
        }
        return InstantWorkoutBuildInput(
            request: request,
            tempoWarmupMeters: Units.meters(fromDisplay: tempoWarmupDisplay, unit: store.unit),
            tempoWorkMeters: Units.meters(fromDisplay: tempoWorkDisplay, unit: store.unit),
            tempoCooldownMeters: Units.meters(fromDisplay: tempoCooldownDisplay, unit: store.unit)
        )
    }
}
