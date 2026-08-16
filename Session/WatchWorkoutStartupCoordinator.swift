import Foundation
import WrathspeedCore

/// Tracks cancellable Watch workout startup and control readiness without HealthKit.
struct WatchWorkoutStartupCoordinator: Equatable {
    enum Phase: Equatable {
        case idle
        case starting
        case recording
    }

    private(set) var phase: Phase = .idle
    private(set) var startupGeneration: UInt = 0

    var canPauseOrLap: Bool {
        phase == .recording
    }

    mutating func beginStartup() -> UInt {
        startupGeneration &+= 1
        phase = .starting
        return startupGeneration
    }

    mutating func cancelStartup() {
        startupGeneration &+= 1
        phase = .idle
    }

    mutating func markRecording(expectedGeneration: UInt) {
        guard expectedGeneration == startupGeneration, phase == .starting else { return }
        phase = .recording
    }

    mutating func reset() {
        phase = .idle
        startupGeneration &+= 1
    }

    func isGenerationCurrent(_ generation: UInt) -> Bool {
        generation == startupGeneration
    }
}

struct WatchWorkoutContext: Equatable {
    let blueprint: WorkoutBlueprint
    let zones: PaceZones?
    let unit: DistanceUnit
    let resultSource: WorkoutSource

    static func make(from request: WatchStartRequest, fallbackUnit: DistanceUnit) -> WatchWorkoutContext {
        let unit = request.unit ?? fallbackUnit
        let vdot = request.vdot
        let zones = request.blueprint.usesPaceTargets && vdot != nil
            ? PaceCalculator.zones(vdot: vdot!)
            : nil
        return WatchWorkoutContext(
            blueprint: request.blueprint,
            zones: zones,
            unit: unit,
            resultSource: .wrathspeedWatch
        )
    }

    @MainActor
    func apply(to session: WorkoutSessionController) {
        session.resultSource = resultSource
        session.splitUnit = unit
        session.zones = zones
    }
}
