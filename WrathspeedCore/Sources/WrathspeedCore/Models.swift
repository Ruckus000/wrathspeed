import Foundation

public enum Ability: String, Codable, CaseIterable, Sendable {
    case beginner
    case intermediate
    case advanced
    case elite
}

public enum Weekday: Int, Codable, CaseIterable, Sendable, Comparable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var calendarWeekday: Int { rawValue }

    public var displayName: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }
}

public enum DistanceUnit: String, Codable, CaseIterable, Sendable {
    case kilometers
    case miles

    public static func `default`(locale: Locale = .current) -> DistanceUnit {
        locale.measurementSystem == .metric ? .kilometers : .miles
    }
}

public enum PaceZone: String, Codable, CaseIterable, Sendable {
    case easy
    case marathon
    case threshold
    case interval
    case repetition
    case recovery
}

public enum Intensity: Codable, Equatable, Hashable, Sendable {
    case zone(PaceZone)
    case rpe(Int)
    case none
}

public enum WorkoutKind: String, Codable, CaseIterable, Sendable {
    case easy
    case intervals
    case tempo
    case longRun
    case race
    case walkRun
    case freeRun
    case strength

    public var isRunning: Bool {
        self != .strength
    }

    public var isQuality: Bool {
        switch self {
        case .intervals, .tempo, .race: true
        default: false
        }
    }

    public var usesPaceTargetsByDefault: Bool {
        switch self {
        case .easy, .intervals, .tempo, .longRun, .race: true
        default: false
        }
    }
}

public enum RunLocation: String, Codable, CaseIterable, Sendable {
    case outdoor
    case treadmill
}

public enum GoalKind: String, Codable, CaseIterable, Sendable {
    case fiveK
    case tenK
    case halfMarathon
    case marathon
    case newToRunning
    case returnToRunning

    public var distanceMeters: Double? {
        switch self {
        case .fiveK: 5_000
        case .tenK: 10_000
        case .halfMarathon: 21_097.5
        case .marathon: 42_195
        case .newToRunning, .returnToRunning: nil
        }
    }

    public var minimumWeeks: Int {
        switch self {
        case .fiveK: 8
        case .tenK: 10
        case .halfMarathon: 12
        case .marathon: 16
        case .newToRunning: 8
        case .returnToRunning: 6
        }
    }

    public var isBeginner: Bool {
        self == .newToRunning || self == .returnToRunning
    }

    public var displayName: String {
        switch self {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .halfMarathon: "Half Marathon"
        case .marathon: "Marathon"
        case .newToRunning: "New to Running"
        case .returnToRunning: "Return to Running"
        }
    }
}

public struct RaceResult: Codable, Equatable, Sendable {
    public var distanceMeters: Double
    public var duration: TimeInterval

    public init(distanceMeters: Double, duration: TimeInterval) {
        self.distanceMeters = distanceMeters
        self.duration = duration
    }
}

public struct TrainingGoal: Codable, Equatable, Sendable {
    public var kind: GoalKind
    public var raceDate: Date?
    public var weekCount: Int

    public init(kind: GoalKind, raceDate: Date? = nil, weekCount: Int? = nil) {
        self.kind = kind
        self.raceDate = raceDate
        let requested = weekCount ?? kind.minimumWeeks
        self.weekCount = min(26, max(kind.minimumWeeks, requested))
    }
}

public struct RunnerProfile: Codable, Equatable, Sendable {
    public var ability: Ability
    public var weeklyMileageMeters: Double
    public var longestRunMeters: Double
    public var daysPerWeek: Int
    public var longRunWeekday: Weekday
    public var unit: DistanceUnit
    public var recentRace: RaceResult?
    public var vdot: Double
    public var availableWeekdays: [Weekday]?

