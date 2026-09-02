import Foundation

/// The small, provider-neutral vocabulary understood by the coach. Apple Foundation Models
/// maps its typed response into this enum before any plan code runs.
public enum CoachIntent: Codable, Equatable, Sendable {
    case cutIntensity
    case reshapeForTravel(travelDates: [Date])
    case retargetVDOT(target: Double)
    case moveLongRun(to: Weekday)
    case moveWorkoutIndoors(workoutID: UUID)
    case clarificationRequired
    case answerOnly

    private enum CodingKeys: String, CodingKey {
        case kind, travelDates, target, weekday, workoutID
    }

    private enum Kind: String, Codable {
        case cutIntensity
        case reshapeForTravel
        case retargetVDOT
        case moveLongRun
        case moveWorkoutIndoors
        case clarificationRequired
        case answerOnly
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .cutIntensity: self = .cutIntensity
        case .reshapeForTravel:
            self = .reshapeForTravel(travelDates: try values.decode([Date].self, forKey: .travelDates))
        case .retargetVDOT:
            self = .retargetVDOT(target: try values.decode(Double.self, forKey: .target))
        case .moveLongRun:
            self = .moveLongRun(to: try values.decode(Weekday.self, forKey: .weekday))
        case .moveWorkoutIndoors:
            self = .moveWorkoutIndoors(workoutID: try values.decode(UUID.self, forKey: .workoutID))
        case .clarificationRequired: self = .clarificationRequired
        case .answerOnly: self = .answerOnly
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cutIntensity:
            try values.encode(Kind.cutIntensity, forKey: .kind)
        case let .reshapeForTravel(travelDates):
            try values.encode(Kind.reshapeForTravel, forKey: .kind)
            try values.encode(travelDates, forKey: .travelDates)
        case let .retargetVDOT(target):
            try values.encode(Kind.retargetVDOT, forKey: .kind)
            try values.encode(target, forKey: .target)
        case let .moveLongRun(to):
            try values.encode(Kind.moveLongRun, forKey: .kind)
            try values.encode(to, forKey: .weekday)
        case let .moveWorkoutIndoors(workoutID):
            try values.encode(Kind.moveWorkoutIndoors, forKey: .kind)
            try values.encode(workoutID, forKey: .workoutID)
        case .clarificationRequired:
            try values.encode(Kind.clarificationRequired, forKey: .kind)
        case .answerOnly:
            try values.encode(Kind.answerOnly, forKey: .kind)
        }
    }

    public var displayTitle: String {
        switch self {
        case .cutIntensity: "Adjusted for soreness"
        case .reshapeForTravel: "Reshaped around travel"
        case .retargetVDOT: "Updated pace targets"
        case .moveLongRun: "Moved long run"
        case .moveWorkoutIndoors: "Moved workout indoors"
        case .clarificationRequired: "More information needed"
        case .answerOnly: "Coach response"
        }
    }
}

/// A redacted, deterministic context. Workout IDs are retained for local resolution only;
/// providers should serialize `reference` and never expose the UUID to a model.
public struct CoachContext: Codable, Equatable, Sendable {
    public struct WorkoutReference: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var reference: String
        public var date: Date
        public var kind: WorkoutKind
        public var title: String
        public var status: WorkoutStatus
        public var plannedDistanceMeters: Double
        public var location: RunLocation

