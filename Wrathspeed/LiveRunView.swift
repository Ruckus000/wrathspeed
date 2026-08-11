import SwiftUI
import WrathspeedCore

struct LiveRunView: View {
    @Environment(AppStore.self) private var store
    let blueprint: WorkoutBlueprint

    var body: some View {
        let session = store.session
        VStack(spacing: 24) {
            Text(session.stepper?.currentStep?.name ?? blueprint.title)
                .font(.title2)
            metric("Time", Units.formatDuration(session.metrics.elapsed))
            metric("Distance", Units.formatDistance(session.metrics.distanceMeters, unit: store.unit))
            if let pace = session.metrics.currentPaceSecPerKm {
                metric("Pace", Units.formatPace(secondsPerKilometer: pace, unit: store.unit))
            }
            HStack(spacing: 16) {
                if session.isPaused {
                    Button("Resume") { session.resume() }
                } else {
                    Button("Pause") { session.pause() }
                }
                Button("Lap") { session.skipStep() }
                Button("End", role: .destructive) {
                    Task { await session.end() }
                }
            }
            .buttonStyle(.borderedProminent)
            Text(session.isRunning ? (WCSessionBridge.isWatchAppInstalled ? "Watch is recording. Phone can disconnect." : "Phone is recording.") : "Starting…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle(blueprint.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.start(blueprint)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.largeTitle.monospacedDigit())
        }
    }
}

