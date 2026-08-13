import HealthKit
import SwiftUI
import WrathspeedCore

struct StrengthPlayerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: StrengthSession
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
    @State private var healthSync = HealthSyncMetadata(state: .notRequired)
    @State private var showAbout = false
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
        .onAppear { seedLogs() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard running, remaining > 0 else { return }
            remaining -= 1
        }
        .sheet(isPresented: $showAbout) {
            if let current {
                ExerciseAboutView(
                    exerciseName: current.exercise.name,
                    cue: current.exercise.cue,
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
            Button("✕") { dismiss() }
                .font(WSFont.ui(12, weight: .heavy))
                .foregroundStyle(WSColor.text40)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 8)
    }

    private func activeView(_ current: StrengthSet) -> some View {
        Group {
            Text("EXERCISE \(index + 1) / \(session.sets.count) · SET \(setIndex + 1)/\(current.sets)")
                .font(WSFont.mono(11))
                .foregroundStyle(WSColor.accent)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 26)
            Text(current.exercise.name.uppercased())
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
            HStack {
                Text("REPS")
                    .font(WSFont.ui(12, weight: .heavy))
                Spacer()
                WSStepperControl(
                    valueText: "\(reps)",
                    decrement: { reps = max(1, reps - 1) },
                    increment: { reps += 1 }
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
                    decrement: { loadValue = max(0, loadValue - 2.5) },
                    increment: { loadValue += 2.5 }
                )
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)
            Text("\(remaining)")
                .font(WSFont.display(100))
                .foregroundStyle(WSColor.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .accessibilityLabel("Rest timer \(remaining) seconds")
            Text("REST SECONDS")
                .font(WSFont.ui(12, weight: .bold))
                .foregroundStyle(WSColor.text50)
                .frame(maxWidth: .infinity)
            Spacer()
            HStack(spacing: 10) {
                WSPrimaryButton(title: running ? "PAUSE REST" : "START REST", height: 58, fontSize: 18) {
                    running.toggle()
                    if running { speech.speak(.stepStarted(current.exercise.name)) }
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

    private var current: StrengthSet? {
        session.sets.indices.contains(index) ? session.sets[index] : nil
    }

    private func seedLogs() {
        startedAt = Date()
        logs = session.sets.flatMap { set in
            (0..<set.sets).map { _ in
                StrengthSetLog(exerciseID: set.exercise.id, completed: false)
            }
        }
    }

    private func logCurrent(skipped: Bool) {
        guard logs.indices.contains(logIndex) else { return }
        logs[logIndex].completed = !skipped
        logs[logIndex].skipped = skipped
        logs[logIndex].reps = reps
        logs[logIndex].loadValue = loadValue > 0 ? loadValue : nil
        logs[logIndex].loadUnit = loadValue > 0 ? loadUnit : nil
        logs[logIndex].note = note.isEmpty ? nil : note
        persistLocalResult()
    }

    private var logIndex: Int {
        session.sets.prefix(index).reduce(0) { $0 + $1.sets } + setIndex
    }

    private func advanceSet() {
        guard let current else { return }
        running = false
        if setIndex + 1 < current.sets {
            setIndex += 1
            remaining = 45
            reps = current.reps
            return
        }
        setIndex = 0
        index += 1
        remaining = 45
        if let next = self.current {
            reps = next.reps
            speech.speak(.stepStarted(next.exercise.name))
        } else {
            finishSession()
        }
    }

    private func finishSession() {
        running = false
        finished = true
        persistLocalResult()
    }

    private func persistLocalResult() {
        let result = StrengthSessionResult(
            sessionID: session.id,
            startedAt: startedAt,
            endedAt: Date(),
            setLogs: logs,
            healthSync: healthSync
        )
        store.recordStrengthResult(result)
    }

    private func saveToHealth() async {
        healthSync = HealthSyncMetadata(state: .pending, lastAttemptAt: Date())
        persistLocalResult()
        let hk = HKHealthStore()
        let end = Date()
        let workout = HKWorkout(activityType: .traditionalStrengthTraining, start: startedAt, end: end)
        do {
            try await hk.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            try await hk.save(workout)
            healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: workout.uuid)
        } catch {
            healthSync = HealthSyncMetadata(state: .failed, failureMessage: error.localizedDescription, lastAttemptAt: end)
        }
        persistLocalResult()
    }
}
