import XCTest
@testable import Wrathspeed
import WrathspeedCore

@MainActor
final class SessionRecoveryTests: XCTestCase {
    func testPartialRecoveryCreatesResultWithoutCompletingPlannedWorkout() {
        let store = AppStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let planWorkout = ScheduledWorkout(blueprint: blueprint)
        store.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK, raceDate: Date().addingTimeInterval(86_400 * 30)),
            profile: RunnerProfile(
                ability: .intermediate,
                daysPerWeek: 4,
                longRunWeekday: .sunday,
                unit: .kilometers,
                vdot: 40,
                availableWeekdays: [.tuesday, .thursday, .saturday, .sunday]
            ),
            workouts: [planWorkout]
        )
        let snapshot = ActiveSessionSnapshot(
            workoutID: blueprint.id,
            blueprintData: try! JSONEncoder().encode(blueprint),
            source: .instant,
            state: .recording,
            startedAt: Date().addingTimeInterval(-1_200),
            elapsedSeconds: 1_200,
            distanceMeters: 2_500
        )
        store.savePartialRecovery(from: snapshot)
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.source, .instant)
        XCTAssertEqual(store.plan?.workouts.first?.status, .scheduled)
        XCTAssertNil(store.pendingRecoverySnapshot)
    }

    func testDiscardRecoveryClearsPendingSnapshot() {
        let store = AppStore()
        store.pendingRecoverySnapshot = ActiveSessionSnapshot(
            workoutID: UUID(),
            blueprintData: Data(),
            source: .wrathspeedPhone,
            state: .paused
        )
        store.discardRecovery()
        XCTAssertNil(store.pendingRecoverySnapshot)
    }
}
