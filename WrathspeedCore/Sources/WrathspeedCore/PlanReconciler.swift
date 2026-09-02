import CryptoKit
import Foundation

/// Preserves completed decisions while allowing the future of a plan to be rebuilt.
public enum PlanReconciler {
    public enum Error: LocalizedError, Equatable, Sendable {
        case futureWorkoutIdentityUnmatched(UUID)
        case duplicateGeneratedIdentity

        public var errorDescription: String? {
            switch self {
            case let .futureWorkoutIdentityUnmatched(id):
                "The regenerated plan could not preserve future workout \(id)."
            case .duplicateGeneratedIdentity:
                "The regenerated plan contains duplicate workout identities."
            }
        }
    }

    public static func reconcile(
        existing: TrainingPlan?,
        generated: TrainingPlan,
        asOf date: Date = Date(),
        calendar: Calendar = .current,
        freezeMileageBaselineMeters: Double? = nil
    ) -> TrainingPlan {
        guard let existing else {
            return capMileage(in: generated, from: date, calendar: calendar, baseline: freezeMileageBaselineMeters)
        }
        let today = calendar.startOfDay(for: date)
        let preserved = existing.workouts.filter {
            $0.date < today || $0.status != .scheduled
        }
        let replacement = generated.workouts.filter { candidate in
            !preserved.contains { calendar.isDate($0.date, inSameDayAs: candidate.date) }
        }
        var plan = generated
        plan.workouts = (preserved + replacement).sorted { $0.date < $1.date }
        plan = capMileage(in: plan, from: date, calendar: calendar, baseline: freezeMileageBaselineMeters)
        return plan
    }

    /// Coach regeneration is stricter than ordinary plan regeneration. Existing future workout
    /// identities must map to a generated slot, while genuinely new slots receive deterministic
    /// identities. If an existing slot cannot be mapped, fail closed instead of silently replacing
    /// it and losing its reminder, result, or Watch identity.
    public static func reconcilePreservingFutureScheduledIdentity(
        existing: TrainingPlan?,
        generated: TrainingPlan,
        asOf date: Date = Date(),
        calendar: Calendar = .current,
        freezeMileageBaselineMeters: Double? = nil
    ) throws -> TrainingPlan {
        let plan = reconcile(
            existing: existing,
            generated: generated,
            asOf: date,
            calendar: calendar,
            freezeMileageBaselineMeters: freezeMileageBaselineMeters
        )
        guard let existing else { return plan }
        return try preservingFutureIdentity(from: existing, in: plan, asOf: date, calendar: calendar)
    }

    /// Coach regeneration changes generated blueprint content but must not silently create new
    /// scheduled-workout identities. Matching is by week, workout role, and occurrence so a
    /// long-run weekday move can retain the same workout and reminder/result identity.
    private static func preservingFutureIdentity(
        from existing: TrainingPlan,
        in generated: TrainingPlan,
        asOf date: Date,
        calendar: Calendar
    ) throws -> TrainingPlan {
        let today = calendar.startOfDay(for: date)
        let existingFuture = existing.workouts.filter {
            $0.date >= today && ($0.status == .scheduled || $0.status == .convertedToEasy)
        }
        guard Set(existingFuture.map(\.id)).count == existingFuture.count else {
            throw Error.duplicateGeneratedIdentity
        }

        var result = generated
        var usedExistingIDs = Set<UUID>()
        for index in result.workouts.indices {
            guard result.workouts[index].date >= today,
                  result.workouts[index].status == .scheduled || result.workouts[index].status == .convertedToEasy
            else { continue }

            let candidate = result.workouts[index]
            let match = existingFuture
                .filter { !usedExistingIDs.contains($0.id) }
                .filter {
                    slotFamily($0) == slotFamily(candidate)
                        && weekOffset(for: $0.date, from: today, calendar: calendar)
                            == weekOffset(for: candidate.date, from: today, calendar: calendar)
                }
                .sorted { lhs, rhs in
                    let leftDistance = abs(lhs.date.timeIntervalSince(candidate.date))
                    let rightDistance = abs(rhs.date.timeIntervalSince(candidate.date))
                    if leftDistance != rightDistance { return leftDistance < rightDistance }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .first

            var preserved = candidate
            if let match {
                usedExistingIDs.insert(match.id)
                preserved.id = match.id
                preserved.blueprint.id = match.blueprint.id
                if match.status == .convertedToEasy,
                   candidate.blueprint.kind.isQuality {
                    preserved = AdaptationRules.applySkip(candidate, convertQualityToEasy: true)
                    preserved.blueprint.id = match.blueprint.id
                    preserved.id = match.id
                }
                preserved.status = match.status
                preserved.result = match.result
                preserved.scheduledTimeMinutes = match.scheduledTimeMinutes
                preserved.reminderEnabled = match.reminderEnabled
            } else {
                let seed = identitySeed(for: candidate, index: index, calendar: calendar)
                preserved.id = stableUUID(for: "scheduled|\(seed)")
                preserved.blueprint.id = stableUUID(for: "blueprint|\(seed)")
            }
            result.workouts[index] = preserved
        }

        guard usedExistingIDs.count == existingFuture.count else {
            let unmatched = existingFuture.first { !usedExistingIDs.contains($0.id) }
            throw Error.futureWorkoutIdentityUnmatched(unmatched?.id ?? UUID())
        }
        guard Set(result.workouts.map(\.id)).count == result.workouts.count,
              Set(result.workouts.map(\.blueprint.id)).count == result.workouts.count
        else {
            throw Error.duplicateGeneratedIdentity
        }
        return result
    }

    private static func weekOffset(for date: Date, from anchor: Date, calendar: Calendar) -> Int {
        let anchorDay = calendar.startOfDay(for: anchor)
        let dateDay = calendar.startOfDay(for: date)
        guard let days = calendar.dateComponents([.day], from: anchorDay, to: dateDay).day else { return 0 }
        if days >= 0 { return days / 7 }
        return -(((-days) + 6) / 7)
    }

    private static func slotFamily(_ workout: ScheduledWorkout) -> String {
        if workout.status == .convertedToEasy || workout.blueprint.kind.isQuality { return "quality" }
        if workout.blueprint.kind == .longRun { return "longRun" }
        return workout.blueprint.kind.rawValue
    }

    private static func identitySeed(for workout: ScheduledWorkout, index: Int, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: workout.date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)|\(slotFamily(workout))|\(workout.blueprint.kind.rawValue)|\(workout.blueprint.title)|\(index)"
    }

    private static func stableUUID(for seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.prefix(16).map { String(format: "%02x", $0) }.joined()
        let value = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: value)!
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
