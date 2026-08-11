import SwiftUI
import WrathspeedCore

struct HistoryView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            List(store.results, id: \.workoutID) { result in
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.startedAt, style: .date)
                    Text(Units.formatDistance(result.distanceMeters, unit: store.unit))
                    if let pace = result.averagePaceSecPerKm {
                        Text(Units.formatPace(secondsPerKilometer: pace, unit: store.unit))
                    }
                    if let comparison = comparison(for: result) {
                        Text(comparison)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func comparison(for result: WorkoutResult) -> String? {
        guard let workout = store.plan?.workouts.first(where: { $0.blueprint.id == result.workoutID || $0.id == result.workoutID }) else {
            return nil
        }
        let planned = workout.blueprint.plannedDistanceMeters
        guard planned > 0 else { return nil }
        let delta = result.distanceMeters - planned
        let distance = Units.formatDistance(abs(delta), unit: store.unit)
        let vsDistance = delta >= 0 ? "+\(distance) vs plan" : "-\(distance) vs plan"
        guard workout.blueprint.usesPaceTargets,
              let actual = result.averagePaceSecPerKm,
              let zone = targetZone(for: workout.blueprint.kind),
              let target = store.zones?.secondsPerKilometer(for: zone)
        else { return vsDistance }
        let paceDelta = actual - target
        let faster = paceDelta < 0
        return "\(vsDistance) · pace \(faster ? "faster" : "slower") than target"
    }

    private func targetZone(for kind: WorkoutKind) -> PaceZone? {
        switch kind {
        case .easy, .longRun, .freeRun: .easy
        case .tempo: .threshold
        case .intervals: .interval
        case .race: .marathon
        default: nil
        }
    }
}
