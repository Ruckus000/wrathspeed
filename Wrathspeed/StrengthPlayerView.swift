import HealthKit
import SwiftUI
import WrathspeedCore

struct StrengthPlayerView: View {
    let session: StrengthSession
    @State private var index = 0
    @State private var remaining = 45
    @State private var running = false
    @State private var saved = false
    private let speech = SpeechCuePlayer()

    var body: some View {
        let current = session.sets.indices.contains(index) ? session.sets[index] : nil
        VStack(spacing: 20) {
            if let current {
                MovementMediaView(
                    movementID: current.exercise.id,
                    symbolName: current.exercise.symbolName
                )
                Text(current.exercise.name)
                    .font(.title2)
                Text("\(current.sets) × \(current.reps)")
                    .font(.headline)
                Text(current.exercise.cue)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("\(remaining)s")
                    .font(.largeTitle.monospacedDigit())
                HStack {
                    Button(running ? "Pause" : "Start") {
                        running.toggle()
                        if running {
                            speech.speak(.stepStarted(current.exercise.name))
                        }
                    }
                    Button("Next") { advance() }
                }
                .buttonStyle(.borderedProminent)
                Text("\(index + 1) / \(session.sets.count)")
                    .font(.caption)
            } else {
                Text("Session complete")
                Button("Save to Health") {
                    Task { await save() }
                }
                .disabled(saved)
            }
        }
        .padding()
        .navigationTitle(session.title)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard running, remaining > 0 else { return }
            remaining -= 1
            if remaining == 0 { advance() }
        }
    }

    private func advance() {
        index += 1
        remaining = 45
        if session.sets.indices.contains(index) {
            speech.speak(.stepStarted(session.sets[index].exercise.name))
        } else {
            running = false
        }
    }

    private func save() async {
        let store = HKHealthStore()
        let start = Date().addingTimeInterval(-Double(session.durationMinutes * 60))
        let end = Date()
        let workout = HKWorkout(
            activityType: .traditionalStrengthTraining,
            start: start,
            end: end
        )
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            try await store.save(workout)
            saved = true
        } catch {
            saved = false
        }
    }
}
