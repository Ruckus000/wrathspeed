import Foundation

/// Preserves completed decisions while allowing the future of a plan to be rebuilt.
public enum PlanReconciler {
    public static func reconcile(
        existing: TrainingPlan?,
        generated: TrainingPlan,
        asOf date: Date = Date(),
        calendar: Calendar = .current,
        freezeMileageBaselineMeters: Double? = nil
    ) -> TrainingPlan {
        guard let existing else { return capMileage(in: generated, from: date, calendar: calendar, baseline: freezeMileageBaselineMeters) }
        let today = calendar.startOfDay(for: date)
        let preserved = existing.workouts.filter { $0.date < today || $0.status != .scheduled }
        let replacement = generated.workouts.filter { candidate in
            !preserved.contains { calendar.isDate($0.date, inSameDayAs: candidate.date) }
        }
        var plan = generated
        plan.workouts = (preserved + replacement).sorted { $0.date < $1.date }
        return capMileage(in: plan, from: date, calendar: calendar, baseline: freezeMileageBaselineMeters)
    }

    private static func capMileage(
        in plan: TrainingPlan,
        from date: Date,
        calendar: Calendar,
        baseline: Double?
    ) -> TrainingPlan {
        guard let baseline, baseline.isFinite, baseline > 0 else { return plan }
        var result = plan
        let today = calendar.startOfDay(for: date)
        let indicesByWeek = Dictionary(grouping: result.workouts.indices.filter { index in
            let workout = result.workouts[index]
            return workout.status == .scheduled && workout.date >= today && workout.blueprint.kind.isRunning && workout.blueprint.kind != .race
        }) { index in
            calendar.dateInterval(of: .weekOfYear, for: result.workouts[index].date)?.start ?? result.workouts[index].date
        }
        for indices in indicesByWeek.values {
            let total = indices.reduce(0) { $0 + result.workouts[$1].blueprint.plannedDistanceMeters }
            guard total > baseline else { continue }
            let scale = baseline / total
            for index in indices { result.workouts[index] = scaled(result.workouts[index], by: scale) }
        }
        return result
    }

    private static func scaled(_ workout: ScheduledWorkout, by scale: Double) -> ScheduledWorkout {
        var workout = workout
        workout.blueprint.plannedDistanceMeters *= scale
        workout.blueprint.steps = workout.blueprint.steps.map { step in
            var step = step
            if case let .distance(meters) = step.target { step.target = .distance(meters: meters * scale) }
            return step
        }
        return workout
    }
}