    public init(
        ability: Ability,
        weeklyMileageMeters: Double? = nil,
        longestRunMeters: Double? = nil,
        daysPerWeek: Int,
        longRunWeekday: Weekday,
        unit: DistanceUnit,
        recentRace: RaceResult? = nil,
        vdot: Double? = nil,
        availableWeekdays: [Weekday]? = nil
    ) {
        self.ability = ability
        self.weeklyMileageMeters = weeklyMileageMeters ?? ability.defaultWeeklyMileageMeters
        self.longestRunMeters = longestRunMeters ?? ability.defaultLongestRunMeters
        self.daysPerWeek = min(6, max(3, daysPerWeek))
        self.longRunWeekday = longRunWeekday
        self.unit = unit
        self.recentRace = recentRace
        self.availableWeekdays = availableWeekdays
        if let vdot {
            self.vdot = vdot
        } else if let recentRace {
            self.vdot = PaceCalculator.vdot(distanceMeters: recentRace.distanceMeters, duration: recentRace.duration)
        } else {
            self.vdot = ability.defaultVDOT
        }
    }
}

public extension Ability {
    var defaultVDOT: Double {
        switch self {
        case .beginner: 35
        case .intermediate: 45
        case .advanced: 55
        case .elite: 65
        }
    }

    var defaultWeeklyMileageMeters: Double {
        switch self {
        case .beginner: 15_000
        case .intermediate: 35_000
        case .advanced: 55_000
        case .elite: 75_000
        }
    }

    var defaultLongestRunMeters: Double {
        switch self {
        case .beginner: 5_000
        case .intermediate: 10_000
        case .advanced: 16_000
        case .elite: 24_000
        }
    }
}

public extension RunnerProfile {
    func resolvedRunWeekdays() -> [Weekday] {
        if let availableWeekdays, !availableWeekdays.isEmpty {
            return availableWeekdays.sorted()
        }
        return PlanGenerator.runWeekdays(daysPerWeek: daysPerWeek, longRun: longRunWeekday)
    }
}

public struct MobilityPreferences: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var sessionsPerWeek: Int

    public init(enabled: Bool = false, sessionsPerWeek: Int = 2) {
        self.enabled = enabled
        self.sessionsPerWeek = min(3, max(1, sessionsPerWeek))
    }
}

public struct PaceZones: Codable, Equatable, Sendable {
    /// Seconds per kilometer for each zone.
    public var secondsPerKilometer: [PaceZone: TimeInterval]

    public init(secondsPerKilometer: [PaceZone: TimeInterval]) {
        self.secondsPerKilometer = secondsPerKilometer
    }

    public func secondsPerKilometer(for zone: PaceZone) -> TimeInterval? {
        secondsPerKilometer[zone]
    }

    public func band(for zone: PaceZone, tolerance: Double = 0.05) -> ClosedRange<TimeInterval>? {
        guard let pace = secondsPerKilometer[zone] else { return nil }
        return (pace * (1 - tolerance))...(pace * (1 + tolerance))
    }
}

public enum StepTarget: Codable, Equatable, Hashable, Sendable {
    case distance(meters: Double)
    case duration(seconds: TimeInterval)

    public var isDistance: Bool {
        if case .distance = self { return true }
        return false
    }
}

public struct WorkoutStep: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var target: StepTarget
    public var intensity: Intensity

    public init(
        id: UUID = UUID(),
        name: String,
        target: StepTarget,
        intensity: Intensity
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.intensity = intensity
    }
}

public struct WorkoutBlueprint: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var kind: WorkoutKind
    public var title: String
    public var location: RunLocation
    public var steps: [WorkoutStep]
    public var plannedDistanceMeters: Double
    public var usesPaceTargets: Bool

    public init(
        id: UUID = UUID(),
        date: Date,
        kind: WorkoutKind,
        title: String,
        location: RunLocation = .outdoor,
        steps: [WorkoutStep],
        plannedDistanceMeters: Double,
        usesPaceTargets: Bool
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.location = location
        self.steps = steps
        self.plannedDistanceMeters = plannedDistanceMeters
        self.usesPaceTargets = usesPaceTargets
    }
}

public enum WorkoutStatus: String, Codable, Sendable {
    case scheduled
    case completed
    case skipped
    case convertedToEasy
}

