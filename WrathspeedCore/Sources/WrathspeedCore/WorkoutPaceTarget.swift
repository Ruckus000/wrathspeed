import Foundation

public enum WorkoutPaceTarget {
    private static let zonePriority: [PaceZone] = [.threshold, .interval, .repetition, .marathon, .easy]

    public static func representativeZone(in blueprint: WorkoutBlueprint) -> PaceZone? {
        let eligible = blueprint.steps.compactMap(eligibleZone(for:))
        guard !eligible.isEmpty else { return nil }
        for preferred in zonePriority where eligible.contains(preferred) {
            return preferred
        }
        return eligible.first
    }

    public static func targetPaceSecPerKm(blueprint: WorkoutBlueprint, zones: PaceZones?) -> TimeInterval? {
        guard blueprint.usesPaceTargets, let zones else { return nil }
        let zone = representativeZone(in: blueprint) ?? fallbackZone(for: blueprint.kind)
        guard let zone else { return nil }
        return zones.secondsPerKilometer(for: zone)
    }

    static func eligibleZone(for step: WorkoutStep) -> PaceZone? {
        let name = step.name.lowercased()
        if name.contains("warm up") || name.contains("warm-up") { return nil }
        if name.contains("cool down") || name.contains("cooldown") { return nil }
        if name.contains("recover") { return nil }
        guard case .zone(let zone) = step.intensity else { return nil }
        guard zone != .recovery else { return nil }
        return zone
    }

    static func fallbackZone(for kind: WorkoutKind) -> PaceZone? {
        switch kind {
        case .easy, .longRun, .freeRun: .easy
        case .tempo: .threshold
        case .intervals: .interval
        case .race: nil
        default: nil
        }
    }

  /// Converts a target pace into treadmill belt speed (metres per second).
    public static func treadmillSpeedMetersPerSecond(paceSecPerKm: TimeInterval) -> Double? {
        guard paceSecPerKm.isFinite, paceSecPerKm > 0 else { return nil }
        return 1_000 / paceSecPerKm
    }

    public static func treadmillSpeedMetersPerSecond(
        blueprint: WorkoutBlueprint,
        zones: PaceZones?
    ) -> Double? {
        guard let pace = targetPaceSecPerKm(blueprint: blueprint, zones: zones) else { return nil }
        return treadmillSpeedMetersPerSecond(paceSecPerKm: pace)
    }

    public static func treadmillSpeedFromDisplay(_ value: Double, unit: DistanceUnit) -> Double {
        switch unit {
        case .kilometers: value / 3.6
        case .miles: value / 2.23694
        }
    }

    public static func treadmillSpeedDisplay(
        metersPerSecond: Double,
        unit: DistanceUnit
    ) -> Double {
        switch unit {
        case .kilometers: metersPerSecond * 3.6
        case .miles: metersPerSecond * 2.23694
        }
    }
}
