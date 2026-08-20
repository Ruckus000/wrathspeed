import Foundation

public struct OnboardingInputs: Equatable, Sendable {
    public var goalMode: GoalMode
    public var goalKind: GoalKind
    public var raceDate: Date?
    public var weekCount: Int
    public var unit: DistanceUnit
    public var ability: Ability
    public var weeklyDisplayDistance: Double
    public var longestDisplayDistance: Double
    public var availableDays: Set<Weekday>
    public var longRunDay: Weekday
    public var includesRecentPerformance: Bool
    public var recentDistanceDisplay: Double?
    public var recentDurationMinutes: Int?
    public var recentDurationSeconds: Int?
    public var strengthEnabled: Bool
    public var strength: StrengthPreferences
    public var mobility: MobilityPreferences

    public init(
        goalMode: GoalMode = .race,
        goalKind: GoalKind = .halfMarathon,
        raceDate: Date? = nil,
        weekCount: Int = 12,
        unit: DistanceUnit = .default(),
        ability: Ability = .intermediate,
        weeklyDisplayDistance: Double = 30,
        longestDisplayDistance: Double = 10,
        availableDays: Set<Weekday> = [.tuesday, .thursday, .saturday, .sunday],
        longRunDay: Weekday = .saturday,
        includesRecentPerformance: Bool = false,
        recentDistanceDisplay: Double? = nil,
        recentDurationMinutes: Int? = nil,
        recentDurationSeconds: Int? = nil,
        strengthEnabled: Bool = true,
        strength: StrengthPreferences = StrengthPreferences(),
        mobility: MobilityPreferences = MobilityPreferences()
    ) {
        self.goalMode = goalMode
        self.goalKind = goalKind
        self.raceDate = raceDate
        self.weekCount = weekCount
        self.unit = unit
        self.ability = ability
        self.weeklyDisplayDistance = weeklyDisplayDistance
        self.longestDisplayDistance = longestDisplayDistance
        self.availableDays = availableDays
        self.longRunDay = longRunDay
        self.includesRecentPerformance = includesRecentPerformance
        self.recentDistanceDisplay = recentDistanceDisplay
        self.recentDurationMinutes = recentDurationMinutes
        self.recentDurationSeconds = recentDurationSeconds
        self.strengthEnabled = strengthEnabled
        self.strength = strength
        self.mobility = mobility
    }

    public func makeGoal(calendar: Calendar, startDate: Date) -> TrainingGoal {
        switch goalMode {
        case .race:
            return TrainingGoal(kind: goalKind, raceDate: raceDate, weekCount: weekCount)
        case .distance:
            return TrainingGoal(kind: goalKind, weekCount: weekCount)
        case .newToRunning:
            return TrainingGoal(kind: .newToRunning, weekCount: weekCount)
        case .returnToRunning:
            return TrainingGoal(kind: .returnToRunning, weekCount: weekCount)
        }
    }

    public func makeProfile() -> RunnerProfile {
        let recentRace: RaceResult?
        if includesRecentPerformance,
           let distance = recentDistanceDisplay,
           let minutes = recentDurationMinutes,
           let seconds = recentDurationSeconds {
            let duration = TimeInterval(minutes * 60 + seconds)
            recentRace = RaceResult(
                distanceMeters: Units.meters(fromDisplay: distance, unit: unit),
                duration: duration
            )
        } else {
            recentRace = nil
        }

        return RunnerProfile(
            ability: ability,
            weeklyMileageMeters: Units.meters(fromDisplay: weeklyDisplayDistance, unit: unit),
            longestRunMeters: Units.meters(fromDisplay: longestDisplayDistance, unit: unit),
            daysPerWeek: availableDays.count,
            longRunWeekday: longRunDay,
            unit: unit,
            recentRace: recentRace,
            availableWeekdays: availableDays.sorted()
        )
    }

    public func makeStrengthPreferences() -> StrengthPreferences {
        guard strengthEnabled else {
            return StrengthPreferences(sessionsPerWeek: 0, preferredDays: [])
        }
        return strength
    }
}

public enum OnboardingValidationError: LocalizedError, Equatable, Sendable {
    case tooFewAvailableDays
    case longRunNotAvailable
    case missingRaceDate
    case missingRecentPerformance

    public var errorDescription: String? {
        switch self {
        case .tooFewAvailableDays: "Choose at least three run days."
        case .longRunNotAvailable: "Long run day must be one of your available run days."
        case .missingRaceDate: "Choose a race date."
        case .missingRecentPerformance: "Enter a recent race distance and time, or skip performance."
        }
    }
}

public enum OnboardingValidator {
    public static func validate(_ inputs: OnboardingInputs, startDate: Date = Date(), calendar: Calendar = .current) throws {
        guard inputs.availableDays.count >= 3 else { throw OnboardingValidationError.tooFewAvailableDays }
        guard inputs.availableDays.contains(inputs.longRunDay) else { throw OnboardingValidationError.longRunNotAvailable }
        if inputs.goalMode == .race && inputs.raceDate == nil {
            throw OnboardingValidationError.missingRaceDate
        }
        if inputs.includesRecentPerformance {
            guard inputs.recentDistanceDisplay != nil,
                  inputs.recentDurationMinutes != nil,
                  inputs.recentDurationSeconds != nil else {
                throw OnboardingValidationError.missingRecentPerformance
            }
        }
        let goal = inputs.makeGoal(calendar: calendar, startDate: startDate)
        let profile = inputs.makeProfile()
        var cal = calendar
        cal.timeZone = .current
        try PlanRequest(goal: goal, profile: profile, startDate: startDate, calendar: cal).validate()
    }
}

public struct OnboardingDraft: Equatable, Sendable {
    public var inputs: OnboardingInputs
    public var plan: TrainingPlan
    public var zones: PaceZones
    public var vdotSource: VDOTSource

    public enum VDOTSource: Equatable, Sendable {
        case recentPerformance
        case abilityEstimate
    }
}

public enum OnboardingDraftBuilder {
    public static func build(
        inputs: OnboardingInputs,
        catalog: StrengthCatalog,
        startDate: Date = Date(),
        calendar: Calendar = .current
    ) throws -> OnboardingDraft {
        try OnboardingValidator.validate(inputs, startDate: startDate, calendar: calendar)
        var cal = calendar
        cal.timeZone = .current
        let goal = inputs.makeGoal(calendar: cal, startDate: startDate)
        let profile = inputs.makeProfile()
        let request = PlanRequest(goal: goal, profile: profile, startDate: startDate, calendar: cal)
        let plan = try TrainingPlanService.regenerate(
            request: request,
            existingPlan: nil,
            adjustment: nil,
            freezeMileageBaselineMeters: nil,
            strengthPreferences: inputs.makeStrengthPreferences(),
            strengthCatalog: catalog
        )
        let vdotSource: OnboardingDraft.VDOTSource = inputs.includesRecentPerformance ? .recentPerformance : .abilityEstimate
        return OnboardingDraft(
            inputs: inputs,
            plan: plan.plan,
            zones: PaceCalculator.zones(vdot: profile.vdot),
            vdotSource: vdotSource
        )
    }
}
