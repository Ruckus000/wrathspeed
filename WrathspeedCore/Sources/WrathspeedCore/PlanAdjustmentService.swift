import Foundation

public struct PlanWorkoutMove: Equatable, Sendable {
    public var from: ScheduledWorkout
    public var to: ScheduledWorkout

    public init(from: ScheduledWorkout, to: ScheduledWorkout) {
        self.from = from
        self.to = to
    }
}

public struct PlanScheduleDiff: Equatable, Sendable {
    public var added: [ScheduledWorkout]
    public var removed: [ScheduledWorkout]
    public var moved: [PlanWorkoutMove]

    public init(
        added: [ScheduledWorkout] = [],
        removed: [ScheduledWorkout] = [],
        moved: [PlanWorkoutMove] = []
    ) {
        self.added = added
        self.removed = removed
        self.moved = moved
    }

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && moved.isEmpty }
}

public enum PlanAdjustmentService {
    /// Applies Not Feeling 100% as a reversible overlay on base prescriptions.
    public static func effectiveWorkouts(
        base: [ScheduledWorkout],
        adjustment: N100Adjustment?,
        calendar: Calendar = .current
    ) -> [ScheduledWorkout] {
        guard let adjustment else { return base }
        return NotFeeling100Rules.apply(workouts: base, adjustment: adjustment, calendar: calendar)
    }

    public static func effectivePlan(
        _ plan: TrainingPlan,
        adjustment: N100Adjustment?,
        calendar: Calendar = .current
    ) -> TrainingPlan {
        var copy = plan
        copy.workouts = effectiveWorkouts(base: plan.workouts, adjustment: adjustment, calendar: calendar)
        return copy
    }

    public static func diffFutureUnstarted(
        current: [ScheduledWorkout],
        proposed: [ScheduledWorkout],
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> PlanScheduleDiff {
        let today = calendar.startOfDay(for: asOf)
        let currentFuture = Dictionary(uniqueKeysWithValues: current.filter {
            $0.date >= today && ($0.status == .scheduled || $0.status == .convertedToEasy)
        }.map { ($0.id, $0) })
        let proposedFuture = Dictionary(uniqueKeysWithValues: proposed.filter {
            $0.date >= today && ($0.status == .scheduled || $0.status == .convertedToEasy)
        }.map { ($0.id, $0) })

        var added: [ScheduledWorkout] = []
        var removed: [ScheduledWorkout] = []
        var moved: [PlanWorkoutMove] = []

        for (id, workout) in proposedFuture where currentFuture[id] == nil {
            added.append(workout)
        }
        for (id, workout) in currentFuture where proposedFuture[id] == nil {
            removed.append(workout)
        }
        for (id, old) in currentFuture {
            guard let new = proposedFuture[id], !calendar.isDate(old.date, inSameDayAs: new.date) else { continue }
            moved.append(PlanWorkoutMove(from: old, to: new))
        }
        return PlanScheduleDiff(added: added, removed: removed, moved: moved)
    }
}
