import Foundation

/// The deterministic inputs behind the coach's quick actions. A button supplies its parameter
/// from these lists and the existing compile-and-approve path does the rest; the model is
/// never in the loop for a button. It was: MOVE LONG RUN and TREADMILL sent a sentence to the
/// model, which is unavailable on most devices and, where available, picked the wrong workout
/// in every day-named request the evaluation harness ran.
public enum CoachQuickActions {
    /// The run days the long run could move to: every available day except its current one.
    /// `CoachPlanRules.validateLongRunWeekday` rejects anything outside this list anyway.
    public static func longRunWeekdayOptions(profile: RunnerProfile) -> [Weekday] {
        profile.resolvedRunWeekdays().filter { $0 != profile.longRunWeekday }
    }

    /// Upcoming outdoor runs the runner could move to a treadmill, soonest first. Fourteen days
    /// keeps the list to what a weather forecast can speak to.
    public static func indoorWorkoutOptions(
        plan: TrainingPlan,
        asOf: Date = Date(),
        calendar: Calendar = .current,
        withinDays days: Int = 14
    ) -> [ScheduledWorkout] {
        let start = calendar.startOfDay(for: asOf)
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return [] }
        return plan.workouts.filter { workout in
            workout.date >= start && workout.date < end
                && (workout.status == .scheduled || workout.status == .convertedToEasy)
                && workout.blueprint.kind.isRunning
                && workout.blueprint.location != .treadmill
        }.sorted { $0.date < $1.date }
    }

    // MARK: - FASTER PACES needs evidence

    public static let fasterPacesRunCount = 3

    public struct FasterPacesEvidence: Equatable {
        /// Most recent first.
        public var runs: [ScheduledWorkout]
        /// Mean of (actual − target) / target over `runs`; negative is faster.
        public var meanDeltaFraction: Double
        /// The current VDOT nudged by the adaptation limit, the same step the rule clamps to.
        public var suggestedVDOT: Double
    }

    public enum FasterPacesVerdict: Equatable {
        case evidence(FasterPacesEvidence)
        case fewerThanThreeRuns(Int)
        case notFasterThanTarget(meanDeltaFraction: Double)
    }

    /// The last three completed runs that had a target pace, averaging at least the nudge
    /// limit faster than target. FASTER PACES used to bump VDOT by that limit on a tap with no
    /// check at all — "make my paces harder" with nothing behind it.
    public static func fasterPacesVerdict(
        plan: TrainingPlan,
        profile: RunnerProfile,
        zones: PaceZones?,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> FasterPacesVerdict {
        let measured: [(workout: ScheduledWorkout, delta: Double)] = plan.workouts
            .filter { $0.blueprint.kind.isRunning && $0.status == .completed }
            .sorted { $0.date > $1.date }
            .compactMap { workout in
                guard let actual = workout.result?.averagePaceSecPerKm, actual > 0,
                      let target = WorkoutPaceTarget.targetPaceSecPerKm(blueprint: workout.blueprint, zones: zones), target > 0
                else { return nil }
                return (workout, (actual - target) / target)
            }
        let recent = Array(measured.prefix(fasterPacesRunCount))
        guard recent.count >= fasterPacesRunCount else { return .fewerThanThreeRuns(recent.count) }
        let mean = recent.map(\.delta).reduce(0, +) / Double(recent.count)
        guard mean <= -CoachPlanRules.vdotChangeLimit else { return .notFasterThanTarget(meanDeltaFraction: mean) }
        return .evidence(FasterPacesEvidence(
            runs: recent.map(\.workout),
            meanDeltaFraction: mean,
            suggestedVDOT: profile.vdot * (1 + CoachPlanRules.vdotChangeLimit)
        ))
    }
}
