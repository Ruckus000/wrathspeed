import HealthKit
import SwiftUI
import WrathspeedCore

struct StrengthPlayerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
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
    private let speech = SpeechCuePlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if finished {
                finishView
            } else if let current {
                activeView(current)
            }
        }
        .background(WSColor.bg.ignoresSafeArea())
        .onAppear {
            catalog = try? StrengthCatalogLoader.load()
            restoreOrStart()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard running, remaining > 0 else { return }
            remaining -= 1
            if remaining == 0 {
                running = false
            }
            persistProgressIfNeeded()
        }
        .sheet(isPresented: $showAbout) {
            if let current {
                ExerciseAboutView(
                    exerciseName: displayedExerciseName(for: current),
                    cue: displayedCue(for: current),
                    symbolName: "figure.strengthtraining.traditional"
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(session.title.uppercased()) · \(session.durationMinutes) MIN")
                .font(WSFont.ui(12, weight: .bold))
                .tracking(2)
                .foregroundStyle(WSColor.text50)
            Spacer()
            Button("FINISH") { finishSession() }
                .font(WSFont.ui(11, weight: .heavy))
                .foregroundStyle(WSColor.accent)
                .frame(minHeight: 44)
                .accessibilityLabel("Finish strength session")
            Button("✕") {
                persistProgressIfNeeded(force: true)
                dismiss()
            }
            .font(WSFont.ui(12, weight: .heavy))
            .foregroundStyle(WSColor.text40)
            .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 8)
    }

    private func activeView(_ current: StrengthSet) -> some View {
        Group {
            HStack {
                Button("← PREVIOUS") { goPrevious() }
                    .font(WSFont.ui(11, weight: .heavy))
                    .foregroundStyle(canGoPrevious ? WSColor.text50 : WSColor.text35)
                    .disabled(!canGoPrevious)
                    .frame(minHeight: 44)
                Spacer()
                Button("NEXT →") { goNext() }
                    .font(WSFont.ui(11, weight: .heavy))
                    .foregroundStyle(canGoNext ? WSColor.text50 : WSColor.text35)
                    .disabled(!canGoNext)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)
            Text("EXERCISE \(index + 1) / \(session.sets.count) · SET \(setIndex + 1)/\(current.sets)")
                .font(WSFont.mono(11))
                .foregroundStyle(WSColor.accent)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
            Text(displayedExerciseName(for: current).uppercased())
                .font(WSFont.display(42))
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
            Button("ABOUT THIS EXERCISE") { showAbout = true }
                .font(WSFont.ui(11, weight: .heavy))
                .foregroundStyle(WSColor.text45)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 8)
                .frame(minHeight: 44, alignment: .leading)
            if !substitutionOptions(for: current).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SUBSTITUTION")
                        .font(WSFont.ui(12, weight: .heavy))
                    Picker("Substitution", selection: substitutionBinding) {
                        Text("Original").tag(Optional<String>.none)
                        ForEach(substitutionOptions(for: current)) { exercise in
                            Text(exercise.name).tag(Optional(exercise.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(WSColor.accent)
                }
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 8)
            }
            HStack {
                Text("REPS")
                    .font(WSFont.ui(12, weight: .heavy))
                Spacer()
                WSStepperControl(
                    valueText: "\(reps)",
                    decrement: { reps = max(1, reps - 1); persistProgressIfNeeded(force: true) },
                    increment: { reps += 1; persistProgressIfNeeded(force: true) }
                )
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 12)
            HStack {
                Text("LOAD")
                    .font(WSFont.ui(12, weight: .heavy))
                Spacer()
                WSStepperControl(
                    valueText: String(format: "%.0f %@", loadValue, loadUnit),
                    decrement: { loadValue = max(0, loadValue - 2.5); persistProgressIfNeeded(force: true) },
                    increment: { loadValue += 2.5; persistProgressIfNeeded(force: true) }
                )
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)
            TextField("Optional note", text: $note)
                .font(WSFont.ui(14))
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(WSColor.surface1, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 8)
                .onChange(of: note) { _, _ in persistProgressIfNeeded(force: true) }
            HStack {
                Text("REST")
                    .font(WSFont.ui(12, weight: .heavy))
                Spacer()
                WSStepperControl(
                    valueText: "\(remaining)s",
                    decrement: { remaining = max(0, remaining - 5); persistProgressIfNeeded(force: true) },
                    increment: { remaining += 5; persistProgressIfNeeded(force: true) }
                )
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)
            Text("\(remaining)")
                .font(WSFont.display(100))
                .foregroundStyle(WSColor.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .accessibilityLabel("Rest timer \(remaining) seconds")
            Text("REST SECONDS")
                .font(WSFont.ui(12, weight: .bold))
                .foregroundStyle(WSColor.text50)
                .frame(maxWidth: .infinity)
            Spacer()
            HStack(spacing: 10) {
                WSPrimaryButton(title: running ? "PAUSE REST" : "START REST", height: 58, fontSize: 18) {
                    running.toggle()
                    if running { speech.speak(.stepStarted(displayedExerciseName(for: current))) }
                    persistProgressIfNeeded(force: true)
                }
                Button("SKIP SET") { logCurrent(skipped: true); advanceSet() }
                    .font(WSFont.ui(12, weight: .heavy))
                    .foregroundStyle(WSColor.destructive)
                    .frame(width: 110, height: 58)
            }
            .padding(.horizontal, WSSpace.gutter)
            WSPrimaryButton(title: "COMPLETE SET", height: 54, fontSize: 18) {
                logCurrent(skipped: false)
                advanceSet()
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 10)
            .padding(.bottom, 56)
        }
    }

    private var finishView: some View {
        Group {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                WSEyebrow(text: "SESSION COMPLETE")
                Text("STRONGER.")
                    .font(WSFont.display(64))
                    .foregroundStyle(WSColor.text)
                Text("\(logs.filter(\.completed).count) SETS LOGGED")
                    .font(WSFont.ui(13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                HStack {
                    Text("DIFFICULTY")
                        .font(WSFont.ui(12, weight: .heavy))
                    Spacer()
                    WSStepperControl(
                        valueText: "RPE \(difficultyRPE)",
                        decrement: { difficultyRPE = max(1, difficultyRPE - 1); try? persistCompleted(force: true) },
                        increment: { difficultyRPE = min(10, difficultyRPE + 1); try? persistCompleted(force: true) }
                    )
                }
                .padding(.top, 8)
                if healthSync.state == .failed {
                    Text(healthSync.failureMessage ?? "Health save failed")
                        .font(WSFont.mono(12))
                        .foregroundStyle(WSColor.destructive)
                }
            }
            .padding(.horizontal, WSSpace.gutter)
            Spacer()
            WSPrimaryButton(title: healthSync.state == .synced ? "SAVED TO HEALTH ✓" : "SAVE TO HEALTH", height: 58, fontSize: 20) {
                Task { await saveToHealth() }
            }
            .disabled(healthSync.state == .synced)
            .padding(.horizontal, WSSpace.gutter)
            WSOutlineButton(title: "DONE") { dismiss() }
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
        if let existing = GuidedSessionPolicy.inProgressStrength(sessionID: session.id, in: store.strengthResults) {
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
        if logs.indices.contains(logIndex), logs[logIndex].completed || logs[logIndex].skipped {
            reps = logs[logIndex].reps ?? current.reps
            loadValue = logs[logIndex].loadValue ?? 0
            loadUnit = logs[logIndex].loadUnit ?? "kg"
            note = logs[logIndex].note ?? ""
            substitutionExerciseID = logs[logIndex].substitutionExerciseID
        } else {
            reps = current.reps
            loadValue = 0
            loadUnit = "kg"
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

    private func logCurrent(skipped: Bool) {
        guard logs.indices.contains(logIndex) else { return }
        logs[logIndex].completed = !skipped
        logs[logIndex].skipped = skipped
        logs[logIndex].reps = reps
        logs[logIndex].loadValue = loadValue > 0 ? loadValue : nil
        logs[logIndex].loadUnit = loadValue > 0 ? loadUnit : nil
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

    private func persistProgressIfNeeded(force: Bool = false) {
        guard !finished else { return }
        _ = force
        do {
            try persistLocalResult(completed: false)
        } catch {}
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
