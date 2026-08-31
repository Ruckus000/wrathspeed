import HealthKit
import SwiftUI
import WrathspeedCore

struct StrengthPlayerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let session: StrengthSession
    @State private var resultID = UUID()
    @State private var index = 0
    @State private var setIndex = 0
    @State private var remaining = 45
    @State private var running = false
    @State private var finished = false
    @State private var startedAt = Date()
    @State private var logs: [StrengthSetLog] = []
    @State private var reps = 8
    @State private var loadValue = 0.0
    @State private var loadUnit = "kg"
    @State private var note = ""
    @State private var substitutionExerciseID: String?
    @State private var difficultyRPE = 7
    @State private var healthSync = HealthSyncMetadata(state: .notRequired)
    @State private var showAbout = false
    @State private var catalog: StrengthCatalog?
    /// Which half of a set the screen is showing. The redesign splits what used to be one
    /// dense scroll into doing the set, then resting after it.
    @State private var stage: Stage = .active
    /// Deliberately separate from `remaining`/`running`, which stay the rest timer and are
    /// what `progress.restRemainingSeconds` persists. Sharing them would let a hold value be
    /// restored as rest.
    @State private var holdRemaining = 0
    @State private var holdRunning = false

    enum Stage {
        case active
        case rest
    }
    private let speech = SpeechCuePlayer()

    var body: some View {
        // Scrollable: this screen already overflowed a small phone before the demo loop
        // was added, which pushed COMPLETE SET off the bottom entirely.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if finished {
                    finishView
                } else if let current {
                    switch stage {
                    case .active: activeView(current)
                    case .rest: restView(current)
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(WSColor.bg.ignoresSafeArea())
        .onAppear {
            catalog = try? StrengthCatalogLoader.load()
            restoreOrStart()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            switch stage {
            case .active:
                guard holdRunning, holdRemaining > 0 else { return }
                holdRemaining -= 1
                if holdRemaining == 0 {
                    holdRunning = false
                    completeSet()
                }
            case .rest:
                guard running, remaining > 0 else { return }
                remaining -= 1
                if remaining == 0 {
                    running = false
                    endRest()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                persistProgressIfNeeded(force: true)
            }
        }
        .overlay {
            if let message = store.errorMessage {
                WSAlert(message: message) { store.errorMessage = nil }
            }
        }
        .sheet(isPresented: $showAbout) {
            if let current {
                ExerciseAboutView(
                    exerciseName: displayedExerciseName(for: current),
                    cue: displayedCue(for: current),
                    symbolName: displayedSymbolName(for: current),
                    movementID: displayedExerciseID(for: current)
                )
            }
        }
    }

    private var header: some View {
        WSRow(alignment: .firstTextBaseline) {
            Text("\(session.title.uppercased()) · \(session.durationMinutes) MIN")
                .wsType(.label, weight: .bold, tracking: 2)
                .foregroundStyle(WSColor.text50)
        } trailing: {
            Button("FINISH") { finishSession() }
                .wsType(.label, weight: .heavy)
                .foregroundStyle(WSColor.accent)
                .frame(minHeight: 44)
                .accessibilityLabel("Finish strength session")
            Button("✕") {
                do {
                    try persistProgress(force: true)
                    dismiss()
                } catch {}
            }
            .wsType(.label, weight: .heavy)
            .foregroundStyle(WSColor.text40)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 8)
    }

    private func activeView(_ current: StrengthSet) -> some View {
        let exercise = displayedExercise(for: current)
        return Group {
            WSRow {
                Button("← PREVIOUS") { goPrevious() }
                    .wsType(.label, weight: .heavy)
                    .foregroundStyle(canGoPrevious ? WSColor.text50 : WSColor.text35)
                    .disabled(!canGoPrevious)
                    .frame(minHeight: 44)
                    .accessibilityLabel(canGoPrevious ? "Previous" : "Previous, unavailable")
                    .accessibilityHint(canGoPrevious ? "" : "At the first exercise")
            } trailing: {
                Button("NEXT →") { goNext() }
                    .wsType(.label, weight: .heavy)
                    .foregroundStyle(canGoNext ? WSColor.text50 : WSColor.text35)
                    .disabled(!canGoNext)
                    .frame(minHeight: 44)
                    .accessibilityLabel(canGoNext ? "Next" : "Next, unavailable")
                    .accessibilityHint(canGoNext ? "" : "At the last exercise")
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(index + 1)/\(session.sets.count)")
                    .wsType(.metric)
                    .foregroundStyle(WSColor.accent)
                Text("SET \(setIndex + 1) OF \(current.sets)")
                    .wsType(.label, weight: .heavy, tracking: 1.5)
                    .foregroundStyle(WSColor.text45)
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Exercise \(index + 1) of \(session.sets.count), set \(setIndex + 1) of \(current.sets)")

            Text(displayedExerciseName(for: current).uppercased())
                .wsType(.displayM)
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)

            MovementMediaView(
                movementID: displayedExerciseID(for: current),
                symbolName: displayedSymbolName(for: current),
                height: 180
            )
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 10)

            // The one thing you act on, in its own card. Reps and holds are genuinely
            // different jobs -- one you count, one you outlast -- so they get different
            // cards rather than a rep stepper that means nothing for a plank.
            if let seconds = exercise?.holdSeconds {
                holdCard(seconds: seconds)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 14)
            } else {
                repsCard(current)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 14)
            }

            Text(displayedCue(for: current))
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text50)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)

            if let exercise {
                WSInstructionCard(exercise)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 14)
            }

            Button("ABOUT THIS EXERCISE") { showAbout = true }
                .wsType(.label, weight: .heavy)
                .foregroundStyle(WSColor.text45)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 10)
                .frame(minHeight: 44, alignment: .leading)

            Button("SKIP SET") { logCurrent(skipped: true); advanceSet() }
                .wsType(.label, weight: .heavy)
                .foregroundStyle(WSColor.destructive)
                .padding(.horizontal, WSSpace.gutter)
                .frame(minHeight: 44, alignment: .leading)

            progressDots
                .padding(.top, 16)
                .padding(.bottom, 40)
        }
    }

    private func repsCard(_ current: StrengthSet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("REPS")
                .wsType(.metricS, tracking: 1.5)
                .foregroundStyle(WSColor.accent)
            Text("\(reps) REPS")
                .wsType(.displayS)
                .foregroundStyle(WSColor.text)
                .padding(.top, 8)
            Text("There is no timer for this one. Do the reps at your own speed, then tap done.")
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text70)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            WSPrimaryButton(title: "SET DONE", height: 56, role: .control) {
                completeSet()
            }
            .padding(.top, 16)
            .accessibilityIdentifier("strength_set_done")
        }
        .wsCard(accent: true)
    }

    private func holdCard(seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HOLD")
                .wsType(.metricS, tracking: 1.5)
                .foregroundStyle(WSColor.accent)
            Text("\(holdRemaining)")
                .wsType(.displayXL)
                .foregroundStyle(WSColor.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .accessibilityLabel("\(holdRemaining) seconds left")
            Text("SECONDS LEFT")
                .wsType(.label, weight: .bold, tracking: 3)
                .foregroundStyle(WSColor.text45)
                .frame(maxWidth: .infinity)
            WSPrimaryButton(title: holdRunning ? "PAUSE" : (holdRemaining == seconds ? "START HOLD" : "RESUME"), height: 56, role: .control) {
                holdRunning.toggle()
                persistProgressIfNeeded(force: true)
            }
            .padding(.top, 16)
            .accessibilityIdentifier("strength_hold_toggle")
            Button("DONE EARLY") { completeSet() }
                .wsType(.label, weight: .heavy)
                .foregroundStyle(WSColor.text45)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .wsCard(accent: true)
    }

    /// One dot per exercise, not per set -- a session of seven exercises at three sets each
    /// would otherwise be twenty-one dots, which reads as noise rather than progress.
    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(session.sets.indices, id: \.self) { position in
                Circle()
                    .fill(position == index ? WSColor.accent : (position < index ? WSColor.accent.opacity(0.35) : WSColor.surface1))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func restView(_ current: StrengthSet) -> some View {
        Group {
            Text("REST")
                .wsType(.label, weight: .heavy, tracking: 3)
                .foregroundStyle(WSColor.text45)
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
            Text("\(remaining)")
                .wsType(.hero)
                .foregroundStyle(WSColor.accent)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Rest, \(remaining) seconds remaining")
            Text("SECONDS")
                .wsType(.label, weight: .bold, tracking: 3)
                .foregroundStyle(WSColor.text40)
                .frame(maxWidth: .infinity)
            Text("Catch your breath. Resting properly is what makes the next set count.")
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text50)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.top, 18)
            Text(nextUpLabel)
                .wsType(.metric, weight: .bold)
                .foregroundStyle(WSColor.accent)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 18)

            // Logging lives here rather than on the active screen: you are standing still
            // for a minute anyway, and the set you are recording is the one you just did.
            loggingControls(current)
                .padding(.top, 26)

            WSPrimaryButton(title: "SKIP REST", height: 56, role: .control) {
                endRest()
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 20)
            .padding(.bottom, 48)
            .accessibilityIdentifier("strength_skip_rest")
        }
    }

    @ViewBuilder
    private func loggingControls(_ current: StrengthSet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LOG THIS SET")
                .wsType(.metricS, tracking: 1.5)
                .foregroundStyle(WSColor.accent)
            WSRow {
                Text("REPS")
                    .wsType(.label, weight: .heavy)
            } trailing: {
                WSStepperControl(
                    valueText: "\(reps)",
                    decrement: { reps = max(1, reps - 1); persistProgressIfNeeded(force: true) },
                    increment: { reps += 1; persistProgressIfNeeded(force: true) }
                )
            }
            .padding(.top, 12)
            WSRow {
                Text("LOAD")
                    .wsType(.label, weight: .heavy)
            } trailing: {
                WSChipRow {
                    WSChip(title: "KG", selected: loadUnit == "kg") { applyLoadUnit("kg") }
                    WSChip(title: "LB", selected: loadUnit == "lb") { applyLoadUnit("lb") }
                }
            }
            .padding(.top, 10)
            HStack {
                Spacer()
                WSStepperControl(
                    valueText: String(format: "%.0f %@", loadValue, loadUnit.uppercased()),
                    decrement: { loadValue = max(0, loadValue - 2.5); persistProgressIfNeeded(force: true) },
                    increment: { loadValue += 2.5; persistProgressIfNeeded(force: true) }
                )
            }
            .padding(.top, 8)
            if !substitutionOptions(for: current).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SUBSTITUTION")
                        .wsType(.label, weight: .heavy)
                    Picker("Substitution", selection: substitutionBinding) {
                        Text("Original").tag(Optional<String>.none)
                        ForEach(substitutionOptions(for: current)) { exercise in
                            Text(exercise.name).tag(Optional(exercise.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(WSColor.accent)
                }
                .padding(.top, 12)
            }
            TextField("Optional note", text: $note)
                .wsType(.body)
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(WSColor.surface1, in: RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous))
                .padding(.top, 10)
                .onChange(of: note) { _, _ in persistProgressIfNeeded(force: true) }
        }
        .padding(.horizontal, WSSpace.gutter)
    }

    private var nextUpLabel: String {
        guard let current else { return "" }
        if setIndex + 1 < current.sets {
            return "NEXT: \(displayedExerciseName(for: current).uppercased()) · SET \(setIndex + 2) OF \(current.sets)"
        }
        let nextIndex = index + 1
        guard session.sets.indices.contains(nextIndex) else { return "LAST SET DONE" }
        return "NEXT: \(session.sets[nextIndex].exercise.name.uppercased())"
    }

    private var finishView: some View {
        Group {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                WSEyebrow(text: "SESSION COMPLETE")
                Text("STRONGER.")
                    .wsType(.displayXL)
                    .foregroundStyle(WSColor.text)
                Text("\(logs.filter(\.completed).count) SETS LOGGED")
                    .wsType(.body, weight: .semibold)
                    .foregroundStyle(Color.white.opacity(0.6))
                WSRow {
                    Text("DIFFICULTY")
                        .wsType(.label, weight: .heavy)
                } trailing: {
                    WSStepperControl(
                        valueText: "RPE \(difficultyRPE)",
                        decrement: { difficultyRPE = max(1, difficultyRPE - 1); try? persistCompleted(force: true) },
                        increment: { difficultyRPE = min(10, difficultyRPE + 1); try? persistCompleted(force: true) }
                    )
                }
                .padding(.top, 8)
                if healthSync.state == .failed {
                    Text(healthSync.failureMessage ?? "Health save failed")
                        .wsType(.metric)
                        .foregroundStyle(WSColor.destructive)
                }
            }
            .padding(.horizontal, WSSpace.gutter)
            Spacer()
            WSPrimaryButton(title: healthSync.state == .synced ? "SAVED TO HEALTH ✓" : "SAVE TO HEALTH", height: 58, role: .control) {
                Task { await saveToHealth() }
            }
            .disabled(healthSync.state == .synced)
            .padding(.horizontal, WSSpace.gutter)
            WSOutlineButton(title: "DONE") {
                dismiss()
            }
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
                .padding(.bottom, 56)
        }
    }

    private var substitutionBinding: Binding<String?> {
        Binding(
            get: { substitutionExerciseID },
            set: { newValue in
                substitutionExerciseID = newValue
                persistProgressIfNeeded(force: true)
            }
        )
    }

    private var current: StrengthSet? {
        session.sets.indices.contains(index) ? session.sets[index] : nil
    }

    private var canGoPrevious: Bool {
        logIndex > 0
    }

    private var canGoNext: Bool {
        logIndex + 1 < logs.count
    }

    private var logIndex: Int {
        session.sets.prefix(index).reduce(0) { $0 + $1.sets } + setIndex
    }

    private func restoreOrStart() {
        if let existing = GuidedSessionPolicy.inProgressStrength(sessionID: session.id, in: store.guidedStrengthResults) {
            resultID = existing.id
            startedAt = existing.startedAt
            logs = existing.setLogs
            healthSync = existing.healthSync
            difficultyRPE = existing.difficultyRPE ?? 7
            if let progress = existing.progress {
                index = progress.exerciseIndex
                setIndex = progress.setIndex
                remaining = progress.restRemainingSeconds
                running = progress.restRunning
                reps = progress.currentReps
                loadValue = progress.currentLoadValue
                loadUnit = progress.currentLoadUnit
                note = progress.currentNote
                substitutionExerciseID = progress.currentSubstitutionExerciseID
                // This branch sets every field by hand instead of going through
                // `syncControlsFromCurrentSet`, so the hold has to be armed here too --
                // otherwise resuming on a plank shows a hold card counting from zero, with a
                // button the timer's `holdRemaining > 0` guard will never let run.
                stage = .active
                holdRunning = false
                holdRemaining = current.flatMap { displayedExercise(for: $0)?.holdSeconds } ?? 0
                // Progress persists the rest timer, but a restore always lands on the active
                // stage, so a restored `running` would tick nothing.
                running = false
            } else {
                syncControlsFromCurrentSet()
            }
            return
        }
        startedAt = Date()
        resultID = UUID()
        logs = session.sets.flatMap { set in
            (0..<set.sets).map { _ in
                StrengthSetLog(exerciseID: set.exercise.id, completed: false)
            }
        }
        syncControlsFromCurrentSet()
        persistProgressIfNeeded(force: true)
    }

    private func syncControlsFromCurrentSet() {
        guard let current else { return }
        stage = .active
        holdRunning = false
        holdRemaining = displayedExercise(for: current)?.holdSeconds ?? 0
        if logs.indices.contains(logIndex), logs[logIndex].completed || logs[logIndex].skipped {
            reps = logs[logIndex].reps ?? current.reps
            loadValue = logs[logIndex].loadValue ?? 0
            loadUnit = logs[logIndex].loadUnit ?? defaultLoadUnit
            note = logs[logIndex].note ?? ""
            substitutionExerciseID = logs[logIndex].substitutionExerciseID
        } else {
            reps = current.reps
            loadValue = 0
            loadUnit = defaultLoadUnit
            note = ""
            substitutionExerciseID = nil
            remaining = current.restSeconds
        }
    }

    private func displayedExerciseName(for set: StrengthSet) -> String {
        if let substitutionExerciseID,
           let exercise = catalog?.exercises.first(where: { $0.id == substitutionExerciseID }) {
            return exercise.name
        }
        return set.exercise.name
    }

    /// The id the demo clip is keyed on. Follows a substitution so the loop always shows
    /// the exercise actually being performed.
    private func displayedExerciseID(for set: StrengthSet) -> String {
        if let substitutionExerciseID,
           let exercise = catalog?.exercises.first(where: { $0.id == substitutionExerciseID }) {
            return exercise.id
        }
        return set.exercise.id
    }

    private func displayedSymbolName(for set: StrengthSet) -> String {
        if let substitutionExerciseID,
           let exercise = catalog?.exercises.first(where: { $0.id == substitutionExerciseID }) {
            return exercise.symbolName
        }
        return set.exercise.symbolName
    }

    /// The exercise actually being performed, following a substitution. `holdSeconds` and the
    /// instruction copy both hang off this, so a substituted movement shows its own.
    private func displayedExercise(for set: StrengthSet) -> StrengthExercise? {
        if let substitutionExerciseID,
           let exercise = catalog?.exercises.first(where: { $0.id == substitutionExerciseID }) {
            return exercise
        }
        // The session carries its own copy, which predates the instruction fields; prefer the
        // catalog so a rebuilt catalog reaches sessions already on disk.
        return catalog?.exercises.first { $0.id == set.exercise.id } ?? set.exercise
    }

    private func displayedCue(for set: StrengthSet) -> String {
        if let substitutionExerciseID,
           let exercise = catalog?.exercises.first(where: { $0.id == substitutionExerciseID }) {
            return exercise.cue
        }
        return set.exercise.cue
    }

    private func substitutionOptions(for set: StrengthSet) -> [StrengthExercise] {
        guard let catalog else { return [] }
        return catalog.exercises.filter { exercise in
            exercise.id != set.exercise.id
                && !Set(exercise.focus).isDisjoint(with: Set(set.exercise.focus))
        }
    }

    private func goPrevious() {
        guard canGoPrevious else { return }
        running = false
        if setIndex > 0 {
            setIndex -= 1
        } else {
            index -= 1
            setIndex = max(session.sets[index].sets - 1, 0)
        }
        syncControlsFromCurrentSet()
        persistProgressIfNeeded(force: true)
    }

    private func goNext() {
        guard canGoNext else { return }
        running = false
        if setIndex + 1 < (current?.sets ?? 1) {
            setIndex += 1
        } else {
            index += 1
            setIndex = 0
        }
        syncControlsFromCurrentSet()
        persistProgressIfNeeded(force: true)
    }

    /// Finish the set being performed and go and rest. The log is not written here -- the
    /// rest screen is where reps and load get edited, so it is written when rest ends and the
    /// numbers are final. `index`/`setIndex` still point at this set throughout, which is what
    /// keeps `logIndex` correct.
    private func completeSet() {
        guard let current else { return }
        holdRunning = false
        // No rest after the last set of the session -- there is nothing to come back for.
        let isLastSet = setIndex + 1 >= current.sets && index + 1 >= session.sets.count
        if isLastSet {
            logCurrent(skipped: false)
            advanceSet()
            return
        }
        remaining = current.restSeconds
        running = true
        stage = .rest
        persistProgressIfNeeded(force: true)
    }

    private func endRest() {
        running = false
        stage = .active
        logCurrent(skipped: false)
        advanceSet()
    }

    private func logCurrent(skipped: Bool) {
        guard logs.indices.contains(logIndex) else { return }
        logs[logIndex].completed = !skipped
        logs[logIndex].skipped = skipped
        logs[logIndex].reps = reps
        logs[logIndex].loadValue = loadValue > 0 ? loadValue : nil
        logs[logIndex].loadUnit = loadUnit
        logs[logIndex].note = note.isEmpty ? nil : note
        logs[logIndex].substitutionExerciseID = substitutionExerciseID
        persistProgressIfNeeded(force: true)
    }

    private func advanceSet() {
        guard let current else { return }
        running = false
        if setIndex + 1 < current.sets {
            setIndex += 1
            syncControlsFromCurrentSet()
            persistProgressIfNeeded(force: true)
            return
        }
        setIndex = 0
        index += 1
        if let next = self.current {
            reps = next.reps
            remaining = next.restSeconds
            note = ""
            substitutionExerciseID = nil
            stage = .active
            holdRunning = false
            holdRemaining = displayedExercise(for: next)?.holdSeconds ?? 0
            speech.speak(.stepStarted(next.exercise.name))
            persistProgressIfNeeded(force: true)
        } else {
            finishSession()
        }
    }

    private func finishSession() {
        running = false
        do {
            try persistCompleted()
            finished = true
        } catch {
            finished = false
        }
    }

    private var defaultLoadUnit: String {
        store.unit == .miles ? "lb" : "kg"
    }

    private func applyLoadUnit(_ newUnit: String) {
        guard newUnit != loadUnit else { return }
        if loadValue > 0 {
            loadValue = Self.convertLoad(loadValue, from: loadUnit, to: newUnit)
        }
        loadUnit = newUnit
        persistProgressIfNeeded(force: true)
    }

    private static func convertLoad(_ value: Double, from: String, to: String) -> Double {
        let kilograms: Double = from == "lb" ? value * 0.45359237 : value
        let converted = to == "lb" ? kilograms / 0.45359237 : kilograms
        return (converted * 2).rounded() / 2
    }

    private func persistProgressIfNeeded(force: Bool = false) {
        guard !finished else { return }
        do {
            try persistProgress(force: force)
        } catch {}
    }

    private func persistProgress(force: Bool) throws {
        guard force else { return }
        try persistLocalResult(completed: false)
    }

    private func persistCompleted(force: Bool = false) throws {
        _ = force
        try persistLocalResult(completed: true)
    }

    private func persistLocalResult(completed: Bool) throws {
        let progress = completed ? nil : StrengthSessionProgress(
            exerciseIndex: index,
            setIndex: setIndex,
            restRemainingSeconds: remaining,
            restRunning: running,
            currentReps: reps,
            currentLoadValue: loadValue,
            currentLoadUnit: loadUnit,
            currentNote: note,
            currentSubstitutionExerciseID: substitutionExerciseID
        )
        let result = StrengthSessionResult(
            id: resultID,
            sessionID: session.id,
            startedAt: startedAt,
            endedAt: Date(),
            setLogs: logs,
            difficultyRPE: completed ? difficultyRPE : nil,
            healthSync: healthSync,
            lifecycle: completed ? .completed : .inProgress,
            progress: progress
        )
        try store.recordStrengthResult(result)
    }

    private func saveToHealth() async {
        healthSync = HealthSyncMetadata(state: .pending, lastAttemptAt: Date())
        do { try persistCompleted() } catch { return }
        let hk = HKHealthStore()
        let end = Date()
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: hk, configuration: configuration, device: .local())
        do {
            try await hk.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            try await builder.beginCollection(at: startedAt)
            try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else {
                throw HKError(.errorHealthDataUnavailable)
            }
            healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: workout.uuid)
        } catch {
            healthSync = HealthSyncMetadata(state: .failed, failureMessage: error.localizedDescription, lastAttemptAt: end)
        }
        do { try persistCompleted() } catch {}
    }
}
