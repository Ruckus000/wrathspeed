import Foundation

public struct MissedWorkSituation: Equatable, Sendable {
    public var missedWorkouts: [ScheduledWorkout]
    public var isFullWeekMissed: Bool

    public init(missedWorkouts: [ScheduledWorkout], isFullWeekMissed: Bool) {
        self.missedWorkouts = missedWorkouts
        self.isFullWeekMissed = isFullWeekMissed
    }
}

public enum MissedWorkChoice: Equatable, Sendable {
    case skipMissed
    case moveEligible
    case extendPlan
}

public struct MissedWorkPreview: Equatable, Sendable {
    public var skippedCount: Int
    public var movedCount: Int
    public var addedWeekCount: Int
    public var description: String

    public init(skippedCount: Int, movedCount: Int, addedWeekCount: Int, description: String) {
        self.skippedCount = skippedCount
        self.movedCount = movedCount
        self.addedWeekCount = addedWeekCount
        self.description = description
    }
}

public enum MissedWorkService {
    public static func detect(
        plan: TrainingPlan,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> MissedWorkSituation? {
        let today = calendar.startOfDay(for: asOf)
        let missed = plan.workouts.filter { workout in
            workout.blueprint.kind.isRunning
                && workout.status == .scheduled
                && calendar.startOfDay(for: workout.date) < today
        }
        guard !missed.isEmpty else { return nil }

        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: asOf)
        let weekMissed = missed.filter { weekInterval?.contains($0.date) ?? false }
        let weekScheduled = plan.workouts.filter { workout in
            workout.blueprint.kind.isRunning
                && (workout.status == .scheduled || workout.status == .convertedToEasy)
                && (weekInterval?.contains(workout.date) ?? false)
        }
        let isFullWeek = !weekScheduled.isEmpty && weekMissed.count == weekScheduled.count
        return MissedWorkSituation(missedWorkouts: missed, isFullWeekMissed: isFullWeek)
    }

    public static func canExtend(plan: TrainingPlan) -> Bool {
        plan.goal.raceDate == nil
    }

    public static func preview(
        choice: MissedWorkChoice,
        plan: TrainingPlan,
        situation: MissedWorkSituation,
        calendar: Calendar = .current,
        asOf: Date = Date()
    ) -> MissedWorkPreview {
        switch choice {
        case .skipMissed:
            return MissedWorkPreview(
                skippedCount: situation.missedWorkouts.count,
                movedCount: 0,
                addedWeekCount: 0,
                description: "Skip \(situation.missedWorkouts.count) missed session(s). They will not be stacked onto future days."
            )
        case .moveEligible:
            let eligible = eligibleToMove(situation.missedWorkouts)
            return MissedWorkPreview(
                skippedCount: situation.missedWorkouts.count - eligible.count,
                movedCount: eligible.count,
                addedWeekCount: 0,
                description: "Move \(eligible.count) eligible session(s) to open future days. Remaining missed work will be skipped."
            )
        case .extendPlan:
            return MissedWorkPreview(
                skippedCount: 0,
                movedCount: 0,
                addedWeekCount: 1,
                description: "Add one week to your plan and reschedule missed work into the extension week."
            )
        }
    }

    public static func applySkip(
        plan: TrainingPlan,
        situation: MissedWorkSituation
    ) -> TrainingPlan {
        var copy = plan
        let ids = Set(situation.missedWorkouts.map(\.id))
        copy.workouts = copy.workouts.map { workout in
            guard ids.contains(workout.id) else { return workout }
            return AdaptationRules.applySkip(workout)
        }
        return copy
    }

    public static func applyMoveEligible(
        plan: TrainingPlan,
        situation: MissedWorkSituation,
        calendar: Calendar = .current,
        asOf: Date = Date()
    ) -> TrainingPlan {
        var copy = plan
        let today = calendar.startOfDay(for: asOf)
        var occupied = Set(copy.workouts.compactMap { workout -> Date? in
            guard workout.status == .scheduled || workout.status == .convertedToEasy else { return nil }
            return calendar.startOfDay(for: workout.date)
        })

        for workout in eligibleToMove(situation.missedWorkouts) {
            guard let nextOpen = nextOpenDay(from: today, occupied: occupied, calendar: calendar) else {
                copy.workouts = copy.workouts.map { current in
                    current.id == workout.id ? AdaptationRules.applySkip(current) : current
                }
                continue
            }
            occupied.insert(nextOpen)
            copy.workouts = copy.workouts.map { current in
                guard current.id == workout.id else { return current }
                var moved = current
                moved.blueprint.date = nextOpen
                return moved
            }
        }

        let movedIDs = Set(eligibleToMove(situation.missedWorkouts).map(\.id))
        copy.workouts = copy.workouts.map { workout in
            guard situation.missedWorkouts.contains(where: { $0.id == workout.id }),
                  !movedIDs.contains(workout.id),
                  workout.status == .scheduled
            else { return workout }
            return AdaptationRules.applySkip(workout)
        }
        return copy
    }

    public static func extendedGoal(from goal: TrainingGoal) -> TrainingGoal? {
        guard goal.raceDate == nil else { return nil }
        var copy = goal
        copy.weekCount = min(26, goal.weekCount + 1)
        return copy
    }

    public static func reassignedIntoExtensionWeek(
        plan: TrainingPlan,
        situation: MissedWorkSituation,
        extensionWeekStart: Date,
        calendar: Calendar = .current
    ) -> TrainingPlan {
        var copy = plan
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: extensionWeekStart) else { return copy }
        let extensionSlots = copy.workouts.filter { workout in
            interval.contains(workout.date)
                && workout.status == .scheduled
                && workout.blueprint.kind.isRunning
        }.sorted { $0.date < $1.date }
        let missedSorted = situation.missedWorkouts.sorted { $0.date < $1.date }
        let missedIDs = Set(situation.missedWorkouts.map(\.id))

        for (index, missed) in missedSorted.enumerated() {
            guard index < extensionSlots.count else { break }
            let slot = extensionSlots[index]
            copy.workouts = copy.workouts.map { workout in
                guard workout.id == slot.id else { return workout }
                var replacement = missed
                replacement.id = slot.id
                replacement.blueprint.id = slot.blueprint.id
                replacement.blueprint.date = slot.date
                replacement.status = .scheduled
                return replacement
            }
        }

        copy.workouts = copy.workouts.map { workout in
            guard missedIDs.contains(workout.id), workout.status == .scheduled else { return workout }
            return AdaptationRules.applySkip(workout)
        }
        return copy
    }

    private static func eligibleToMove(_ missed: [ScheduledWorkout]) -> [ScheduledWorkout] {
        missed.filter { workout in
            workout.blueprint.kind != .longRun && !workout.blueprint.kind.isQuality
        }
    }

    private static func nextOpenDay(
        from start: Date,
        occupied: Set<Date>,
        calendar: Calendar,
        limitDays: Int = 21
    ) -> Date? {
        for offset in 0..<limitDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let normalized = calendar.startOfDay(for: day)
            if !occupied.contains(normalized) {
                return normalized
            }
        }
        return nil
    }
}
