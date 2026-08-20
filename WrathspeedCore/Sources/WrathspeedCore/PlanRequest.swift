import Foundation

public struct PlanRequest: Equatable, Sendable {
    public var goal: TrainingGoal
    public var profile: RunnerProfile
    public var startDate: Date
    public var calendar: Calendar
    public var location: RunLocation

    public init(
        goal: TrainingGoal,
        profile: RunnerProfile,
        startDate: Date,
        calendar: Calendar = .current,
        location: RunLocation = .outdoor
    ) {
        self.goal = goal
        self.profile = profile
        self.startDate = startDate
        self.calendar = calendar
        self.location = location
    }
}

public enum PlanInputError: LocalizedError, Equatable, Sendable {
    case invalidWeeklyMileage
    case invalidLongestRun
    case longestRunExceedsWeeklyMileage
    case invalidRaceResult
    case invalidVDOT
    case longRunNotInAvailableDays
    case raceDateTooSoon(minimumWeeks: Int)
    case raceDateTooFar(maximumWeeks: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidWeeklyMileage: "Weekly mileage must be greater than zero."
        case .invalidLongestRun: "Longest recent run must be greater than zero."
        case .longestRunExceedsWeeklyMileage: "Longest recent run cannot exceed weekly mileage."
        case .invalidRaceResult: "Recent race distance and time must be greater than zero."
        case .invalidVDOT: "Fitness estimate must be greater than zero."
        case .longRunNotInAvailableDays: "Long run day must be one of your available run days."
        case let .raceDateTooSoon(minimumWeeks): "Race date must be at least \(minimumWeeks) weeks away."
        case let .raceDateTooFar(maximumWeeks): "Race date must be within \(maximumWeeks) weeks."
        }
    }
}

public extension PlanRequest {
    func validate() throws {
        let profile = profile
        guard profile.weeklyMileageMeters.isFinite, profile.weeklyMileageMeters > 0 else { throw PlanInputError.invalidWeeklyMileage }
        guard profile.longestRunMeters.isFinite, profile.longestRunMeters > 0 else { throw PlanInputError.invalidLongestRun }
        guard profile.longestRunMeters <= profile.weeklyMileageMeters else { throw PlanInputError.longestRunExceedsWeeklyMileage }
        if let recent = profile.recentRace,
           !recent.distanceMeters.isFinite || !recent.duration.isFinite || recent.distanceMeters <= 0 || recent.duration <= 0 {
            throw PlanInputError.invalidRaceResult
        }
        guard profile.vdot.isFinite, profile.vdot > 0 else { throw PlanInputError.invalidVDOT }
        if let available = profile.availableWeekdays, !available.isEmpty,
           !available.contains(profile.longRunWeekday) {
            throw PlanInputError.longRunNotInAvailableDays
        }
        guard !goal.kind.isBeginner, let raceDate = goal.raceDate else { return }
        let start = calendar.startOfDay(for: startDate)
        let race = calendar.startOfDay(for: raceDate)
        let minimum = goal.kind.minimumWeeks * 7
        let days = calendar.dateComponents([.day], from: start, to: race).day ?? 0
        guard days >= minimum else { throw PlanInputError.raceDateTooSoon(minimumWeeks: goal.kind.minimumWeeks) }
        guard days <= PlanGenerator.maxWeeks * 7 else { throw PlanInputError.raceDateTooFar(maximumWeeks: PlanGenerator.maxWeeks) }
    }
}
