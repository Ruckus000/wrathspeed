import Foundation

public enum PlanScheduleService {
    public static func canMove(
        workout: ScheduledWorkout,
        to date: Date,
        plan: TrainingPlan,
        calendar: Calendar = .current
    ) -> PlanMoveValidation {
        let target = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        guard target >= today else {
            return PlanMoveValidation(allowed: false, reason: "You can’t schedule runs in the past.")
        }
        let conflict = plan.workouts.contains {
            $0.id != workout.id && calendar.isDate($0.date, inSameDayAs: target) && $0.status == .scheduled
        }
        if conflict {
            return PlanMoveValidation(allowed: false, reason: "You already have a run that day.")
        }
        var warnings: [String] = []
        if workout.blueprint.kind == .longRun,
           !AdaptationRules.canMoveLongRun(from: workout.date, to: target) {
            return PlanMoveValidation(allowed: false, reason: "Long runs can only move within 48 hours.")
        }
        if AdaptationRules.wouldStackQuality(existing: plan.workouts, moving: workout, to: target, calendar: calendar) {
            warnings.append("That would stack two quality days.")
        }
        return PlanMoveValidation(allowed: true, warnings: warnings)
    }
}

public struct PlanMoveValidation: Equatable, Sendable {
    public var allowed: Bool
    public var reason: String?
    public var warnings: [String]

    public init(allowed: Bool, reason: String? = nil, warnings: [String] = []) {
        self.allowed = allowed
        self.reason = reason
        self.warnings = warnings
    }
}

public struct PlanUndoSnapshot: Codable, Equatable, Sendable {
    public var plan: TrainingPlan
    public var n100: N100Adjustment?

    public init(plan: TrainingPlan, n100: N100Adjustment?) {
        self.plan = plan
        self.n100 = n100
    }
}
