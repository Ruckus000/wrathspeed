import Foundation

public struct InstantWorkoutBuildInput: Equatable, Sendable {
    public var request: InstantWorkoutRequest
    public var tempoWarmupMeters: Double?
    public var tempoWorkMeters: Double?
    public var tempoCooldownMeters: Double?
    public var raceGoalKind: GoalKind?

    public init(
        request: InstantWorkoutRequest,
        tempoWarmupMeters: Double? = nil,
        tempoWorkMeters: Double? = nil,
        tempoCooldownMeters: Double? = nil,
        raceGoalKind: GoalKind? = nil
    ) {
        self.request = request
        self.tempoWarmupMeters = tempoWarmupMeters
        self.tempoWorkMeters = tempoWorkMeters
        self.tempoCooldownMeters = tempoCooldownMeters
        self.raceGoalKind = raceGoalKind
    }
}

public enum InstantWorkoutBuilder {
    public static func build(_ request: InstantWorkoutRequest, date: Date = Date()) throws -> WorkoutBlueprint {
        try build(InstantWorkoutBuildInput(request: request), date: date)
    }

    public static func build(_ input: InstantWorkoutBuildInput, date: Date = Date()) throws -> WorkoutBlueprint {
        let request = input.request
        switch request.kind {
        case .easy, .freeRun:
            if request.targetMode == .duration, let seconds = request.durationSeconds {
                return timedEasy(date: date, seconds: seconds, location: request.location, kind: request.kind)
            }
            let meters = request.distanceMeters ?? 5_000
            return WorkoutBuilder.easyRun(date: date, meters: meters, location: request.location)
        case .longRun:
            if request.targetMode == .duration, let seconds = request.durationSeconds {
                return timedLongRun(date: date, seconds: seconds, location: request.location)
            }
            return WorkoutBuilder.longRun(
                date: date,
                meters: request.distanceMeters ?? 12_000,
                location: request.location,
                usesPace: request.paceZone != nil
            )
        case .tempo:
            return tempoBlueprint(
                date: date,
                location: request.location,
                warmupMeters: input.tempoWarmupMeters ?? 1_500,
                workMeters: input.tempoWorkMeters ?? 5_000,
                cooldownMeters: input.tempoCooldownMeters ?? 1_000
            )
        case .intervals:
            if let params = request.intervalParams {
                return intervalBlueprint(date: date, request: request, params: params)
            }
            return WorkoutBuilder.intervals(date: date, kind: .fiveK, phase: .build, location: request.location)
        case .walkRun:
            return BeginnerPlanGenerator.walkRun(
                date: date,
                runSeconds: request.walkRunWorkSeconds ?? 60,
                walkSeconds: request.walkRunRestSeconds ?? 90,
                repeats: request.walkRunReps ?? 8,
                location: request.location
            )
        case .race:
            let meters = request.distanceMeters ?? 5_000
            let goalKind = input.raceGoalKind ?? inferRaceGoalKind(meters: meters)
            return WorkoutBuilder.race(
                date: date,
                meters: meters,
                kind: goalKind,
                location: request.location
            )
        case .strength:
            throw NSError(
                domain: "InstantWorkoutBuilder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Use strength player for strength sessions."]
            )
        }
    }

    private static func timedEasy(
        date: Date,
        seconds: TimeInterval,
        location: RunLocation,
        kind: WorkoutKind
    ) -> WorkoutBlueprint {
        WorkoutBlueprint(
            date: date,
            kind: kind,
            title: kind == .freeRun ? "Free run" : "Easy run",
            location: location,
            steps: [WorkoutStep(name: "Main", target: .duration(seconds: seconds), intensity: .zone(.easy))],
            plannedDistanceMeters: 0,
            usesPaceTargets: false
        )
    }

    private static func timedLongRun(date: Date, seconds: TimeInterval, location: RunLocation) -> WorkoutBlueprint {
        WorkoutBlueprint(
            date: date,
            kind: .longRun,
            title: "Long run",
            location: location,
            steps: [WorkoutStep(name: "Long run", target: .duration(seconds: seconds), intensity: .rpe(4))],
            plannedDistanceMeters: 0,
            usesPaceTargets: false
        )
    }

    private static func tempoBlueprint(
        date: Date,
        location: RunLocation,
        warmupMeters: Double,
        workMeters: Double,
        cooldownMeters: Double
    ) -> WorkoutBlueprint {
        let steps = [
            WorkoutStep(name: "Warm up", target: .distance(meters: warmupMeters), intensity: .zone(.easy)),
            WorkoutStep(name: "Tempo", target: .distance(meters: workMeters), intensity: .zone(.threshold)),
            WorkoutStep(name: "Cool down", target: .distance(meters: cooldownMeters), intensity: .zone(.easy)),
        ]
        return WorkoutBlueprint(
            date: date,
            kind: .tempo,
            title: "Tempo run",
            location: location,
            steps: steps,
            plannedDistanceMeters: warmupMeters + workMeters + cooldownMeters,
            usesPaceTargets: true
        )
    }

    private static func intervalBlueprint(
        date: Date,
        request: InstantWorkoutRequest,
        params: InstantIntervalParams
    ) -> WorkoutBlueprint {
        var steps: [WorkoutStep] = []
        if let warmup = params.warmupMeters {
            steps.append(WorkoutStep(name: "Warm up", target: .distance(meters: warmup), intensity: .zone(.easy)))
        }
        for rep in 1...params.reps {
            steps.append(WorkoutStep(name: "Rep \(rep)", target: params.workTarget, intensity: .zone(.interval)))
            if rep < params.reps {
                steps.append(WorkoutStep(name: "Recovery", target: params.recoveryTarget, intensity: .zone(.recovery)))
            }
        }
        if let cooldown = params.cooldownMeters {
            steps.append(WorkoutStep(name: "Cool down", target: .distance(meters: cooldown), intensity: .zone(.easy)))
        }
        let distance = steps.compactMap { step -> Double? in
            if case let .distance(meters) = step.target { return meters }
            return nil
        }.reduce(0, +)
        return WorkoutBlueprint(
            date: date,
            kind: .intervals,
            title: "Intervals",
            location: request.location,
            steps: steps,
            plannedDistanceMeters: distance,
            usesPaceTargets: true
        )
    }

    private static func inferRaceGoalKind(meters: Double) -> GoalKind {
        switch meters {
        case ..<6_500: .fiveK
        case ..<11_500: .tenK
        case ..<30_000: .halfMarathon
        default: .marathon
        }
    }
}