public struct ScheduledWorkout: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var blueprint: WorkoutBlueprint
    public var status: WorkoutStatus
    public var result: WorkoutResult?
    public var scheduledTimeMinutes: Int?
    public var reminderEnabled: Bool

    public init(
        id: UUID = UUID(),
        blueprint: WorkoutBlueprint,
        status: WorkoutStatus = .scheduled,
        result: WorkoutResult? = nil,
        scheduledTimeMinutes: Int? = nil,
        reminderEnabled: Bool = false
    ) {
        self.id = id
        self.blueprint = blueprint
        self.status = status
        self.result = result
        self.scheduledTimeMinutes = scheduledTimeMinutes
        self.reminderEnabled = reminderEnabled
    }

    public var date: Date { blueprint.date }

    enum CodingKeys: String, CodingKey {
        case id, blueprint, status, result, scheduledTimeMinutes, reminderEnabled
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        blueprint = try values.decode(WorkoutBlueprint.self, forKey: .blueprint)
        status = try values.decode(WorkoutStatus.self, forKey: .status)
        result = try values.decodeIfPresent(WorkoutResult.self, forKey: .result)
        scheduledTimeMinutes = try values.decodeIfPresent(Int.self, forKey: .scheduledTimeMinutes)
        reminderEnabled = try values.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
    }
}

public struct WorkoutSplit: Codable, Equatable, Sendable {
    public var index: Int
    public var distanceMeters: Double
    public var duration: TimeInterval
    public var paceSecPerKm: Double

    public init(index: Int, distanceMeters: Double, duration: TimeInterval, paceSecPerKm: Double) {
        self.index = index
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.paceSecPerKm = paceSecPerKm
    }
}

public struct WorkoutResult: Codable, Equatable, Sendable, Identifiable {
    public var id: String { WorkoutResultMerge.identityKey(for: self) }
    public var workoutID: UUID
    public var startedAt: Date
    public var duration: TimeInterval
    public var distanceMeters: Double
    public var averagePaceSecPerKm: Double?
    public var heartRateAverage: Double?
    public var location: RunLocation
    public var healthKitUUID: UUID?
    public var route: [RoutePoint]?
    public var splits: [WorkoutSplit]?
    public var source: WorkoutSource
    public var matchInfo: WorkoutMatchInfo
    public var energyKilocalories: Double?
    public var cadenceAverage: Double?
    public var isUnavailableInHealth: Bool
    public var healthSync: HealthSyncMetadata

    public init(
        workoutID: UUID,
        startedAt: Date,
        duration: TimeInterval,
        distanceMeters: Double,
        averagePaceSecPerKm: Double?,
        heartRateAverage: Double? = nil,
        location: RunLocation,
        healthKitUUID: UUID? = nil,
        route: [RoutePoint]? = nil,
        splits: [WorkoutSplit]? = nil,
        source: WorkoutSource = .wrathspeedPhone,
        matchInfo: WorkoutMatchInfo = WorkoutMatchInfo(),
        energyKilocalories: Double? = nil,
        cadenceAverage: Double? = nil,
        isUnavailableInHealth: Bool = false,
        healthSync: HealthSyncMetadata = HealthSyncMetadata()
    ) {
        self.workoutID = workoutID
        self.startedAt = startedAt
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.averagePaceSecPerKm = averagePaceSecPerKm
        self.heartRateAverage = heartRateAverage
        self.location = location
        self.healthKitUUID = healthKitUUID
        self.route = route
        self.splits = splits
        self.source = source
        self.matchInfo = matchInfo
        self.energyKilocalories = energyKilocalories
        self.cadenceAverage = cadenceAverage
        self.isUnavailableInHealth = isUnavailableInHealth
        self.healthSync = healthSync
    }