        public init(
            id: UUID,
            reference: String,
            date: Date,
            kind: WorkoutKind,
            title: String,
            status: WorkoutStatus,
            plannedDistanceMeters: Double,
            location: RunLocation
        ) {
            self.id = id
            self.reference = reference
            self.date = date
            self.kind = kind
            self.title = title
            self.status = status
            self.plannedDistanceMeters = plannedDistanceMeters
            self.location = location
        }
    }

    public struct ResultSummary: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var date: Date
        public var distanceMeters: Double
        public var averagePaceSecPerKm: Double?
        public var heartRateAverage: Double?

        public init(
            id: UUID,
            date: Date,
            distanceMeters: Double,
            averagePaceSecPerKm: Double?,
            heartRateAverage: Double?
        ) {
            self.id = id
            self.date = date
            self.distanceMeters = distanceMeters
            self.averagePaceSecPerKm = averagePaceSecPerKm
            self.heartRateAverage = heartRateAverage
        }
    }

    public var asOf: Date
    public var goal: TrainingGoal
    public var profile: RunnerProfile
    public var currentWeekStart: Date
    public var workouts: [WorkoutReference]
    public var recentResults: [ResultSummary]
    public var adherence: Double

    public init(
        asOf: Date,
        goal: TrainingGoal,
        profile: RunnerProfile,
        currentWeekStart: Date,
        workouts: [WorkoutReference],
        recentResults: [ResultSummary],
        adherence: Double
    ) {
        self.asOf = asOf
        self.goal = goal
        self.profile = profile
        self.currentWeekStart = currentWeekStart
        self.workouts = workouts
        self.recentResults = recentResults
        self.adherence = adherence
    }
}

public enum CoachWarningSeverity: String, Codable, CaseIterable, Sendable {
    case soft
    case blocking
}

public struct CoachProposalWarning: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var severity: CoachWarningSeverity
    public var message: String

    public init(id: UUID = UUID(), severity: CoachWarningSeverity, message: String) {
        self.id = id
        self.severity = severity
        self.message = message
    }
}

public enum CoachChangeKind: String, Codable, CaseIterable, Sendable {
    case updated
    case moved
    case removed
    case added
}

public struct CoachProposalChange: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var workoutID: UUID?
    public var reference: String
    public var kind: CoachChangeKind
    public var before: String
    public var after: String

    public init(
        id: UUID = UUID(),
        workoutID: UUID? = nil,
        reference: String,
        kind: CoachChangeKind,
        before: String,
        after: String
    ) {
        self.id = id
        self.workoutID = workoutID
        self.reference = reference
        self.kind = kind
        self.before = before
        self.after = after
    }
}

public struct CoachPlanRuleResult: Equatable, Sendable {
    public var plan: TrainingPlan
    public var changes: [CoachProposalChange]
    public var warnings: [CoachProposalWarning]

    public init(
        plan: TrainingPlan,
        changes: [CoachProposalChange],
        warnings: [CoachProposalWarning] = []
    ) {
        self.plan = plan
        self.changes = changes
        self.warnings = warnings
    }
}

public enum CoachPlanRuleError: LocalizedError, Equatable, Sendable {
    case travelDatesRequired
    case noSafeTravelSchedule
    case noEligibleWorkout(String)
    case workoutNotFound
    case workoutAlreadyStarted
    case invalidDateInput
    case invalidPlan(String)
    case invalidProfile(String)
    case targetWeekdayUnavailable
    case invalidVDOT
    case vdotDecreaseExceedsLimit
    case protectedWorkoutChanged
    case noChanges
    case unsupportedIntent

    public var errorDescription: String? {
        switch self {
        case .travelDatesRequired:
            "Tell me the exact travel dates before I reshape the plan."
        case .noSafeTravelSchedule:
            "I couldn’t find a safe open day for every quality workout during travel."
        case let .noEligibleWorkout(message):
            message
        case .workoutNotFound:
            "I couldn’t find that workout in the current plan."
        case .workoutAlreadyStarted:
            "Only future, unstarted workouts can be edited."
        case .invalidDateInput:
            "The coach received an invalid date."
        case let .invalidPlan(message):
            message
        case let .invalidProfile(message):
            message
        case .targetWeekdayUnavailable:
            "That weekday is not one of your available run days."
        case .invalidVDOT:
            "The new VDOT must be a finite value greater than zero."
        case .vdotDecreaseExceedsLimit:
            "VDOT changes are limited to 3% in either direction."
        case .protectedWorkoutChanged:
            "Completed and past workouts must remain unchanged."
        case .noChanges:
            "That request would not change the current plan."
        case .unsupportedIntent:
            "This coach response is not a plan-editing request."
        }
    }
}

public struct CoachVDOTAdjustment: Equatable, Sendable {
    public var effectiveTarget: Double
    public var warnings: [CoachProposalWarning]

