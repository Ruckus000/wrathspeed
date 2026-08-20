import Foundation

public struct ImportedHealthWorkout: Equatable, Sendable {
    public var healthKitUUID: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var duration: TimeInterval
    public var distanceMeters: Double
    public var location: RunLocation
    public var heartRateAverage: Double?
    public var energyKilocalories: Double?
    public var cadenceAverage: Double?
    public var route: [RoutePoint]?
    public var source: WorkoutSource

    public init(
        healthKitUUID: UUID,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        distanceMeters: Double,
        location: RunLocation,
        heartRateAverage: Double? = nil,
        energyKilocalories: Double? = nil,
        cadenceAverage: Double? = nil,
        route: [RoutePoint]? = nil,
        source: WorkoutSource = .appleHealth
    ) {
        self.healthKitUUID = healthKitUUID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.location = location
        self.heartRateAverage = heartRateAverage
        self.energyKilocalories = energyKilocalories
        self.cadenceAverage = cadenceAverage
        self.route = route
        self.source = source
    }

    public func asWorkoutResult() -> WorkoutResult {
        let pace = distanceMeters > 0 ? duration / (distanceMeters / 1_000) : nil
        return WorkoutResult(
            workoutID: healthKitUUID,
            startedAt: startedAt,
            duration: duration,
            distanceMeters: distanceMeters,
            averagePaceSecPerKm: pace,
            heartRateAverage: heartRateAverage,
            location: location,
            healthKitUUID: healthKitUUID,
            route: route,
            source: source,
            matchInfo: WorkoutMatchInfo(state: .unmatched),
            energyKilocalories: energyKilocalories,
            cadenceAverage: cadenceAverage,
            healthSync: HealthSyncMetadata(state: .synced, healthKitUUID: healthKitUUID)
        )
    }
}

public struct WorkoutMatchCandidate: Equatable, Sendable {
    public var scheduledWorkoutID: UUID
    public var score: Double

    public init(scheduledWorkoutID: UUID, score: Double) {
        self.scheduledWorkoutID = scheduledWorkoutID
        self.score = score
    }
}

public enum WorkoutMatcher {
    public static let distanceTolerance = 0.35

    public static func candidates(
        for result: WorkoutResult,
        plan: TrainingPlan?,
        calendar: Calendar = .current
    ) -> [WorkoutMatchCandidate] {
        guard let plan else { return [] }
        let eligible = plan.workouts.filter { workout in
            workout.status == .scheduled || workout.status == .convertedToEasy
        }
        return eligible.compactMap { workout -> WorkoutMatchCandidate? in
            guard sameLocalDay(result.startedAt, workout.date, calendar: calendar) else { return nil }
            let planned = workout.blueprint.plannedDistanceMeters
            guard planned > 0 else { return nil }
            let delta = abs(result.distanceMeters - planned) / planned
            guard delta <= distanceTolerance else { return nil }
            let timeDelta = abs(result.startedAt.timeIntervalSince(workout.date))
            let locationPenalty = result.location == workout.blueprint.location ? 0.0 : 300.0
            let score = timeDelta + (delta * 1_000) + locationPenalty
            return WorkoutMatchCandidate(scheduledWorkoutID: workout.id, score: score)
        }
        .sorted { $0.score < $1.score }
    }

    public static func bestSuggestion(
        for result: WorkoutResult,
        plan: TrainingPlan?,
        rejectedIDs: Set<UUID> = [],
        calendar: Calendar = .current
    ) -> UUID? {
        candidates(for: result, plan: plan, calendar: calendar)
            .first { !rejectedIDs.contains($0.scheduledWorkoutID) }?
            .scheduledWorkoutID
    }

    public static func sameLocalDay(_ lhs: Date, _ rhs: Date, calendar: Calendar) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }
}

public enum HealthImportMerge {
    public static func merge(
        existing: [WorkoutResult],
        imports: [ImportedHealthWorkout]
    ) -> [WorkoutResult] {
        var merged = existing
        for imported in imports {
            if let index = merged.firstIndex(where: {
                WorkoutResultMerge.resolvedHealthKitUUID(for: $0) == imported.healthKitUUID
            }) {
                var current = merged[index]
                current.duration = imported.duration
                let preserveConfirmedTreadmillDistance =
                    current.location == .treadmill && current.source != .appleHealth
                if !preserveConfirmedTreadmillDistance {
                    current.distanceMeters = imported.distanceMeters
                }
                if current.source == .appleHealth {
                    current.startedAt = imported.startedAt
                    current.location = imported.location
                }
                if current.duration > 0, current.distanceMeters > 0 {
                    current.averagePaceSecPerKm = (current.duration / current.distanceMeters) * 1_000
                } else {
                    current.averagePaceSecPerKm = nil
                }
                current.heartRateAverage = imported.heartRateAverage ?? current.heartRateAverage
                current.energyKilocalories = imported.energyKilocalories ?? current.energyKilocalories
                current.cadenceAverage = imported.cadenceAverage ?? current.cadenceAverage
                if let route = imported.route {
                    let preserveLocalRoute = current.source != .appleHealth && current.route != nil
                    if !preserveLocalRoute {
                        current.route = route
                    }
                }
                current.isUnavailableInHealth = false
                current.healthKitUUID = imported.healthKitUUID
                current.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: imported.healthKitUUID)
                merged[index] = current
            } else {
                merged.append(imported.asWorkoutResult())
            }
        }
        return merged.sorted { $0.startedAt > $1.startedAt }
    }

    public static func markUnavailable(existing: [WorkoutResult], missingHealthIDs: Set<UUID>) -> [WorkoutResult] {
        existing.map { result in
            guard let uuid = WorkoutResultMerge.resolvedHealthKitUUID(for: result),
                  missingHealthIDs.contains(uuid) else { return result }
            var copy = result
            copy.isUnavailableInHealth = true
            return copy
        }
    }
}

public enum HealthImportApply {
    public static func apply(
        existing: [WorkoutResult],
        importResult: HealthImportResult
    ) -> [WorkoutResult] {
        let merged = HealthImportMerge.merge(existing: existing, imports: importResult.workouts)
        return HealthImportMerge.markUnavailable(existing: merged, missingHealthIDs: importResult.deletedHealthKitUUIDs)
    }
}