    enum CodingKeys: String, CodingKey {
        case workoutID, startedAt, duration, distanceMeters, averagePaceSecPerKm, heartRateAverage
        case location, healthKitUUID, route, splits, source, matchInfo, energyKilocalories
        case cadenceAverage, isUnavailableInHealth, healthSync
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        workoutID = try values.decode(UUID.self, forKey: .workoutID)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        duration = try values.decode(TimeInterval.self, forKey: .duration)
        distanceMeters = try values.decode(Double.self, forKey: .distanceMeters)
        averagePaceSecPerKm = try values.decodeIfPresent(Double.self, forKey: .averagePaceSecPerKm)
        heartRateAverage = try values.decodeIfPresent(Double.self, forKey: .heartRateAverage)
        location = try values.decode(RunLocation.self, forKey: .location)
        healthKitUUID = try values.decodeIfPresent(UUID.self, forKey: .healthKitUUID)
        route = try values.decodeIfPresent([RoutePoint].self, forKey: .route)
        splits = try values.decodeIfPresent([WorkoutSplit].self, forKey: .splits)
        source = try values.decodeIfPresent(WorkoutSource.self, forKey: .source) ?? .wrathspeedPhone
        matchInfo = try values.decodeIfPresent(WorkoutMatchInfo.self, forKey: .matchInfo) ?? WorkoutMatchInfo()
        energyKilocalories = try values.decodeIfPresent(Double.self, forKey: .energyKilocalories)
        cadenceAverage = try values.decodeIfPresent(Double.self, forKey: .cadenceAverage)
        isUnavailableInHealth = try values.decodeIfPresent(Bool.self, forKey: .isUnavailableInHealth) ?? false
        healthSync = try values.decodeIfPresent(HealthSyncMetadata.self, forKey: .healthSync) ?? HealthSyncMetadata(
            state: healthKitUUID == nil ? .notRequired : .synced,
            healthKitUUID: healthKitUUID
        )
    }
}

public struct RoutePoint: Codable, Equatable, Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double
    public var timestamp: Date

    public init(latitude: Double, longitude: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }
}

public struct TrainingPlan: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var goal: TrainingGoal
    public var profile: RunnerProfile
    public var workouts: [ScheduledWorkout]
    public var generatedAt: Date

    public init(
        id: UUID = UUID(),
        goal: TrainingGoal,
        profile: RunnerProfile,
        workouts: [ScheduledWorkout],
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.goal = goal
        self.profile = profile
        self.workouts = workouts
        self.generatedAt = generatedAt
    }

    /// Puts `workouts` back in date order.
    ///
    /// Date order is an invariant every producer already maintains -- `PlanGenerator`,
    /// `BeginnerPlanGenerator`, `PlanReconciler` and the persistence migration all sort before
    /// handing a plan over -- and consumers rely on it: the weekly calendar renders `workouts`
    /// straight into a `ForEach`, so array order is display order.
    ///
    /// Rescheduling breaks it. Moving a workout rewrites `blueprint.date` in place, which leaves
    /// the workout at its old index, and the calendar then listed a run moved to Friday where
    /// Tuesday used to be. Call this after anything that can put a workout on a different day.
    ///
    /// Not needed for changes that cannot move a workout -- marking one complete, attaching a
    /// result -- which is why this is an explicit call rather than a `didSet`. A `didSet` would
    /// also re-sort during loops that mutate elements by index, and `sort` is not guaranteed
    /// stable, so equal-dated workouts could shuffle underneath an in-progress loop.
    public mutating func restoreDateOrder() {
        workouts.sort { $0.date < $1.date }
    }
}

public struct UpcomingWorkoutsPayload: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var blueprints: [WorkoutBlueprint]
    public var vdot: Double?
    public var unit: DistanceUnit?

    public init(
        generatedAt: Date = Date(),
        blueprints: [WorkoutBlueprint],
        vdot: Double? = nil,
        unit: DistanceUnit? = nil
    ) {
        self.generatedAt = generatedAt
        self.blueprints = blueprints
        self.vdot = vdot
        self.unit = unit
    }
}

public struct QualitySession: Codable, Equatable, Sendable {
    public var targetPaceSecPerKm: Double
    public var actualPaceSecPerKm: Double

    public init(targetPaceSecPerKm: Double, actualPaceSecPerKm: Double) {
        self.targetPaceSecPerKm = targetPaceSecPerKm
        self.actualPaceSecPerKm = actualPaceSecPerKm
    }

    /// Negative means faster than target.
    public var paceDeltaFraction: Double {
        (actualPaceSecPerKm - targetPaceSecPerKm) / targetPaceSecPerKm
    }
}
