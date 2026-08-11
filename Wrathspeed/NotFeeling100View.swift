import SwiftUI
import WrathspeedCore

struct NotFeeling100View: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var days = 7
    @State private var mode: N100Mode = .reducedDifficulty
    @State private var returnPace: N100Return = .balanced

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Days: \(days)", value: $days, in: 3...14)
                Picker("Mode", selection: $mode) {
                    ForEach(N100Mode.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
                Picker("Return", selection: $returnPace) {
                    ForEach(N100Return.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
            }
            .navigationTitle("Not feeling 100%")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        store.applyNotFeeling100(
                            N100Adjustment(start: Date(), dayCount: days, mode: mode, returnPace: returnPace)
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

struct InstantRunView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: WorkoutKind = .easy
    @State private var location: RunLocation = .outdoor
    @State private var blueprint: WorkoutBlueprint?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Workout", selection: $kind) {
                    Text("Easy").tag(WorkoutKind.easy)
                    Text("Intervals").tag(WorkoutKind.intervals)
                    Text("Tempo").tag(WorkoutKind.tempo)
                    Text("Long").tag(WorkoutKind.longRun)
                    Text("Walk-run").tag(WorkoutKind.walkRun)
                    Text("Free run").tag(WorkoutKind.freeRun)
                }
                Picker("Location", selection: $location) {
                    Text("Outdoor").tag(RunLocation.outdoor)
                    Text("Treadmill").tag(RunLocation.treadmill)
                }
            }
            .navigationTitle("Instant run")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        blueprint = InstantWorkoutFactory.make(kind: kind, location: location, date: Date())
                    }
                }
            }
            .navigationDestination(item: $blueprint) { item in
                LiveRunView(blueprint: item)
            }
        }
    }
}
