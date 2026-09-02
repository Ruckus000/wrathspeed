import SwiftUI
import WrathspeedCore

struct OnboardingView: View {
    @Environment(AppStore.self) private var store

    @State private var step = 0
    @State private var inputs = OnboardingInputs()
    @State private var draft: OnboardingDraft?
    @State private var building = false
    @State private var buildProgress = 0.12
    @State private var validationMessage: String?

    private let totalSteps = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if building {
                buildScreen
            } else {
                formScreen
            }
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 20)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WSColor.bg.ignoresSafeArea())
    }

    private var formScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if step > 0 {
                    WSBackButton(title: "← BACK", accessibilityLabel: "Back") { step -= 1 }
                }
                Spacer()
            }
            if step == 0 {
                WSMark(size: 44, label: nil)
                    .padding(.top, 12)
            }
            WSEyebrow(text: eyebrow)
                .padding(.top, 26)
            Text(headline)
                .wsType(.displayM)
                .foregroundStyle(WSColor.text)
                .lineSpacing(-4)
                .padding(.top, 8)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)

            Group {
                switch step {
                case 0: goalModeStep
                case 1: goalDetailsStep
                case 2: unitStep
                case 3: numbersStep
                case 4: scheduleStep
                case 5: supplementalStep
                default: previewStep
                }
            }
            .padding(.top, 26)

            if let validationMessage {
                Text(validationMessage)
                    .wsType(.metric)
                    .foregroundStyle(WSColor.accent)
                    .padding(.top, 12)
                    .accessibilityLabel(validationMessage)
            }

            Spacer()
            // The app's only health statement people meet without going looking for it. Settings
            // carries the full version; anyone already onboarded has only that route.
            if step == totalSteps - 1 {
                Text("Wrathspeed is a training app, not medical advice. Build up gradually, stop anything that causes sharp pain, and talk to a doctor first if you have a health condition or an injury that is still settling.")
                    .wsType(.caption, weight: .medium)
                    // `text40` is 3.77:1 against `bg`, under the 4.5:1 WCAG AA needs for text
                    // this size. Of everything in the app this is the line least worth making
                    // people squint at. `text50` is 5.33:1.
                    .foregroundStyle(WSColor.text50)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
            }
            WSPrimaryButton(title: primaryButtonTitle) {
                advance()
            }
            .accessibilityIdentifier(primaryButtonTitle)
        }
    }

    private var buildScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            WSMark(size: 44, label: nil)
                .padding(.bottom, 20)
            WSEyebrow(text: "STAND BY")
            Text("BUILDING\nYOUR PLAN")
                .wsType(.displayXL)
                .foregroundStyle(WSColor.text)
                .padding(.top, 10)
            Text(buildSummary)
                .wsType(.metric)
                .foregroundStyle(WSColor.text45)
                .padding(.top, 16)
            WSProgressBar(progress: buildProgress)
                .padding(.top, 26)
            Spacer()
        }
    }

    private var goalModeStep: some View {
        VStack(spacing: 10) {
            ForEach(GoalMode.allCases, id: \.self) { mode in
                WSSelectRow(title: mode.displayName, selected: inputs.goalMode == mode) {
                    inputs.goalMode = mode
                    switch mode {
                    case .race: inputs.goalKind = .halfMarathon
                    case .distance: inputs.goalKind = .tenK
                    case .newToRunning: inputs.goalKind = .newToRunning
                    case .returnToRunning: inputs.goalKind = .returnToRunning
                    }
                    inputs.weekCount = max(inputs.weekCount, inputs.goalKind.minimumWeeks)
                } accessory: { EmptyView() }
            }
        }
    }

    private var goalDetailsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            if inputs.goalMode == .race {
                Text("RACE DISTANCE")
                    .wsType(.body, weight: .heavy)
                VStack(spacing: 8) {
                    ForEach([GoalKind.fiveK, .tenK, .halfMarathon, .marathon], id: \.self) { kind in
                        WSSelectRow(title: kind.displayName, selected: inputs.goalKind == kind) {
                            inputs.goalKind = kind
                            inputs.weekCount = max(inputs.weekCount, kind.minimumWeeks)
                        } accessory: { EmptyView() }
                    }
                }
                DatePicker(
                    "Race date",
                    selection: Binding(
                        get: { inputs.raceDate ?? defaultRaceDate },
                        set: { inputs.raceDate = $0 }
                    ),
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(WSColor.accent)
                .accessibilityLabel("Race date")
            } else if inputs.goalMode == .distance {
                Text("DISTANCE GOAL")
                    .wsType(.body, weight: .heavy)
                VStack(spacing: 8) {
                    ForEach([GoalKind.fiveK, .tenK, .halfMarathon, .marathon], id: \.self) { kind in
                        WSSelectRow(title: kind.displayName, selected: inputs.goalKind == kind) {
                            inputs.goalKind = kind
                            inputs.weekCount = max(inputs.weekCount, kind.minimumWeeks)
                        } accessory: { EmptyView() }
                    }
                }
                stepperRow(
                    "PLAN LENGTH · WKS",
                    text: "\(inputs.weekCount)",
                    down: { inputs.weekCount = max(inputs.goalKind.minimumWeeks, inputs.weekCount - 1) },
                    up: { inputs.weekCount = min(26, inputs.weekCount + 1) }
                )
            } else {
                stepperRow(
                    "PLAN LENGTH · WKS",
                    text: "\(inputs.weekCount)",
                    down: { inputs.weekCount = max(inputs.goalKind.minimumWeeks, inputs.weekCount - 1) },
                    up: { inputs.weekCount = min(26, inputs.weekCount + 1) }
                )
            }
        }
    }

    private var unitStep: some View {
        VStack(spacing: 10) {
            WSSelectRow(title: "Kilometers", selected: inputs.unit == .kilometers) {
                inputs.unit = .kilometers
            } accessory: { EmptyView() }
            WSSelectRow(title: "Miles", selected: inputs.unit == .miles) {
                inputs.unit = .miles
            } accessory: { EmptyView() }
            Text("DISTANCE LABELS AND INPUTS FOLLOW THIS UNIT. WE STORE METERS INTERNALLY.")
                .wsType(.metric)
                .foregroundStyle(WSColor.text40)
                .padding(.top, 8)
        }
    }

    private var numbersStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                ForEach(Ability.allCases, id: \.self) { item in
                    WSChip(title: item.title, selected: inputs.ability == item) { inputs.ability = item }
                }
            }
            stepperRow(
                "WEEKLY \(WSFormat.unitLabel(inputs.unit).uppercased())",
                text: WSFormat.distanceValue(Units.meters(fromDisplay: inputs.weeklyDisplayDistance, unit: inputs.unit), unit: inputs.unit, fraction: 0),
                down: { inputs.weeklyDisplayDistance = max(5, inputs.weeklyDisplayDistance - 1) },
                up: { inputs.weeklyDisplayDistance = min(90, inputs.weeklyDisplayDistance + 1) }
            )
            stepperRow(
                "LONGEST RECENT \(WSFormat.unitLabel(inputs.unit).uppercased())",
                text: WSFormat.distanceValue(Units.meters(fromDisplay: inputs.longestDisplayDistance, unit: inputs.unit), unit: inputs.unit, fraction: 0),
                down: { inputs.longestDisplayDistance = max(2, inputs.longestDisplayDistance - 1) },
                up: { inputs.longestDisplayDistance = min(26, inputs.longestDisplayDistance + 1) }
            )
            Toggle(isOn: $inputs.includesRecentPerformance) {
                Text("ADD RECENT RACE OR PB")
                    .wsType(.body, weight: .heavy)
            }
            .tint(WSColor.accent)
            if inputs.includesRecentPerformance {
                stepperRow(
                    "RACE \(WSFormat.unitLabel(inputs.unit).uppercased())",
                    text: WSFormat.distanceValue(Units.meters(fromDisplay: inputs.recentDistanceDisplay ?? 10, unit: inputs.unit), unit: inputs.unit, fraction: 1),
                    down: {
                        let current = inputs.recentDistanceDisplay ?? 10
                        inputs.recentDistanceDisplay = max(1, current - 0.5)
                    },
                    up: {
                        let current = inputs.recentDistanceDisplay ?? 10
                        inputs.recentDistanceDisplay = min(42, current + 0.5)
                    }
                )
                WSRow {
                    Text("TIME")
                        .wsType(.body, weight: .heavy)
                } trailing: {
                    WSStepperControl(
                        valueText: timeLabel,
                        decrement: { adjustRecentTime(by: -5) },
                        increment: { adjustRecentTime(by: 5) }
                    )
                }
            } else {
                Text("WITHOUT A RECENT RESULT, VDOT COMES FROM ABILITY — LABELED AS AN ESTIMATE IN PREVIEW.")
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text40)
            }
        }
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AVAILABLE RUN DAYS")
                .wsType(.body, weight: .heavy)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    WSChip(title: day.chipLabel, selected: inputs.availableDays.contains(day)) {
                        toggleDay(day)
                    }
                }
            }
            Text("LONG RUN DAY")
                .wsType(.body, weight: .heavy)
                .padding(.top, 8)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(inputs.availableDays.sorted(), id: \.self) { day in
                    WSChip(title: day.chipLabel, selected: inputs.longRunDay == day) {
                        inputs.longRunDay = day
                    }
                }
            }
        }
    }

    private var supplementalStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(isOn: $inputs.strengthEnabled) {
                Text("INCLUDE STRENGTH")
                    .wsType(.body, weight: .heavy)
            }
            .tint(WSColor.accent)
            if inputs.strengthEnabled {
                VStack(spacing: 8) {
                    ForEach(StrengthGoal.allCases, id: \.self) { item in
                        WSSelectRow(title: item.title, selected: inputs.strength.goal == item) {
                            inputs.strength.goal = item
                        } accessory: { EmptyView() }
                    }
                }
                stepperRow(
                    "STRENGTH / WEEK",
                    text: "\(inputs.strength.sessionsPerWeek)",
                    down: { inputs.strength.sessionsPerWeek = max(1, inputs.strength.sessionsPerWeek - 1) },
                    up: { inputs.strength.sessionsPerWeek = min(4, inputs.strength.sessionsPerWeek + 1) }
                )
                // Session length was reachable only from Settings after onboarding finished,
                // so the first plan was always built at the 30-minute default whether or not
                // that suited the person. The allowed values mirror StrengthPreferences,
                // which clamps anything outside [30, 45, 60] back to 30.
                VStack(alignment: .leading, spacing: 10) {
                    Text("SESSION LENGTH")
                        .wsType(.body, weight: .bold)
                        .foregroundStyle(WSColor.text)
                        .accessibilityHidden(true)
                    WSChipRow(spacing: 8) {
                        ForEach([30, 45, 60], id: \.self) { minutes in
                            WSChip(title: "\(minutes) min", selected: inputs.strength.durationMinutes == minutes) {
                                inputs.strength.durationMinutes = minutes
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Session length")
                }
            }
            Toggle(isOn: $inputs.mobility.enabled) {
                Text("INCLUDE MOBILITY")
                    .wsType(.body, weight: .heavy)
            }
            .tint(WSColor.accent)
            if inputs.mobility.enabled {
                stepperRow(
                    "MOBILITY / WEEK",
                    text: "\(inputs.mobility.sessionsPerWeek)",
                    down: { inputs.mobility.sessionsPerWeek = max(1, inputs.mobility.sessionsPerWeek - 1) },
                    up: { inputs.mobility.sessionsPerWeek = min(3, inputs.mobility.sessionsPerWeek + 1) }
                )
            }
        }
    }

    private var previewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let draft {
                Text("FIRST WEEK")
                    .wsType(.body, weight: .heavy)
                ForEach(firstWeekWorkouts(draft)) { workout in
                    WSRow {
                        // Kept together so the stacked arrangement does not break this
                        // group onto separate lines of its own.
                        HStack(spacing: 10) {
                            Text(WSFormat.weekdayDate(workout.date))
                                .wsType(.metric)
                                .foregroundStyle(WSColor.text45)
                                .frame(width: 92, alignment: .leading)
                            Text(workout.blueprint.title.uppercased())
                                .wsType(.body, weight: .heavy)
                        }
                    } trailing: {
                        Text(WSFormat.distance(workout.blueprint.plannedDistanceMeters, unit: inputs.unit, fraction: 0))
                            .wsType(.metric)
                            .foregroundStyle(WSColor.text45)
                    }
                }
                Text("STARTING WEEKLY \(WSFormat.distance(weeklyMileage(draft), unit: inputs.unit)) · \(draft.plan.goal.weekCount) WEEKS")
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text45)
                    .padding(.top, 6)
                if let easy = draft.zones.secondsPerKilometer(for: .easy) {
                    Text("EASY PACE \(WSFormat.pace(easy, unit: inputs.unit)) · VDOT \(WSFormat.vdot(draft.plan.profile.vdot)) (\(vdotLabel(draft)))")
                        .wsType(.metric)
                        .foregroundStyle(WSColor.text45)
                }
            } else {
                Text("BUILD A DRAFT TO PREVIEW YOUR FIRST WEEK.")
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text45)
            }
        }
    }

    private func stepperRow(_ title: String, text: String, down: @escaping () -> Void, up: @escaping () -> Void) -> some View {
        WSRow {
            Text(title)
                .wsType(.body, weight: .heavy)
        } trailing: {
            WSStepperControl(valueText: text, decrement: down, increment: up)
        }
    }

    private var eyebrow: String { "STEP \(step + 1)/\(totalSteps) — \(stepTitle.uppercased())" }
    private var stepTitle: String {
        switch step {
        case 0: "Goal"
        case 1: "Details"
        case 2: "Units"
        case 3: "Fitness"
        case 4: "Schedule"
        case 5: "Support"
        default: "Preview"
        }
    }

    private var headline: String {
        switch step {
        case 0: "WHAT ARE WE\nCHASING?"
        case 1: "LOCK IN THE\nDETAILS."
        case 2: "PICK YOUR\nDISTANCE UNIT."
        case 3: "HOW FIT ARE\nYOU TODAY?"
        case 4: "WHEN CAN YOU\nRUN?"
        case 5: "STRENGTH +\nMOBILITY?"
        default: "REVIEW YOUR\nDRAFT PLAN."
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case totalSteps - 1: "CONFIRM PLAN →"
        case 5: "BUILD DRAFT →"
        default: "NEXT →"
        }
    }

    private var buildSummary: String {
        "\(inputs.weekCount) WEEKS · \(inputs.goalKind.displayName.uppercased()) · \(inputs.availableDays.count) RUNS / WK"
    }

    private var defaultRaceDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: inputs.goalKind.minimumWeeks, to: Date()) ?? Date()
    }

    private var timeLabel: String {
        let minutes = inputs.recentDurationMinutes ?? 45
        let seconds = inputs.recentDurationSeconds ?? 0
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func adjustRecentTime(by seconds: Int) {
        var total = (inputs.recentDurationMinutes ?? 45) * 60 + (inputs.recentDurationSeconds ?? 0)
        total = max(60, total + seconds)
        inputs.recentDurationMinutes = total / 60
        inputs.recentDurationSeconds = total % 60
        if inputs.recentDistanceDisplay == nil { inputs.recentDistanceDisplay = 10 }
    }

    private func toggleDay(_ day: Weekday) {
        if inputs.availableDays.contains(day) {
            guard inputs.availableDays.count > 3 else { return }
            inputs.availableDays.remove(day)
            if inputs.longRunDay == day {
                inputs.longRunDay = inputs.availableDays.sorted().last ?? .saturday
            }
        } else {
            inputs.availableDays.insert(day)
        }
    }

    private func advance() {
        validationMessage = nil
        if step < 5 {
            if let error = validateCurrentStep() {
                validationMessage = error
                return
            }
            normalizeDraftInputs()
            step += 1
            return
        }
        if step == 5 {
            do {
                normalizeDraftInputs()
                try OnboardingValidator.validate(inputs)
                building = true
                withAnimation(.linear(duration: 1.2)) { buildProgress = 1 }
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    do {
                        let built = try store.generateOnboardingDraft(from: inputs)
                        draft = built
                        building = false
                        step += 1
                    } catch {
                        building = false
                        validationMessage = error.localizedDescription
                    }
                }
            } catch {
                validationMessage = error.localizedDescription
            }
            return
        }
        guard let draft else {
            validationMessage = "Build a draft plan first."
            return
        }
        store.confirmOnboarding(draft: draft)
    }

    private func validateCurrentStep() -> String? {
        switch step {
        case 1:
            normalizeDraftInputs()
        case 4:
            if inputs.availableDays.count < 3 { return OnboardingValidationError.tooFewAvailableDays.errorDescription }
            if !inputs.availableDays.contains(inputs.longRunDay) { return OnboardingValidationError.longRunNotAvailable.errorDescription }
        default: break
        }
        return nil
    }

    private func normalizeDraftInputs() {
        if inputs.goalMode == .race && inputs.raceDate == nil {
            inputs.raceDate = defaultRaceDate
        }
    }

    private func firstWeekWorkouts(_ draft: OnboardingDraft) -> [ScheduledWorkout] {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        return draft.plan.workouts.filter { $0.date >= start && $0.date < end }
    }

    private func weeklyMileage(_ draft: OnboardingDraft) -> Double {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        return draft.plan.workouts
            .filter { $0.date >= start && $0.date < end && $0.blueprint.kind.isRunning }
            .reduce(0) { $0 + $1.blueprint.plannedDistanceMeters }
    }

    private func vdotLabel(_ draft: OnboardingDraft) -> String {
        draft.vdotSource == .recentPerformance ? "FROM RECENT RESULT" : "ABILITY ESTIMATE"
    }
}
