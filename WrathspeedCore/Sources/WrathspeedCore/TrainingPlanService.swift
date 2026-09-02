import Foundation

public struct GeneratedTrainingSchedule: Equatable, Sendable {
    public var plan: TrainingPlan
    public var strengthSessions: [StrengthSession]

    public init(plan: TrainingPlan, strengthSessions: [StrengthSession]) {
        self.plan = plan
        self.strengthSessions = strengthSessions
    }
}

public enum TrainingPlanService {
    public static func regenerate(
        request: PlanRequest,
        existingPlan: TrainingPlan?,
        adjustment: N100Adjustment?,
        freezeMileageBaselineMeters: Double?,
        strengthPreferences: StrengthPreferences,
        strengthCatalog: StrengthCatalog,
        preserveFutureScheduledIdentity: Bool = false
    ) throws -> GeneratedTrainingSchedule {
        let basePlan = try PlanGenerator.generateValidated(request)
        let plan: TrainingPlan
        if preserveFutureScheduledIdentity {
            plan = try PlanReconciler.reconcilePreservingFutureScheduledIdentity(
                existing: existingPlan,
                generated: basePlan,
                asOf: request.startDate,
                calendar: request.calendar,
                freezeMileageBaselineMeters: freezeMileageBaselineMeters
            )
        } else {
            plan = PlanReconciler.reconcile(
                existing: existingPlan,
                generated: basePlan,
                asOf: request.startDate,
                calendar: request.calendar,
                freezeMileageBaselineMeters: freezeMileageBaselineMeters
            )
        }
        let strengthSessions = StrengthPlanner.schedule(
            preferences: strengthPreferences,
            startDate: request.startDate,
            weekCount: plan.goal.weekCount,
            calendar: request.calendar,
            catalog: strengthCatalog
        )
        return GeneratedTrainingSchedule(plan: plan, strengthSessions: strengthSessions)
    }
}
