import SwiftUI
import WrathspeedCore

/// Browsable index of every movement the app knows, so a demo clip is reachable even
/// when the movement is not in today's routine.
struct MovementLibraryView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Section("Strength") {
                ForEach(strengthExercises, id: \.id) { exercise in
                    NavigationLink {
                        MovementDetailView(
                            movementID: exercise.id,
                            name: exercise.name,
                            symbolName: exercise.symbolName,
                            cue: exercise.cue,
                            subtitle: "\(exercise.defaultReps) reps"
                        )
                    } label: {
                        Label(exercise.name, systemImage: exercise.symbolName)
                    }
                }
            }
            ForEach(MovementPhase.allCases, id: \.self) { phase in
                let movements = store.movementCatalog.inPhase(phase)
                if !movements.isEmpty {
                    Section(phase.title) {
                        ForEach(movements) { movement in
                            NavigationLink {
                                MovementDetailView(
                                    movementID: movement.id,
                                    name: movement.name,
                                    symbolName: movement.symbolName,
                                    cue: movement.cue,
                                    subtitle: "\(movement.durationSeconds)s · \(movement.bodyArea)"
                                )
                            } label: {
                                Label(movement.name, systemImage: movement.symbolName)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Movements")
    }

    private var strengthExercises: [StrengthExercise] {
        store.strengthCatalog.exercises
    }
}

struct MovementDetailView: View {
    let movementID: String
    let name: String
    let symbolName: String
    let cue: String
    let subtitle: String

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                MovementMediaView(movementID: movementID, symbolName: symbolName, height: 280)
                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(cue)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
