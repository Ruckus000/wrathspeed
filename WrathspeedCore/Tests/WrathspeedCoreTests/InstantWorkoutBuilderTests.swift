import Foundation
import XCTest
@testable import WrathspeedCore

final class InstantWorkoutBuilderTests: XCTestCase {
    func testEasyDistanceRoundTrip() throws {
        let request = InstantWorkoutRequest(kind: .easy, location: .outdoor, distanceMeters: 8_000)
        try InstantWorkoutValidation.validate(request)
        let blueprint = try InstantWorkoutBuilder.build(request)
        XCTAssertEqual(blueprint.kind, .easy)
        XCTAssertGreaterThan(blueprint.plannedDistanceMeters, 0)
    }

    func testInstantRoundTripTable() throws {
        let cases: [InstantWorkoutBuildInput] = [
            InstantWorkoutBuildInput(
                request: InstantWorkoutRequest(
                    kind: .easy,
                    location: .outdoor,
                    distanceMeters: 5_000
                )
            ),
            InstantWorkoutBuildInput(
                request: InstantWorkoutRequest(
                    kind: .longRun,
                    location: .treadmill,
                    distanceMeters: 10_000
                )
            ),
            InstantWorkoutBuildInput(
                request: InstantWorkoutRequest(
                    kind: .freeRun,
                    location: .outdoor,
                    targetMode: .duration,
                    durationSeconds: 1_800
                )
            ),
            InstantWorkoutBuildInput(
                request: InstantWorkoutRequest(
                    kind: .tempo,
                    location: .outdoor
                ),
                tempoWarmupMeters: 1_000,
                tempoWorkMeters: 4_000,
                tempoCooldownMeters: 800
            ),
            InstantWorkoutBuildInput(
                request: InstantWorkoutRequest(
                    kind: .intervals,
                    location: .outdoor,
                    intervalParams: InstantIntervalParams(
                        reps: 4,
                        workTarget: .distance(meters: 400),
                        recoveryTarget: .distance(meters: 200),
                        warmupMeters: 1_000,
                        cooldownMeters: 800
                    )
                )
            ),
            InstantWorkoutBuildInput(
                request: InstantWorkoutRequest(
                    kind: .walkRun,
                    location: .treadmill,
                    walkRunWorkSeconds: 90,
                    walkRunRestSeconds: 60,
                    walkRunReps: 6
                )
            ),
            InstantWorkoutBuildInput(
                request: InstantWorkoutRequest(
                    kind: .race,
                    location: .outdoor,
                    distanceMeters: 10_000
                ),
                raceGoalKind: .tenK
            ),
        ]

        for input in cases {
            try InstantWorkoutValidation.validate(input)
            let blueprint = try InstantWorkoutBuilder.build(input)
            XCTAssertEqual(blueprint.kind, input.request.kind)
            XCTAssertEqual(blueprint.location, input.request.location)
            XCTAssertFalse(blueprint.steps.isEmpty)
        }
    }

    func testInvalidInputTable() {
        let inputs: [InstantWorkoutBuildInput] = [
            InstantWorkoutBuildInput(
                request: InstantWorkoutRequest(kind: .easy, location: .outdoor, distanceMeters: 200_000)
            ),
            InstantWorkoutBuildInput(
                request: InstantWorkoutRequest(
                    kind: .intervals,
                    location: .outdoor,
                    intervalParams: InstantIntervalParams(
                        reps: 0,
                        workTarget: .distance(meters: 400),
                        recoveryTarget: .distance(meters: 200)
                    )
                )
            ),
            InstantWorkoutBuildInput(
                request: InstantWorkoutRequest(
                    kind: .walkRun,
                    location: .outdoor,
                    walkRunWorkSeconds: 0,
                    walkRunRestSeconds: 60,
                    walkRunReps: 4
                )
            ),
            InstantWorkoutBuildInput(
                request: InstantWorkoutRequest(kind: .tempo, location: .outdoor),
                tempoWorkMeters: 0
            ),
        ]

        for input in inputs {
            XCTAssertThrowsError(try InstantWorkoutValidation.validate(input))
        }
    }

    func testRejectsOversizedDistance() {
        let request = InstantWorkoutRequest(kind: .easy, location: .outdoor, distanceMeters: 200_000)
        XCTAssertThrowsError(try InstantWorkoutValidation.validate(request))
    }
}
