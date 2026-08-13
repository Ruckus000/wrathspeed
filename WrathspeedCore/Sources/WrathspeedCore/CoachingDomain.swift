import Foundation

public enum GoalMode: String, Codable, CaseIterable, Sendable {
    case race
    case distance
    case newToRunning
    case returnToRunning

    public init(kind: GoalKind) {
        switch kind {
        case .fiveK, .tenK, .halfMarathon, .marathon: self = .race
        case .newToRunning: self = .newToRunning
        case .returnToRunning: self = .returnToRunning
        }
    }

    public var displayName: String {
        switch self {
        case .race: "Race"
        case .distance: "Distance"
        case .newToRunning: "New to Running"
        case .returnToRunning: "Return to Running"
        }
    }
}

public enum PlanLifecycleState: String, Codable, CaseIterable, Sendable {
    case draft
    case active
    case completed
    case archived
}

public enum WorkoutSource: String, Codable, CaseIterable, Sendable {
    case wrathspeedPhone
    case wrathspeedWatch
    case appleHealth
    case instant
}

public enum HealthSyncState: String, Codable, CaseIterable, Sendable {
    case notRequired
    case pending
    case synced
    case failed
}

public struct HealthSyncMetadata: Codable, Equatable, Sendable {
    public var state: HealthSyncState
    public var failureMessage: String?
    public var lastAttemptAt: Date?
    public var healthKitUUID: UUID?

    public init(
        state: HealthSyncState = .notRequired,
        failureMessage: String? = nil,
        lastAttemptAt: Date? = nil,
        healthKitUUID: UUID? = nil
    ) {
        self.state = state
        self.failureMessage = failureMessage
        self.lastAttemptAt = lastAttemptAt
        self.healthKitUUID = healthKitUUID
    }
}

public enum WorkoutMatchState: String, Codable, CaseIterable, Sendable {
    case unmatched
    case suggested
    case matched
    case ignored
}

public struct WorkoutMatchInfo: Codable, Equatable, Sendable {
    public var state: WorkoutMatchState
    public var scheduledWorkoutID: UUID?
    public var suggestedWorkoutID: UUID?
    public var rejectedWorkoutIDs: [UUID]

    public init(
        state: WorkoutMatchState = .unmatched,
        scheduledWorkoutID: UUID? = nil,
        suggestedWorkoutID: UUID? = nil,
        rejectedWorkoutIDs: [UUID] = []
    ) {
        self.state = state
        self.scheduledWorkoutID = scheduledWorkoutID
        self.suggestedWorkoutID = suggestedWorkoutID
        self.rejectedWorkoutIDs = rejectedWorkoutIDs
    }
}

public enum PlanAdjustmentKind: String, Codable, CaseIterable, Sendable {
    case notFeeling100
}

public struct PlanAdjustment: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: PlanAdjustmentKind
    public var payload: N100Adjustment
    public var isActive: Bool
    public var createdAt: Date
    public var endedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: PlanAdjustmentKind = .notFeeling100,
        payload: N100Adjustment,
        isActive: Bool = true,
        createdAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.isActive = isActive
        self.createdAt = createdAt
        self.endedAt = endedAt
    }
}

public enum PlanChangeKind: String, Codable, CaseIterable, Sendable {
    case move
    case skip
    case convert
    case scheduleRegeneration
    case adjustment
    case undo
}

public struct PlanChange: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: PlanChangeKind
    public var timestamp: Date
    public var affectedWorkoutIDs: [UUID]
    public var previousSnapshot: Data?
    public var description: String

    public init(
        id: UUID = UUID(),
        kind: PlanChangeKind,
        timestamp: Date = Date(),
        affectedWorkoutIDs: [UUID],
        previousSnapshot: Data? = nil,
        description: String
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.affectedWorkoutIDs = affectedWorkoutIDs
        self.previousSnapshot = previousSnapshot
        self.description = description
    }
}

public enum InstantTargetMode: String, Codable, CaseIterable, Sendable {
    case distance
    case duration
}

public struct InstantIntervalParams: Codable, Equatable, Sendable {
    public var reps: Int
    public var workTarget: StepTarget
    public var recoveryTarget: StepTarget
    public var warmupMeters: Double?
    public var cooldownMeters: Double?

