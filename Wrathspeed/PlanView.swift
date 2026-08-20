import SwiftUI
import WrathspeedCore

struct PlanView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                if let goal = store.plan?.goal {
                    Section(goal.kind.displayName) {
                        if let race = goal.raceDate {
                            LabeledContent("Race") { Text(race, style: .date) }
                        }
                        LabeledContent("Weeks", value: "\(goal.weekCount)")
                    }
                }
                ForEach(grouped, id: \.0) { weekStart, workouts in
                    Section(weekStart.formatted(.dateTime.month().day())) {
                        ForEach(workouts) { workout in
                            NavigationLink {
                                WorkoutDetailView(workout: workout)
                            } label: {
                                WorkoutRow(workout: workout, unit: store.unit)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plan")
        }
    }

    private var grouped: [(Date, [ScheduledWorkout])] {
        guard let plan = store.plan else { return [] }
        let groups = Dictionary(grouping: plan.workouts) {
            Calendar.current.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date
        }
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted { $0.date < $1.date }) }
    }
}

struct WorkoutDetailView: View {
    @Environment(AppStore.self) private var store
    let workout: ScheduledWorkout
    @State private var moveDate = Date()
    @State private var showLive = false

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Type", value: workout.blueprint.kind.rawValue)
                LabeledContent("When") { Text(workout.date, style: .date) }
                LabeledContent("Where", value: workout.blueprint.location.rawValue)
                if workout.blueprint.plannedDistanceMeters > 0 {
                    LabeledContent("Distance", value: Units.formatDistance(workout.blueprint.plannedDistanceMeters, unit: store.unit))
                }
            }
            Section("Steps") {
                ForEach(workout.blueprint.steps) { step in
                    VStack(alignment: .leading) {
                        Text(step.name)
                        Text(stepLabel(step))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !routines.isEmpty {
                Section("Prep and recovery") {
                    MobilitySectionView(routines: routines)
                }
            }
            Section {
                Button("Start") { showLive = true }
                DatePicker("Move to", selection: $moveDate, displayedComponents: .date)
                Button("Move") { store.move(workout, to: moveDate) }
                Button("Skip", role: .destructive) { store.skip(workout) }
                if workout.blueprint.kind.isQuality {
                    Button("Convert to easy") { store.skip(workout, convertQuality: true) }
                }
            }
        }
        .navigationTitle(workout.blueprint.title)
        .navigationDestination(isPresented: $showLive) {
            LiveRunView(blueprint: workout.blueprint)
        }
        .onAppear { moveDate = workout.date }
    }

    private var routines: [MobilityRoutine] {
        MobilityPlanner.routines(for: workout.blueprint.kind, catalog: store.movementCatalog)
    }

    private func stepLabel(_ step: WorkoutStep) -> String {
        switch step.target {
        case .distance(let meters):
            Units.formatDistance(meters, unit: store.unit)
        case .duration(let seconds):
            Units.formatDuration(seconds)
        }
    }
}
