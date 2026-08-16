import SwiftData
import XCTest
@testable import Wrathspeed
import WrathspeedCore

@MainActor
final class SessionRecoveryTests: XCTestCase {
    private func makeStore() throws -> (AppStore, ModelContext) {
        let container = try ModelContainer(
            for: Schema([
                SnapshotEntity.self,
                MigrationMarkerEntity.self,
                AppSettingsEntity.self,
                TrainingPlanEntity.self,
                ScheduledWorkoutEntity.self,
                WorkoutResultEntity.self,
                StrengthSessionEntity.self,
                StrengthSessionResultEntity.self,
                MobilitySessionResultEntity.self,
                ActiveSessionSnapshotEntity.self,
            ]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)
        return (store, context)
    }

    func testPartialRecoveryCreatesResultWithoutCompletingPlannedWorkout() throws {
        let (store, _) = try makeStore()
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
            blueprintData: try JSONEncoder().encode(blueprint),
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
        XCTAssertNil(store.errorMessage)
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

    func testMatchingCancellationClearsCountdownRecovery() throws {
        let (store, context) = try makeStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let startupID = store.session.testing_beginOwnedStartup()
        store.session.testing_simulateCountdownOwnership(startupID: startupID, blueprint: blueprint)
        XCTAssertEqual(store.session.sessionState, .countdown)
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .countdown)

        store.session.cancelPendingLaunch()
        XCTAssertEqual(store.session.sessionState, .preparing)
        XCTAssertNil(store.session.blueprint)
        XCTAssertNil(try ActiveSessionStore.load(from: context))
        XCTAssertNil(store.pendingRecoverySnapshot)
    }

    func testCurrentStartupFailureClearsCountdownAndRethrows() throws {
        let (store, context) = try makeStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let startupID = store.session.testing_beginOwnedStartup()
        store.session.testing_simulateCountdownOwnership(startupID: startupID, blueprint: blueprint)
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .countdown)

        store.session.testing_cleanupCurrentStartupFailure(startupID: startupID)

        XCTAssertEqual(store.session.sessionState, .preparing)
        XCTAssertNil(try ActiveSessionStore.load(from: context))
        XCTAssertNil(store.pendingRecoverySnapshot)

        let staleID = startupID
        let newID = store.session.testing_beginOwnedStartup()
        store.session.testing_simulateCountdownOwnership(startupID: newID, blueprint: blueprint)
        store.session.testing_cleanupCurrentStartupFailure(startupID: staleID)
        XCTAssertEqual(store.session.sessionState, .countdown)
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .countdown)
    }

    func testMatchingTerminalSavedClearsCountdownRecovery() throws {
        let (store, context) = try makeStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let startedAt = Date(timeIntervalSince1970: 1_700_001_050)
        try ActiveSessionStore.save(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .countdown,
                startedAt: startedAt
            ),
            to: context
        )
        store.session.onSnapshot?(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .saved,
                startedAt: startedAt
            )
        )
        XCTAssertNil(try ActiveSessionStore.load(from: context))
        XCTAssertNil(store.pendingRecoverySnapshot)
    }

    func testTerminalSavedClearsMatchingStartupRecoveryOnly() throws {
        let (store, context) = try makeStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let otherBlueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Other",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let startedAt = Date(timeIntervalSince1970: 1_700_001_000)
        try ActiveSessionStore.save(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .countdown,
                startedAt: startedAt
            ),
            to: context
        )
        store.session.onSnapshot?(
            ActiveSessionSnapshot(
                workoutID: otherBlueprint.id,
                blueprintData: try JSONEncoder().encode(otherBlueprint),
                source: .wrathspeedPhone,
                state: .saved,
                startedAt: startedAt.addingTimeInterval(60)
            )
        )
        let loaded = try ActiveSessionStore.load(from: context)
        XCTAssertEqual(loaded?.workoutID, blueprint.id)
        XCTAssertEqual(loaded?.state, .countdown)
    }

    func testTerminalSavedDoesNotClearStoredFinishingWithoutPersistedResult() throws {
        let (store, context) = try makeStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let startedAt = Date(timeIntervalSince1970: 1_700_001_100)
        try ActiveSessionStore.save(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .finishing,
                startedAt: startedAt
            ),
            to: context
        )
        store.session.onSnapshot?(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .saved,
                startedAt: startedAt
            )
        )
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .finishing)
        XCTAssertNil(store.pendingRecoverySnapshot)
    }
}