    public init(
        reps: Int,
        workTarget: StepTarget,
        recoveryTarget: StepTarget,
        warmupMeters: Double? = nil,
        cooldownMeters: Double? = nil
    ) {
        self.reps = reps
        self.workTarget = workTarget
        self.recoveryTarget = recoveryTarget
        self.warmupMeters = warmupMeters
        self.cooldownMeters = cooldownMeters
    }
}

public struct InstantWorkoutRequest: Codable, Equatable, Sendable {
    public var kind: WorkoutKind
    public var location: RunLocation
    public var targetMode: InstantTargetMode
    public var distanceMeters: Double?
    public var durationSeconds: TimeInterval?
    public var paceZone: PaceZone?
    public var rpe: Int?
    public var intervalParams: InstantIntervalParams?
    public var walkRunWorkSeconds: TimeInterval?
    public var walkRunRestSeconds: TimeInterval?
    public var walkRunReps: Int?

    public init(
        kind: WorkoutKind,
        location: RunLocation,
        targetMode: InstantTargetMode = .distance,
        distanceMeters: Double? = nil,
        durationSeconds: TimeInterval? = nil,
        paceZone: PaceZone? = nil,
        rpe: Int? = nil,
        intervalParams: InstantIntervalParams? = nil,
        walkRunWorkSeconds: TimeInterval? = nil,
        walkRunRestSeconds: TimeInterval? = nil,
        walkRunReps: Int? = nil
    ) {
        self.kind = kind
        self.location = location
        self.targetMode = targetMode
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.paceZone = paceZone
        self.rpe = rpe
        self.intervalParams = intervalParams
        self.walkRunWorkSeconds = walkRunWorkSeconds
        self.walkRunRestSeconds = walkRunRestSeconds
        self.walkRunReps = walkRunReps
    }
}

public struct StrengthSetLog: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var exerciseID: String
    public var completed: Bool
    public var skipped: Bool
    public var reps: Int?
    public var loadValue: Double?
    public var loadUnit: String?
    public var substitutionExerciseID: String?
    public var note: String?

    public init(
        id: UUID = UUID(),
        exerciseID: String,
        completed: Bool = false,
        skipped: Bool = false,
        reps: Int? = nil,
        loadValue: Double? = nil,
        loadUnit: String? = nil,
        substitutionExerciseID: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.completed = completed
        self.skipped = skipped
        self.reps = reps
        self.loadValue = loadValue
        self.loadUnit = loadUnit
        self.substitutionExerciseID = substitutionExerciseID
        self.note = note
    }
}

public struct StrengthSessionResult: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var sessionID: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var setLogs: [StrengthSetLog]
    public var difficultyRPE: Int?
    public var healthSync: HealthSyncMetadata

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        startedAt: Date,
        endedAt: Date,
        setLogs: [StrengthSetLog],
        difficultyRPE: Int? = nil,
        healthSync: HealthSyncMetadata = HealthSyncMetadata()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.setLogs = setLogs
        self.difficultyRPE = difficultyRPE
        self.healthSync = healthSync
    }
}

public enum MobilityCategory: String, Codable, CaseIterable, Sendable {
    case preRun
    case postRun
    case recovery

    public var displayName: String {
        switch self {
        case .preRun: "Pre-Run"
        case .postRun: "Post-Run"
        case .recovery: "Recovery"
        }
    }

    public var typicalDurationRange: ClosedRange<Int> {
        switch self {
        case .preRun: 5...8
        case .postRun: 8...10
        case .recovery: 15...20
        }
    }
}

public struct MobilityMovement: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var durationSeconds: TimeInterval?
    public var reps: Int?
    public var side: String?
    public var transitionSeconds: TimeInterval
    public var restSeconds: TimeInterval
    public var cue: String
    public var mediaExerciseID: String?
    public var symbolName: String

    public init(
        id: String,
        name: String,
        durationSeconds: TimeInterval? = nil,
        reps: Int? = nil,
        side: String? = nil,
        transitionSeconds: TimeInterval = 0,
        restSeconds: TimeInterval = 0,
        cue: String,
        mediaExerciseID: String? = nil,
        symbolName: String = "figure.flexibility"
    ) {
        self.id = id
        self.name = name
        self.durationSeconds = durationSeconds
        self.reps = reps
        self.side = side
        self.transitionSeconds = transitionSeconds
        self.restSeconds = restSeconds
        self.cue = cue
        self.mediaExerciseID = mediaExerciseID
        self.symbolName = symbolName
    }
}

