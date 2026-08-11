import SwiftUI
import WrathspeedCore

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var showN100 = false
    @State private var showInstant = false
    @State private var liveBlueprint: WorkoutBlueprint?

    var body: some View {
        NavigationStack {
            List {
                if let pending = store.pendingSuggestion {
                    Section("Pace suggestion") {
                        Text(pending.reason)
                        Text("New VDOT \(pending.newVDOT.formatted(.number.precision(.fractionLength(1))))")
                        HStack {
                            Button("Accept") { store.acceptVDOTSuggestion() }
                            Button("Not now", role: .cancel) { store.declineVDOTSuggestion() }
                        }
                    }
                }
                Section("Today") {
                    if store.todaysRuns.isEmpty && store.todaysStrength.isEmpty {
                        Text("Rest day. Add an instant run if you want extra work.")
                    }
                    ForEach(store.todaysRuns) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            WorkoutRow(workout: workout, unit: store.unit)
                        }
                        .swipeActions {
                            Button("Start") { liveBlueprint = workout.blueprint }
                        }
                    }
                    ForEach(store.todaysStrength) { session in
                        NavigationLink {
                            StrengthPlayerView(session: session)
                        } label: {
                            Label(session.title, systemImage: "figure.strengthtraining.traditional")
                        }
                    }
                }
                Section("This week") {
                    ForEach(weekWorkouts) { workout in
                        WorkoutRow(workout: workout, unit: store.unit)
                    }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not 100%") { showN100 = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Instant run", systemImage: "plus") { showInstant = true }
                }
            }
            .sheet(isPresented: $showN100) { NotFeeling100View() }
            .sheet(isPresented: $showInstant) { InstantRunView() }
            .navigationDestination(item: $liveBlueprint) { blueprint in
                LiveRunView(blueprint: blueprint)
            }
        }
    }

    private var weekWorkouts: [ScheduledWorkout] {
        guard let plan else { return [] }
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        return plan.workouts.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
    }

    private var plan: TrainingPlan? { store.plan }
}

struct WorkoutRow: View {
    let workout: ScheduledWorkout
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.blueprint.title)
            Text(workout.date, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
            if workout.blueprint.plannedDistanceMeters > 0 {
                Text(Units.formatDistance(workout.blueprint.plannedDistanceMeters, unit: unit))
                    .font(.caption)
            }
        }
    }
}