    public init(effectiveTarget: Double, warnings: [CoachProposalWarning] = []) {
        self.effectiveTarget = effectiveTarget
        self.warnings = warnings
    }
}

public enum CoachPlanRules {
    public static let vdotChangeLimit = AdaptationRules.vdotNudge

    public static func validateVDOT(current: Double, requested: Double) throws -> CoachVDOTAdjustment {
        guard current.isFinite, current > 0, requested.isFinite, requested > 0 else {
            throw CoachPlanRuleError.invalidVDOT
        }
        let delta = (requested - current) / current
        // Keep the mathematical boundary stable across floating-point representations.
        let boundaryTolerance = 1e-12
        if delta < -vdotChangeLimit - boundaryTolerance {
            throw CoachPlanRuleError.vdotDecreaseExceedsLimit
        }
        if delta > vdotChangeLimit + boundaryTolerance {
            let capped = current * (1 + vdotChangeLimit)
            return CoachVDOTAdjustment(
                effectiveTarget: capped,
                warnings: [CoachProposalWarning(
                    severity: .soft,
                    message: "The increase was capped at 3% to protect adaptation."
                )]
            )
        }
        return CoachVDOTAdjustment(effectiveTarget: requested)
    }

    public static func validateLongRunWeekday(
        _ target: Weekday,
        profile: RunnerProfile
    ) throws {
        guard profile.resolvedRunWeekdays().contains(target) else {
            throw CoachPlanRuleError.targetWeekdayUnavailable
        }
    }