public struct MobilitySession: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var category: MobilityCategory
    public var title: String
    public var movements: [MobilityMovement]
    public var durationMinutes: Int

    public init(
        id: UUID = UUID(),
        date: Date,
        category: MobilityCategory,
        title: String,
        movements: [MobilityMovement],
        durationMinutes: Int
    ) {
        self.id = id
        self.date = date
        self.category = category
        self.title = title
        self.movements = movements
        self.durationMinutes = durationMinutes
    }
}

public struct MobilitySessionResult: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var sessionID: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var completedMovementIDs: [String]

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        startedAt: Date,
        endedAt: Date,
        completedMovementIDs: [String]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.completedMovementIDs = completedMovementIDs
    }
}

public struct GuidedMediaReference: Codable, Equatable, Sendable {
    public var localExerciseID: String
    public var provider: String
    public var remoteMediaID: String?
    public var streamURL: URL?
    public var posterURL: URL?
    public var author: String?
    public var licenseName: String?
    public var sourceURL: URL?
    public var attribution: String?
    public var fallbackSymbolName: String
    public var fallbackCue: String

    public init(
        localExerciseID: String,
        provider: String = "local",
        remoteMediaID: String? = nil,
        streamURL: URL? = nil,
        posterURL: URL? = nil,
        author: String? = nil,
        licenseName: String? = nil,
        sourceURL: URL? = nil,
        attribution: String? = nil,
        fallbackSymbolName: String = "figure.strengthtraining.traditional",
        fallbackCue: String
    ) {
        self.localExerciseID = localExerciseID
        self.provider = provider
        self.remoteMediaID = remoteMediaID
        self.streamURL = streamURL
        self.posterURL = posterURL
        self.author = author
        self.licenseName = licenseName
        self.sourceURL = sourceURL
        self.attribution = attribution
        self.fallbackSymbolName = fallbackSymbolName
        self.fallbackCue = fallbackCue
    }
}

public enum ActiveSessionState: String, Codable, CaseIterable, Sendable {
    case preparing
    case countdown
    case recording
    case paused
    case finishing
    case saved
    case healthSyncPending
    case failed
}

public struct ActiveSessionSnapshot: Codable, Equatable, Sendable {
    public var workoutID: UUID
    public var blueprintData: Data
    public var source: WorkoutSource
    public var state: ActiveSessionState
    public var startedAt: Date?
    public var elapsedSeconds: TimeInterval
    public var distanceMeters: Double
    public var stepIndex: Int
    public var isPaused: Bool
    public var updatedAt: Date
    public var healthSync: HealthSyncMetadata

    public init(
        workoutID: UUID,
        blueprintData: Data,
        source: WorkoutSource,
        state: ActiveSessionState,
        startedAt: Date? = nil,
        elapsedSeconds: TimeInterval = 0,
        distanceMeters: Double = 0,
        stepIndex: Int = 0,
        isPaused: Bool = false,
        updatedAt: Date = Date(),
        healthSync: HealthSyncMetadata = HealthSyncMetadata()
    ) {
        self.workoutID = workoutID
        self.blueprintData = blueprintData
        self.source = source
        self.state = state
        self.startedAt = startedAt
        self.elapsedSeconds = elapsedSeconds
        self.distanceMeters = distanceMeters
        self.stepIndex = stepIndex
        self.isPaused = isPaused
        self.updatedAt = updatedAt
        self.healthSync = healthSync
    }
}

public enum PendingHealthOpKind: String, Codable, CaseIterable, Sendable {
    case importWorkouts
    case saveWorkout
    case saveStrength
}

public struct PendingHealthOp: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: PendingHealthOpKind
    public var payloadData: Data
    public var createdAt: Date
    public var attemptCount: Int
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        kind: PendingHealthOpKind,
        payloadData: Data,
        createdAt: Date = Date(),
        attemptCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.payloadData = payloadData
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.lastError = lastError
    }
}

public enum PersistenceSchema {
    public static let currentVersion = 1
}

public extension WorkoutSource {
    var displayName: String {
        switch self {
        case .wrathspeedPhone: "Wrathspeed Phone"
        case .wrathspeedWatch: "Wrathspeed Watch"
        case .appleHealth: "Apple Health"
        case .instant: "Instant"
        }
    }
}

extension ActiveSessionSnapshot: Identifiable {
    public var id: UUID { workoutID }
}

public extension HealthSyncState {
    var title: String {
        switch self {
        case .notRequired: "Not required"
        case .pending: "Pending"
        case .synced: "Synced"
        case .failed: "Failed"
        }
    }
}

