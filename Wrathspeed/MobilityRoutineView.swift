import SwiftUI
import WrathspeedCore

/// Plays a warm-up, drill or cool-down routine: one movement at a time, with its demo
/// loop, cue, and a countdown that advances automatically.
struct MobilityRoutineView: View {
    let routine: MobilityRoutine

    @State private var index = 0
    @State private var remaining: Int
    @State private var running = false
    private let speech = SpeechCuePlayer()

    init(routine: MobilityRoutine) {
        self.routine = routine
        _remaining = State(initialValue: routine.items.first?.durationSeconds ?? 0)
    }

    private var current: RoutineItem? {
        routine.items.indices.contains(index) ? routine.items[index] : nil
    }

    var body: some View {
        VStack(spacing: 20) {
            if let current {
                MovementMediaView(
                    movementID: current.movement.id,
                    symbolName: current.movement.symbolName
                )
                Text(current.movement.name)
                    .font(.title2)
                Text(current.movement.cue)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("\(remaining)s")
                    .font(.largeTitle.monospacedDigit())
                HStack {
                    Button(running ? "Pause" : "Start") {
                        running.toggle()
                        if running {
                            speech.speak(.stepStarted(current.movement.name))
                        }
                    }
                    Button("Next") { advance() }
                }
                .buttonStyle(.borderedProminent)
                Text("\(index + 1) / \(routine.items.count)")
                    .font(.caption)
            } else {
                ContentUnavailableView(
                    "\(routine.title) complete",
                    systemImage: "checkmark.circle",
                    description: Text("Nice. That's the whole routine.")
                )
            }
        }
        .padding()
        .navigationTitle(routine.title)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard running, remaining > 0 else { return }
            remaining -= 1
            if remaining == 0 { advance() }
        }
    }

    private func advance() {
        index += 1
        if let next = routine.items.indices.contains(index) ? routine.items[index] : nil {
            remaining = next.durationSeconds
            speech.speak(.stepStarted(next.movement.name))
        } else {
            remaining = 0
            running = false
        }
    }
}

/// Lists the routines that bracket a given workout, each linking to its player.
struct MobilitySectionView: View {
    let routines: [MobilityRoutine]

    var body: some View {
        ForEach(routines) { routine in
            NavigationLink {
                MobilityRoutineView(routine: routine)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(routine.title, systemImage: icon(for: routine.phase))
                    Text("\(routine.items.count) movements · \(routine.totalSeconds / 60) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func icon(for phase: MovementPhase) -> String {
        switch phase {
        case .warmup: "figure.flexibility"
        case .drills: "figure.run"
        case .cooldown: "wind"
        }
    }
}