    public static func preview(
        intent: CoachIntent,
        plan: TrainingPlan,
        profile: RunnerProfile,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) throws -> CoachPlanRuleResult {
        guard asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw CoachPlanRuleError.invalidDateInput
        }
        try validatePlanIntegrity(plan)
        try validateProfile(profile)
        let result: CoachPlanRuleResult
        switch intent {
        case .cutIntensity:
            result = try cutIntensity(plan: plan, asOf: asOf, calendar: calendar)
        case let .reshapeForTravel(travelDates):
            result = try reshapeForTravel(plan: plan, profile: profile, travelDates: travelDates, asOf: asOf, calendar: calendar)
        case let .moveWorkoutIndoors(workoutID):
            result = try moveWorkoutIndoors(plan: plan, workoutID: workoutID, asOf: asOf, calendar: calendar)
        case let .retargetVDOT(target):
            let adjustment = try validateVDOT(current: profile.vdot, requested: target)
            guard adjustment.effectiveTarget != profile.vdot else {
                throw CoachPlanRuleError.noChanges
            }
            var proposed = plan
            proposed.profile.vdot = adjustment.effectiveTarget
            var changes = changes(from: plan, to: proposed, asOf: asOf, calendar: calendar)
            changes.append(CoachProposalChange(
                reference: "PROFILE",
                kind: .updated,
                before: "VDOT \(String(format: "%.1f", profile.vdot))",
                after: "VDOT \(String(format: "%.1f", adjustment.effectiveTarget))"
            ))
            guard !changes.isEmpty else { throw CoachPlanRuleError.noChanges }
            result = CoachPlanRuleResult(plan: proposed, changes: changes, warnings: adjustment.warnings)
        case let .moveLongRun(to):
            try validateLongRunWeekday(to, profile: profile)
            throw CoachPlanRuleError.unsupportedIntent
        case .clarificationRequired, .answerOnly:
            throw CoachPlanRuleError.unsupportedIntent
        }
        try validateProtectedWorkoutsUnchanged(
            current: plan,
            proposed: result.plan,
            asOf: asOf,
            calendar: calendar
        )
        return result
    }

    public static func validateProtectedWorkoutsUnchanged(
        current: TrainingPlan,
        proposed: TrainingPlan,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        guard asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw CoachPlanRuleError.invalidDateInput
        }
        let currentIDs = current.workouts.map(\.id)
        guard Set(currentIDs).count == currentIDs.count else {
            throw CoachPlanRuleError.invalidPlan("The current plan contains duplicate workout IDs.")
        }
        let proposedIDs = proposed.workouts.map(\.id)
        guard Set(proposedIDs).count == proposedIDs.count else {
            throw CoachPlanRuleError.invalidPlan("The proposed plan contains duplicate workout IDs.")
        }
        let proposedByID = Dictionary(uniqueKeysWithValues: proposed.workouts.map { ($0.id, $0) })
        for workout in current.workouts where !isUnstarted(workout, asOf: asOf, calendar: calendar) {
            guard proposedByID[workout.id] == workout else {
                throw CoachPlanRuleError.protectedWorkoutChanged
            }
        }
    }

    public static func validatePlanIntegrity(_ plan: TrainingPlan) throws {
        try validateProfile(plan.profile)
        guard plan.goal.weekCount >= plan.goal.kind.minimumWeeks,
              plan.goal.weekCount <= 26,
              plan.goal.raceDate?.timeIntervalSinceReferenceDate.isFinite ?? true
        else {
            throw CoachPlanRuleError.invalidPlan("The current plan contains invalid goal data.")
        }
        let workoutIDs = plan.workouts.map(\.id)
        guard Set(workoutIDs).count == workoutIDs.count else {
            throw CoachPlanRuleError.invalidPlan("The current plan contains duplicate workout IDs.")
        }
        let blueprintIDs = plan.workouts.map(\.blueprint.id)
        guard Set(blueprintIDs).count == blueprintIDs.count else {
            throw CoachPlanRuleError.invalidPlan("The current plan contains duplicate workout references.")
        }
        guard plan.workouts.allSatisfy({ workout in
            workout.date.timeIntervalSinceReferenceDate.isFinite
                && workout.blueprint.date.timeIntervalSinceReferenceDate.isFinite
                && workout.blueprint.plannedDistanceMeters.isFinite
                && workout.blueprint.plannedDistanceMeters >= 0
                && workout.blueprint.steps.allSatisfy { step in
                    switch step.target {
                    case let .distance(meters): meters.isFinite && meters >= 0
                    case let .duration(seconds): seconds.isFinite && seconds >= 0
                    }
                }
        }) else {
            throw CoachPlanRuleError.invalidPlan("The current plan contains invalid workout data.")
        }
    }

    public static func validateProfile(_ profile: RunnerProfile) throws {
        guard profile.weeklyMileageMeters.isFinite,
              profile.weeklyMileageMeters > 0,
              profile.longestRunMeters.isFinite,
              profile.longestRunMeters > 0,
              profile.vdot.isFinite,
              profile.vdot > 0,
              (3...6).contains(profile.daysPerWeek)
        else {
            throw CoachPlanRuleError.invalidProfile("The runner profile contains invalid training data.")
        }
        if let weekdays = profile.availableWeekdays, !weekdays.isEmpty {
            guard Set(weekdays).count == weekdays.count else {
                throw CoachPlanRuleError.invalidProfile("The runner profile contains duplicate run days.")
            }
            guard (3...6).contains(weekdays.count), weekdays.contains(profile.longRunWeekday) else {
                throw CoachPlanRuleError.invalidProfile("The runner profile has an invalid set of available run days.")
            }
        }
        guard profile.longestRunMeters <= profile.weeklyMileageMeters else {
            throw CoachPlanRuleError.invalidProfile("The longest run cannot exceed weekly mileage.")
        }
        if let recentRace = profile.recentRace {
            guard recentRace.distanceMeters.isFinite,
                  recentRace.distanceMeters > 0,
                  recentRace.duration.isFinite,
                  recentRace.duration > 0
            else {
                throw CoachPlanRuleError.invalidProfile("The recent race data is invalid.")
            }
        }
        guard !profile.resolvedRunWeekdays().isEmpty else {
            throw CoachPlanRuleError.invalidProfile("The runner profile has no available run days.")
        }
    }

    public static func changes(
        from current: TrainingPlan,
        to proposed: TrainingPlan,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> [CoachProposalChange] {
        let today = calendar.startOfDay(for: asOf)
        let currentIDs = current.workouts.map(\.id)
        let proposedIDs = proposed.workouts.map(\.id)
        guard Set(currentIDs).count == currentIDs.count,
              Set(proposedIDs).count == proposedIDs.count
        else { return [] }
        let currentWorkouts = Dictionary(uniqueKeysWithValues: current.workouts.map { ($0.id, $0) })
        let proposedWorkouts = Dictionary(uniqueKeysWithValues: proposed.workouts.map { ($0.id, $0) })
        // Same numbering the model was shown -- see `references(in:asOf:calendar:limit:)`.
        let currentRefs = Dictionary(
            uniqueKeysWithValues: references(in: current, asOf: asOf, calendar: calendar)
                .map { ($0.workout.id, $0.reference) }
        )
        let proposedRefs = Dictionary(
            uniqueKeysWithValues: references(in: proposed, asOf: asOf, calendar: calendar)
                .map { ($0.workout.id, $0.reference) }
        )

        var result: [CoachProposalChange] = []
        for id in Set(currentWorkouts.keys).union(proposedWorkouts.keys) {
            let before = currentWorkouts[id]
            let after = proposedWorkouts[id]
            if let before, !isUnstarted(before, asOf: asOf, calendar: calendar), after != before { continue }

            switch (before, after) {
            case let (before?, after?) where before == after:
                continue
            case let (before?, after?):
                let moved = !calendar.isDate(before.date, inSameDayAs: after.date)
                result.append(CoachProposalChange(
                    workoutID: id,
                    reference: currentRefs[id] ?? proposedRefs[id] ?? "workout",
                    kind: moved ? .moved : .updated,
                    before: summary(before, calendar: calendar),
                    after: summary(after, calendar: calendar)
                ))
            case let (before?, nil):
                guard before.date >= today, isUnstarted(before, asOf: asOf, calendar: calendar) else { continue }
                result.append(CoachProposalChange(
                    workoutID: id,
                    reference: currentRefs[id] ?? "workout",
                    kind: .removed,
                    before: summary(before, calendar: calendar),
                    after: "Removed"
                ))
            case let (nil, after?):
                guard after.date >= today, isUnstarted(after, asOf: asOf, calendar: calendar) else { continue }
                result.append(CoachProposalChange(
                    workoutID: id,
                    reference: proposedRefs[id] ?? "workout",
                    kind: .added,
                    before: "Not scheduled",
                    after: summary(after, calendar: calendar)
                ))
            case (nil, nil):
                continue
            }
        }
        return result.sorted { $0.reference < $1.reference }
    }

    private static func cutIntensity(
        plan: TrainingPlan,
        asOf: Date,
        calendar: Calendar
    ) throws -> CoachPlanRuleResult {
        let today = calendar.startOfDay(for: asOf)
        // The next seven days, not the calendar week. `weekOfYear` starts on Sunday, and the
        // generator puts a week's one quality session on its earliest run day -- so once that
        // day had passed, "make this week safer" found nothing until the week rolled over.
        // Asked on a Wednesday, a runner means Wednesday through Tuesday.
        guard let windowEnd = calendar.date(byAdding: .day, value: 7, to: today)
        else { throw CoachPlanRuleError.noEligibleWorkout("I couldn’t work out the next seven days.") }

        let window = plan.workouts.filter {
            isUnstarted($0, asOf: asOf, calendar: calendar) && $0.date >= today && $0.date < windowEnd
        }
        guard let quality = window.filter({ $0.blueprint.kind.isQuality && $0.blueprint.kind != .race }).sorted(by: dateOrder).first else {
            throw CoachPlanRuleError.noEligibleWorkout("There is no unstarted quality workout in the next seven days to convert.")
        }
        // Date order here too. `first(where:)` on array order picked whichever long run was
        // stored first, which stops being the soonest one after any reschedule.
        guard let longRun = window.filter({ $0.blueprint.kind == .longRun }).sorted(by: dateOrder).first else {
            throw CoachPlanRuleError.noEligibleWorkout("There is no unstarted long run in the next seven days to reduce.")
        }

        var proposed = plan
        proposed.workouts = proposed.workouts.map { workout in
            if workout.id == quality.id {
                var converted = AdaptationRules.applySkip(workout, convertQualityToEasy: true)
                // Coach edits must preserve the scheduled workout and result identity even when
                // the existing engine rebuilds the easy-run blueprint.
                converted.blueprint.id = workout.blueprint.id
                return converted
            }
            if workout.id == longRun.id {
                return scaled(workout, by: 0.8)
            }
            return workout
        }
        let changes = changes(from: plan, to: proposed, asOf: asOf, calendar: calendar)
        guard !changes.isEmpty else { throw CoachPlanRuleError.noChanges }
        return CoachPlanRuleResult(plan: proposed, changes: changes)
    }

    private static func reshapeForTravel(
        plan: TrainingPlan,
        profile: RunnerProfile,
        travelDates: [Date],
        asOf: Date,
        calendar: Calendar
    ) throws -> CoachPlanRuleResult {
        guard !travelDates.isEmpty else { throw CoachPlanRuleError.travelDatesRequired }
        guard travelDates.allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }) else {
            throw CoachPlanRuleError.invalidDateInput
        }
        let normalizedTravelDates = travelDates.map { calendar.startOfDay(for: $0) }
        guard Set(normalizedTravelDates).count == normalizedTravelDates.count,
              zip(normalizedTravelDates, normalizedTravelDates.dropFirst()).allSatisfy({ $0 < $1 })
        else {
            throw CoachPlanRuleError.invalidDateInput
        }
        let travelDays = Set(normalizedTravelDates)
        let today = calendar.startOfDay(for: asOf)
        var proposed = plan

        // Easy filler is the first thing to give up during travel. Completed work, races, and
        // long runs are intentionally untouched.
        proposed.workouts.removeAll { workout in
            travelDays.contains(calendar.startOfDay(for: workout.date))
                && isUnstarted(workout, asOf: asOf, calendar: calendar)
                && workout.blueprint.kind == .easy
        }

        let conflictingQuality = proposed.workouts
            .filter { travelDays.contains(calendar.startOfDay(for: $0.date)) && isUnstarted($0, asOf: asOf, calendar: calendar) && $0.blueprint.kind.isQuality && $0.blueprint.kind != .race }
            .sorted(by: dateOrder)
        for quality in conflictingQuality {
            guard proposed.workouts.contains(where: { $0.id == quality.id }) else { continue }
            let target = try nearestSafeTravelDay(
                for: quality,
                in: proposed,
                profile: profile,
                travelDays: travelDays,
                asOf: today,
                calendar: calendar
            )

            let targetWorkouts = proposed.workouts.filter { isUnstarted($0, asOf: asOf, calendar: calendar) && calendar.isDate($0.date, inSameDayAs: target) }
            if let easy = targetWorkouts.first(where: { $0.blueprint.kind == .easy }),
               let easyIndex = proposed.workouts.firstIndex(where: { $0.id == easy.id }) {
                proposed.workouts.remove(at: easyIndex)
            }
            guard let refreshedIndex = proposed.workouts.firstIndex(where: { $0.id == quality.id }) else {
                throw CoachPlanRuleError.noSafeTravelSchedule
            }
            var moved = proposed.workouts[refreshedIndex]
            moved.blueprint.date = target
            proposed.workouts[refreshedIndex] = moved
        }
        proposed.workouts.sort { $0.date < $1.date }

        let changes = changes(from: plan, to: proposed, asOf: asOf, calendar: calendar)
        guard !changes.isEmpty else { throw CoachPlanRuleError.noChanges }
        return CoachPlanRuleResult(plan: proposed, changes: changes)
    }

    private static func moveWorkoutIndoors(
        plan: TrainingPlan,
        workoutID: UUID,
        asOf: Date,
        calendar: Calendar
    ) throws -> CoachPlanRuleResult {
        guard let workout = plan.workouts.first(where: { $0.id == workoutID }) else {
            throw CoachPlanRuleError.workoutNotFound
        }
        guard isUnstarted(workout, asOf: asOf, calendar: calendar) else {
            throw CoachPlanRuleError.workoutAlreadyStarted
        }
        guard workout.blueprint.kind.isRunning else {
            throw CoachPlanRuleError.noEligibleWorkout("Only running workouts can be moved to a treadmill.")
        }
        guard workout.blueprint.location != .treadmill else { throw CoachPlanRuleError.noChanges }

        var proposed = plan
        proposed.workouts = proposed.workouts.map { workout in
            guard workout.id == workoutID else { return workout }
            var copy = workout
            copy.blueprint.location = .treadmill
            return copy
        }
        let changes = changes(from: plan, to: proposed, asOf: asOf, calendar: calendar)
        guard !changes.isEmpty else { throw CoachPlanRuleError.noChanges }
        return CoachPlanRuleResult(plan: proposed, changes: changes)
    }

    private static func nearestSafeTravelDay(
        for workout: ScheduledWorkout,
        in plan: TrainingPlan,
        profile: RunnerProfile,
        travelDays: Set<Date>,
        asOf: Date,
        calendar: Calendar
    ) throws -> Date {
        let maxDate = plan.workouts.map(\.date).max() ?? asOf
        let maxDistance = min(366, max(14, calendar.dateComponents([.day], from: asOf, to: maxDate).day ?? 14))
        for offset in 1...maxDistance {
            for signedOffset in [offset, -offset] {
                guard let candidate = calendar.date(byAdding: .day, value: signedOffset, to: workout.date) else { continue }
                let day = calendar.startOfDay(for: candidate)
                guard day >= asOf,
                      day <= maxDate,
                      !travelDays.contains(day),
                      profile.resolvedRunWeekdays().contains(Weekday(rawValue: calendar.component(.weekday, from: day)) ?? .sunday)
                else { continue }
                if let goalDate = plan.goal.raceDate, calendar.isDate(goalDate, inSameDayAs: day) {
                    continue
                }

                let occupants = plan.workouts.filter { isUnstarted($0, asOf: asOf, calendar: calendar) && calendar.isDate($0.date, inSameDayAs: day) }
                guard occupants.allSatisfy({ $0.id == workout.id || $0.blueprint.kind == .easy }) else { continue }
                let otherQuality = plan.workouts.contains {
                    $0.id != workout.id
                        && isUnstarted($0, asOf: asOf, calendar: calendar)
                        && $0.blueprint.kind.isQuality
                        && abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.date), to: day).day ?? 99) == 1
                }
                guard !otherQuality else { continue }
                return day
            }
        }
        throw CoachPlanRuleError.noSafeTravelSchedule
    }

    /// The workouts the coach can talk about, in the order the model sees them, each with its
    /// `wN` handle.
    ///
    /// One function, used by the prompt context and by the proposal diff, so a reference on the
    /// card is always the workout the model was shown. It numbered *every* workout before,
    /// completed ones included, and the prompt then took the first 28 -- so late in a plan the
    /// model was handed forty finished runs and not one it could act on.
    ///
    /// Only unstarted workouts are numbered: a completed run is not something the coach can edit,
    /// and showing it invites the model to reference it. `limit` is the model's window; the
    /// proposal diff passes `nil` so a regeneration that reaches past `w28` still labels every
    /// row. The two agree on every number they share because they share the filter and order.
    public static func references(
        in plan: TrainingPlan,
        asOf: Date,
        calendar: Calendar,
        limit: Int? = nil
    ) -> [(workout: ScheduledWorkout, reference: String)] {
        let eligible = plan.workouts
            .filter { isUnstarted($0, asOf: asOf, calendar: calendar) }
            .sorted(by: dateOrder)
        let shown = limit.map { Array(eligible.prefix($0)) } ?? eligible
        return shown.enumerated().map { (workout: $0.element, reference: "w\($0.offset + 1)") }
    }

    /// The window the prompt renders. Kept here rather than in the provider so the context
    /// builder and the diff cannot disagree about it.
    public static let modelReferenceLimit = 28

    private static func isUnstarted(
        _ workout: ScheduledWorkout,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        workout.date >= calendar.startOfDay(for: asOf)
            && (workout.status == .scheduled || workout.status == .convertedToEasy)
    }

    private static func scaled(_ workout: ScheduledWorkout, by factor: Double) -> ScheduledWorkout {
        var copy = workout
        copy.blueprint.plannedDistanceMeters *= factor
        copy.blueprint.steps = copy.blueprint.steps.map { step in
            var step = step
            if case let .distance(meters) = step.target {
                step.target = .distance(meters: meters * factor)
            }
            return step
        }
        return copy
    }

    private static func summary(_ workout: ScheduledWorkout, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let kilometers = workout.blueprint.plannedDistanceMeters / 1_000
        var fields = [
            formatter.string(from: workout.date),
            workout.blueprint.kind.rawValue,
            workout.blueprint.title,
            String(format: "%.1f km", kilometers),
            workout.blueprint.location.rawValue,
            workout.reminderEnabled ? "reminder on" : "reminder off"
        ]
        if let minutes = workout.scheduledTimeMinutes {
            fields.append(String(format: "%02d:%02d", minutes / 60, minutes % 60))
        }
        if !workout.blueprint.steps.isEmpty {
            let steps = workout.blueprint.steps.map { step in
                let target: String
                switch step.target {
                case let .distance(meters): target = String(format: "%.0f m", meters)
                case let .duration(seconds): target = String(format: "%.0f s", seconds)
                }
                let intensity: String
                switch step.intensity {
                case let .zone(zone): intensity = zone.rawValue
                case let .rpe(value): intensity = "RPE \(value)"
                case .none: intensity = "none"
                }
                return "\(step.name): \(target) @ \(intensity)"
            }.joined(separator: "; ")
            fields.append("steps [\(steps)]")
        }
        return fields.joined(separator: " · ")
    }

    private static func dateOrder(_ lhs: ScheduledWorkout, _ rhs: ScheduledWorkout) -> Bool {
        lhs.date < rhs.date
    }
}

