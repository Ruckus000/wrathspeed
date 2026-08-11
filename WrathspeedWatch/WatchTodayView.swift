import SwiftUI
import WrathspeedCore

struct WatchTodayView: View {
    @Environment(WatchStore.self) private var store
    @State private var active: WorkoutBlueprint?

    var body: some View {
        NavigationStack {
            List {
                if store.upcoming.isEmpty {
                    Text("No upcoming runs. Open iPhone to sync your plan.")
                }
                ForEach(store.upcoming) { blueprint in
                    Button {
                        active = blueprint
                    } label: {
                        VStack(alignment: .leading) {
                            Text(blueprint.title)
                            Text(blueprint.date, style: .date)
                                .font(.caption2)
                        }
                    }
                }
            }
            .navigationTitle("Wrathspeed")
            .navigationDestination(item: $active) { blueprint in
                WatchLiveView(blueprint: blueprint)
            }
            .onReceive(NotificationCenter.default.publisher(for: .watchShouldStartWorkout)) { _ in
                if let pending = store.bridge.pendingStart ?? store.upcoming.first {
                    active = pending
                }
            }
            .onChange(of: store.bridge.pendingStart?.id) { _, _ in
                if let pending = store.bridge.pendingStart {
                    active = pending
                }
            }
        }
    }
}

struct WatchLiveView: View {
    @Environment(WatchStore.self) private var store
    let blueprint: WorkoutBlueprint

    var body: some View {
        let session = store.session
        ScrollView {
            VStack(spacing: 8) {
                Text(session.stepper?.currentStep?.name ?? blueprint.title)
                Text(Units.formatDuration(session.metrics.elapsed))
                    .font(.title.monospacedDigit())
                Text(Units.formatDistance(session.metrics.distanceMeters, unit: .kilometers))
                if let pace = session.metrics.currentPaceSecPerKm {
                    Text(Units.formatPace(secondsPerKilometer: pace, unit: .kilometers))
                }
                HStack {
                    Button(session.isPaused ? "Go" : "Pause") {
                        session.isPaused ? session.resume() : session.pause()
                    }
                    Button("Lap") { session.skipStep() }
                }
                Button("End", role: .destructive) {
                    Task { await session.end() }
                }
            }
        }
        .navigationTitle("Run")
        .task {
            let vdot = store.bridge.upcoming?.vdot ?? 50
            store.session.zones = blueprint.usesPaceTargets ? PaceCalculator.zones(vdot: vdot) : nil
            try? await store.session.start(blueprint: blueprint, zones: store.session.zones)
        }
    }
}

