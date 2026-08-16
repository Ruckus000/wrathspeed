import Foundation
import Testing
@testable import WrathspeedCore

struct WorkoutPaceTargetTests {
    private let zones = PaceCalculator.zones(vdot: 50)

    @Test(arguments: [
        ("easy", WorkoutBuilder.easyRun(date: Date(), meters: 5_000, location: .outdoor), PaceZone.easy),
        ("tempo", WorkoutBuilder.tempo(date: Date(), phase: .build, location: .outdoor), PaceZone.threshold),
        ("intervals", WorkoutBuilder.intervals(date: Date(), kind: .fiveK, phase: .build, location: .outdoor), PaceZone.interval),
        ("5K race", WorkoutBuilder.race(date: Date(), meters: 5_000, kind: .fiveK, location: .outdoor), PaceZone.threshold),
        ("10K race", WorkoutBuilder.race(date: Date(), meters: 10_000, kind: .tenK, location: .outdoor), PaceZone.threshold),
        ("half marathon race", WorkoutBuilder.race(date: Date(), meters: 21_097.5, kind: .halfMarathon, location: .outdoor), PaceZone.threshold),
        ("marathon race", WorkoutBuilder.race(date: Date(), meters: 42_195, kind: .marathon, location: .outdoor), PaceZone.marathon),
    ] as [(String, WorkoutBlueprint, PaceZone)])
    func selectsRepresentativeZone(_ label: String, blueprint: WorkoutBlueprint, expected: PaceZone) {
        #expect(WorkoutPaceTarget.representativeZone(in: blueprint) == expected, Comment(rawValue: label))
        #expect(
            WorkoutPaceTarget.targetPaceSecPerKm(blueprint: blueprint, zones: zones)
                == zones.secondsPerKilometer(for: expected),
            Comment(rawValue: label)
        )
    }

    @Test func fallsBackWhenNoEligibleStep() {
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .strength,
            title: "Strength",
            steps: [],
            plannedDistanceMeters: 0,
            usesPaceTargets: false
        )
        #expect(WorkoutPaceTarget.representativeZone(in: blueprint) == nil)
        #expect(WorkoutPaceTarget.targetPaceSecPerKm(blueprint: blueprint, zones: zones) == nil)
    }

    @Test func ignoresWarmupCooldownAndRecovery() {
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .tempo,
            title: "Tempo",
            steps: [
                WorkoutStep(name: "Warm up", target: .distance(meters: 1_500), intensity: .zone(.easy)),
                WorkoutStep(name: "Recover", target: .distance(meters: 400), intensity: .zone(.recovery)),
                WorkoutStep(name: "Tempo", target: .distance(meters: 3_000), intensity: .zone(.threshold)),
                WorkoutStep(name: "Cool down", target: .distance(meters: 1_000), intensity: .zone(.easy)),
            ],
            plannedDistanceMeters: 5_900,
            usesPaceTargets: true
        )
        #expect(WorkoutPaceTarget.representativeZone(in: blueprint) == .threshold)
    }
}
