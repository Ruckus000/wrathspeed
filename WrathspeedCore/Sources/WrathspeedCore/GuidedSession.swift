import Foundation

public enum GuidedSessionLifecycle: String, Codable, CaseIterable, Sendable {
    case inProgress
    case completed
}

public struct StrengthSessionProgress: Codable, Equatable, Sendable {
    public var exerciseIndex: Int
    public var setIndex: Int
    public var restRemainingSeconds: Int
    public var restRunning: Bool
    public var currentReps: Int
    public var currentLoadValue: Double
    public var currentLoadUnit: String
    public var currentNote: String
    public var currentSubstitutionExerciseID: String?

    public init(
        exerciseIndex: Int = 0,
        setIndex: Int = 0,
        restRemainingSeconds: Int = 45,
        restRunning: Bool = false,
        currentReps: Int = 8,
        currentLoadValue: Double = 0,
        currentLoadUnit: String = "kg",
        currentNote: String = "",
        currentSubstitutionExerciseID: String? = nil
    ) {
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
        self.restRemainingSeconds = restRemainingSeconds
        self.restRunning = restRunning
        self.currentReps = currentReps
        self.currentLoadValue = currentLoadValue
        self.currentLoadUnit = currentLoadUnit
        self.currentNote = currentNote
        self.currentSubstitutionExerciseID = currentSubstitutionExerciseID
    }
}

public struct MobilitySessionProgress: Codable, Equatable, Sendable {
    public var movementIndex: Int
    public var remainingSeconds: TimeInterval

    public init(movementIndex: Int = 0, remainingSeconds: TimeInterval = 30) {
        self.movementIndex = movementIndex
        self.remainingSeconds = remainingSeconds
    }
}

public enum GuidedSessionPolicy {
    public static func inProgressStrength(
        sessionID: UUID,
        in results: [StrengthSessionResult]
    ) -> StrengthSessionResult? {
        results.first { $0.sessionID == sessionID && $0.lifecycle == .inProgress }
    }

    public static func inProgressMobility(
        routineID: String,
        in results: [MobilitySessionResult]
    ) -> MobilitySessionResult? {
        results.first { $0.routineID == routineID && $0.lifecycle == .inProgress }
    }

    public static func completedStrength(_ results: [StrengthSessionResult]) -> [StrengthSessionResult] {
        results.filter { $0.lifecycle == .completed }
    }

    public static func completedMobility(_ results: [MobilitySessionResult]) -> [MobilitySessionResult] {
        results.filter { $0.lifecycle == .completed }
    }
}