public struct CoachProposal: Equatable, Sendable, Identifiable {
    public var id: UUID
    /// The compiler context is part of the approval token. Revalidation must not silently
    /// choose a different local day after the proposal crosses midnight or a time-zone change.
    public var evaluatedAt: Date
    public var calendarTimeZoneIdentifier: String
    public var intent: CoachIntent
    public var title: String
    public var rationale: String
    public var changes: [CoachProposalChange]
    public var warnings: [CoachProposalWarning]
    public var basePlan: TrainingPlan
    public var baseProfile: RunnerProfile
    public var baseN100: N100Adjustment?
    public var proposedPlan: TrainingPlan
    public var proposedProfile: RunnerProfile
    public var proposedN100: N100Adjustment?

    public init(
        id: UUID = UUID(),
        evaluatedAt: Date = Date(),
        calendarTimeZoneIdentifier: String = TimeZone.current.identifier,
        intent: CoachIntent,
        title: String? = nil,
        rationale: String,
        changes: [CoachProposalChange],
        warnings: [CoachProposalWarning] = [],
        basePlan: TrainingPlan,
        baseProfile: RunnerProfile,
        baseN100: N100Adjustment?,
        proposedPlan: TrainingPlan,
        proposedProfile: RunnerProfile,
        proposedN100: N100Adjustment?
    ) {
        self.id = id
        self.evaluatedAt = evaluatedAt
        self.calendarTimeZoneIdentifier = calendarTimeZoneIdentifier
        self.intent = intent
        self.title = title ?? intent.displayTitle
        self.rationale = rationale
        self.changes = changes
        self.warnings = warnings
        self.basePlan = basePlan
        self.baseProfile = baseProfile
        self.baseN100 = baseN100
        self.proposedPlan = proposedPlan
        self.proposedProfile = proposedProfile
        self.proposedN100 = proposedN100
    }

    public var blockingWarnings: [CoachProposalWarning] {
        warnings.filter { $0.severity == .blocking }
    }

    public var softWarnings: [CoachProposalWarning] {
        warnings.filter { $0.severity == .soft }
    }

    public var isApplicable: Bool {
        !changes.isEmpty && blockingWarnings.isEmpty
    }
}

public enum CoachApplyResult: Equatable, Sendable {
    case applied
    case rejected(reason: String)

    public var didApply: Bool {
        if case .applied = self { return true }
        return false
    }
}
