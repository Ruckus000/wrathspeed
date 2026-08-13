import Foundation
import WrathspeedCore

enum InstantWorkoutBuilder {
    static func build(_ request: InstantWorkoutRequest, date: Date = Date()) throws -> WorkoutBlueprint {
        switch request.kind {
        case .easy, .freeRun:
            let meters = request.distanceMeters ?? 5_000
            if request.targetMode == .duration, let seconds = request.durationSeconds {
                return timedEasy(date: date, seconds: seconds, location: request.location, kind: request.kind)
            }
            return WorkoutBuilder.easyRun(date: date, meters: meters, location: request.location)
        case .longRun:
            return WorkoutBuilder.longRun(
                date: date,
                meters: request.distanceMeters ?? 12_000,
                location: request.location,
                usesPace: request.paceZone != nil
            )
        case .tempo:
            return WorkoutBuilder.tempo(date: date, phase: .build, location: request.location)
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
            return WorkoutBuilder.easyRun(date: date, meters: request.distanceMeters ?? 5_000, location: request.location)
        case .strength:
            throw NSError(domain: "InstantWorkoutBuilder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Use strength player for strength sessions."])
        }
    }

    private static func timedEasy(date: Date, seconds: TimeInterval, location: RunLocation, kind: WorkoutKind) -> WorkoutBlueprint {
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

    private static func intervalBlueprint(date: Date, request: InstantWorkoutRequest, params: InstantIntervalParams) -> WorkoutBlueprint {
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
}

enum InstantWorkoutValidation {
    static func validate(_ request: InstantWorkoutRequest) throws {
        if let meters = request.distanceMeters {
            guard meters.isFinite, meters > 0, meters < 100_000 else {
                throw NSError(domain: "InstantWorkoutValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Distance must be between zero and 100 km."])
            }
        }
        if let seconds = request.durationSeconds {
            guard seconds.isFinite, seconds > 0, seconds < 6 * 3_600 else {
                throw NSError(domain: "InstantWorkoutValidation", code: 2, userInfo: [NSLocalizedDescriptionKey: "Duration must be under 6 hours."])
            }
        }
        if let params = request.intervalParams {
            guard params.reps > 0, params.reps <= 30 else {
                throw NSError(domain: "InstantWorkoutValidation", code: 3, userInfo: [NSLocalizedDescriptionKey: "Reps must be between 1 and 30."])
            }
        }
    }
}
