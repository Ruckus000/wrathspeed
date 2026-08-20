import Foundation

public struct WeeklyLoadSummary: Equatable, Sendable {
    public var weekStart: Date
    public var plannedMeters: Double
    public var actualMeters: Double
    public var confirmedAdherenceCount: Int
    public var plannedRunCount: Int
    public var unmatchedExtraMeters: Double
    public var qualityCompleted: Int

    public init(
        weekStart: Date,
        plannedMeters: Double,
        actualMeters: Double,
        confirmedAdherenceCount: Int,
        plannedRunCount: Int,
        unmatchedExtraMeters: Double,
        qualityCompleted: Int
    ) {
        self.weekStart = weekStart
        self.plannedMeters = plannedMeters
        self.actualMeters = actualMeters
        self.confirmedAdherenceCount = confirmedAdherenceCount
        self.plannedRunCount = plannedRunCount
        self.unmatchedExtraMeters = unmatchedExtraMeters
        self.qualityCompleted = qualityCompleted
    }
}

public enum HistoryInsights {
    public static func weeklySummary(
        plan: TrainingPlan?,
        results: [WorkoutResult],
        weekStart: Date,
        calendar: Calendar = .current
    ) -> WeeklyLoadSummary {
        let end = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let workouts = plan?.workouts.filter {
            $0.date >= weekStart && $0.date < end && $0.blueprint.kind.isRunning
        } ?? []
        let plannedMeters = workouts.reduce(0) { $0 + $1.blueprint.plannedDistanceMeters }
        let plannedRunCount = workouts.filter {
            $0.status == .scheduled || $0.status == .convertedToEasy || $0.status == .completed
        }.count
        let confirmed = workouts.filter { countsTowardAdherence($0) }.count

        let deduped = deduplicatedResults(results)
        let weekResults = deduped.filter { $0.startedAt >= weekStart && $0.startedAt < end }
        let actualMeters = weekResults.reduce(0) { $0 + $1.distanceMeters }
        let unmatchedExtra = weekResults.filter { result in
            result.matchInfo.state != .matched
                && result.source != .wrathspeedPhone
                && result.source != .wrathspeedWatch
        }.reduce(0) { $0 + $1.distanceMeters }
        let qualityCompleted = workouts.filter {
            $0.status == .completed && $0.blueprint.kind.isQuality
        }.count

        return WeeklyLoadSummary(
            weekStart: weekStart,
            plannedMeters: plannedMeters,
            actualMeters: actualMeters,
            confirmedAdherenceCount: confirmed,
            plannedRunCount: plannedRunCount,
            unmatchedExtraMeters: unmatchedExtra,
            qualityCompleted: qualityCompleted
        )
    }

    public static func rollingFourWeekSummaries(
        plan: TrainingPlan?,
        results: [WorkoutResult],
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> [WeeklyLoadSummary] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: asOf) else { return [] }
        return (0..<4).compactMap { offset -> WeeklyLoadSummary? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: interval.start) else { return nil }
            return weeklySummary(plan: plan, results: results, weekStart: start, calendar: calendar)
        }.reversed()
    }

    public static func deduplicatedResults(_ results: [WorkoutResult]) -> [WorkoutResult] {
        var seen = Set<String>()
        var output: [WorkoutResult] = []
        for result in results {
            let key = WorkoutResultMerge.identityKey(for: result)
            if seen.insert(key).inserted {
                output.append(result)
            }
        }
        return output
    }

    static func countsTowardAdherence(_ workout: ScheduledWorkout) -> Bool {
        guard workout.status == .completed, let result = workout.result else { return false }
        switch result.source {
        case .wrathspeedPhone, .wrathspeedWatch:
            return result.workoutID == workout.blueprint.id || result.workoutID == workout.id
        case .appleHealth:
            return result.matchInfo.state == .matched && result.matchInfo.scheduledWorkoutID == workout.id
        case .instant:
            return false
        }
    }
}