public enum InstantWorkoutValidation {
    public static func validate(_ request: InstantWorkoutRequest) throws {
        try validate(InstantWorkoutBuildInput(request: request))
    }

    public static func validate(_ input: InstantWorkoutBuildInput) throws {
        let request = input.request
        if let meters = request.distanceMeters {
            try validateDistance(meters)
        }
        if let seconds = request.durationSeconds {
            try validateDuration(seconds)
        }
        if let params = request.intervalParams {
            guard params.reps > 0, params.reps <= 30 else {
                throw validationError("Reps must be between 1 and 30.")
            }
        }
        if let reps = request.walkRunReps {
            guard reps > 0, reps <= 30 else {
                throw validationError("Repetitions must be between 1 and 30.")
            }
        }
        switch request.kind {
        case .easy, .freeRun, .longRun, .race:
            if request.targetMode == .distance {
                guard let meters = request.distanceMeters else {
                    throw validationError("Distance is required.")
                }
                try validateDistance(meters)
            } else {
                guard let seconds = request.durationSeconds else {
                    throw validationError("Duration is required.")
                }
                try validateDuration(seconds)
            }
        case .tempo:
            try validateDistance(input.tempoWarmupMeters ?? 1_500)
            try validateDistance(input.tempoWorkMeters ?? 5_000)
            try validateDistance(input.tempoCooldownMeters ?? 1_000)
        case .intervals:
            guard let params = request.intervalParams else {
                throw validationError("Interval parameters are required.")
            }
            guard params.reps > 0, params.reps <= 30 else {
                throw validationError("Reps must be between 1 and 30.")
            }
            try validateStepTarget(params.workTarget)
            try validateStepTarget(params.recoveryTarget)
            if let warmup = params.warmupMeters { try validateDistance(warmup) }
            if let cooldown = params.cooldownMeters { try validateDistance(cooldown) }
        case .walkRun:
            guard let run = request.walkRunWorkSeconds, run > 0, run <= 3_600 else {
                throw validationError("Run duration must be between 1 second and 1 hour.")
            }
            guard let walk = request.walkRunRestSeconds, walk > 0, walk <= 3_600 else {
                throw validationError("Walk duration must be between 1 second and 1 hour.")
            }
            guard let reps = request.walkRunReps, reps > 0, reps <= 30 else {
                throw validationError("Repetitions must be between 1 and 30.")
            }
        case .strength:
            throw validationError("Use strength player for strength sessions.")
        }
    }

    private static func validateDistance(_ meters: Double) throws {
        guard meters.isFinite, meters > 0, meters < 100_000 else {
            throw validationError("Distance must be between zero and 100 km.")
        }
    }

    private static func validateDuration(_ seconds: TimeInterval) throws {
        guard seconds.isFinite, seconds > 0, seconds < 6 * 3_600 else {
            throw validationError("Duration must be under 6 hours.")
        }
    }

    private static func validateStepTarget(_ target: StepTarget) throws {
        switch target {
        case .distance(let meters):
            try validateDistance(meters)
        case .duration(let seconds):
            try validateDuration(seconds)
        }
    }

    private static func validationError(_ message: String) -> NSError {
        NSError(domain: "InstantWorkoutValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
