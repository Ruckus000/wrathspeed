import SwiftData
import XCTest
@testable import Wrathspeed
import WrathspeedCore

@MainActor
final class WorkoutResultRecordTests: XCTestCase {
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

    private func plannedStore() throws -> (AppStore, ModelContext) {
        let pair = try makeStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let workout = ScheduledWorkout(blueprint: blueprint)
        pair.0.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [workout]
        )
        pair.0.profile = pair.0.plan?.profile
        pair.0.save()
        return pair
    }

    private func sampleResult(
        workoutID: UUID,
        startedAt: Date,
        healthState: HealthSyncState,
        healthKitUUID: UUID? = nil,
        source: WorkoutSource = .wrathspeedPhone
    ) -> WorkoutResult {
        WorkoutResult(
            workoutID: workoutID,
            startedAt: startedAt,
            duration: 1_800,
            distanceMeters: 5_000,
            averagePaceSecPerKm: 360,
            location: .outdoor,
            healthKitUUID: healthKitUUID,
            source: source,
            healthSync: HealthSyncMetadata(state: healthState, healthKitUUID: healthKitUUID)
        )
    }

    private func snapshot(
        blueprint: WorkoutBlueprint,
        startedAt: Date,
        state: ActiveSessionState,
        elapsed: TimeInterval = 1_800,
        distance: Double = 5_000
    ) throws -> ActiveSessionSnapshot {
        ActiveSessionSnapshot(
            workoutID: blueprint.id,
            blueprintData: try JSONEncoder().encode(blueprint),
            source: .wrathspeedPhone,
            state: state,
            startedAt: startedAt,
            elapsedSeconds: elapsed,
            distanceMeters: distance
        )
    }

    func testPendingThenSyncedKeepsSingleResultAndCompletesPlanOnce() throws {
        let (store, _) = try plannedStore()
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.blueprint.id)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var celebrationEvents = 0
        var completionEvents = 0

        let statusBeforeInsert = store.plan?.workouts.first?.status
        try store.record(sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .pending))
        if store.celebration != nil { celebrationEvents += 1 }
        if statusBeforeInsert != .completed, store.plan?.workouts.first?.status == .completed { completionEvents += 1 }
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(celebrationEvents, 1)
        XCTAssertEqual(completionEvents, 1)

        var synced = sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .synced, healthKitUUID: UUID())
        synced.route = [RoutePoint(latitude: 1, longitude: 2, timestamp: startedAt)]
        let celebrationBeforeUpdate = store.celebration
        let statusBeforeUpdate = store.plan?.workouts.first?.status
        try store.record(synced)
        if store.celebration != celebrationBeforeUpdate { celebrationEvents += 1 }
        if statusBeforeUpdate != .completed, store.plan?.workouts.first?.status == .completed { completionEvents += 1 }

        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.healthSync.state, .synced)
        XCTAssertEqual(store.results.first?.route?.count, 1)
        XCTAssertEqual(store.results.first?.source, .wrathspeedPhone)
        XCTAssertEqual(store.results.first?.workoutID, workoutID)
        XCTAssertEqual(store.results.first?.startedAt, startedAt)
        XCTAssertEqual(celebrationEvents, 1)
        XCTAssertEqual(completionEvents, 1)
    }

    func testFailedThenSyncedUpdatesSameResult() throws {
        let (store, _) = try plannedStore()
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.blueprint.id)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_050)
        try store.record(sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .failed))
        let healthUUID = UUID()
        try store.record(sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .synced, healthKitUUID: healthUUID))
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.healthSync.state, .synced)
        XCTAssertEqual(store.results.first?.healthKitUUID, healthUUID)
    }

    func testSyncedIsNeverDowngraded() throws {
        let (store, _) = try plannedStore()
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.blueprint.id)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_060)
        let healthUUID = UUID()
        try store.record(sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .synced, healthKitUUID: healthUUID))
        try store.record(sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .pending))
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.healthSync.state, .synced)
        XCTAssertEqual(store.results.first?.healthKitUUID, healthUUID)
    }

    func testMetadataUpdateDoesNotRepeatCelebration() throws {
        let (store, _) = try plannedStore()
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.blueprint.id)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_100)
        var celebrationEvents = 0

        try store.record(sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .pending))
        if store.celebration != nil { celebrationEvents += 1 }
        let firstCelebration = store.celebration

        let synced = sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .synced, healthKitUUID: UUID())
        try store.record(synced)
        if store.celebration != firstCelebration { celebrationEvents += 1 }
        XCTAssertEqual(store.celebration, firstCelebration)
        XCTAssertEqual(celebrationEvents, 1)
    }

    func testConflictingHealthKitUUIDsDoNotMergeInStore() throws {
        let (store, _) = try plannedStore()
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.blueprint.id)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_150)
        try store.record(sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .synced, healthKitUUID: UUID()))
        try store.record(sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .synced, healthKitUUID: UUID()))
        XCTAssertEqual(store.results.count, 2)
        XCTAssertNotEqual(store.results[0].healthKitUUID, store.results[1].healthKitUUID)
    }

    func testHealthSyncPendingSnapshotDoesNotRestoreAfterLocalSave() throws {
        let (store, context) = try makeStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let startedAt = Date(timeIntervalSince1970: 1_700_000_200)
        try store.record(sampleResult(workoutID: blueprint.id, startedAt: startedAt, healthState: .failed))

        try ActiveSessionStore.save(
            snapshot(blueprint: blueprint, startedAt: startedAt, state: .healthSyncPending),
            to: context
        )

        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertNil(restored.pendingRecoverySnapshot)
    }

    func testSavePartialDoesNotCreateDuplicateForCompletedWorkout() throws {
        let (store, _) = try plannedStore()
        let blueprint = try XCTUnwrap(store.plan?.workouts.first?.blueprint)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_300)
        try store.record(sampleResult(workoutID: blueprint.id, startedAt: startedAt, healthState: .failed))

        store.savePartialRecovery(from: try snapshot(
            blueprint: blueprint,
            startedAt: startedAt,
            state: .recording,
            elapsed: 0,
            distance: 0
        ))
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.distanceMeters, 5_000)
    }

    func testRecordingSnapshotWithNoResultRestores() throws {
        let (_, context) = try makeStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let startedAt = Date(timeIntervalSince1970: 1_700_000_400)
        try ActiveSessionStore.save(
            snapshot(blueprint: blueprint, startedAt: startedAt, state: .recording),
            to: context
        )
        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.pendingRecoverySnapshot?.state, .recording)
        XCTAssertEqual(restored.pendingRecoverySnapshot?.workoutID, blueprint.id)
    }

    func testPausedSnapshotWithNoResultRestores() throws {
        let (_, context) = try makeStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let startedAt = Date(timeIntervalSince1970: 1_700_000_410)
        try ActiveSessionStore.save(
            snapshot(blueprint: blueprint, startedAt: startedAt, state: .paused),
            to: context
        )
        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.pendingRecoverySnapshot?.state, .paused)
    }

    func testFinishingSnapshotWithNoResultRestores() throws {
        let (_, context) = try makeStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let startedAt = Date(timeIntervalSince1970: 1_700_000_420)
        try ActiveSessionStore.save(
            snapshot(blueprint: blueprint, startedAt: startedAt, state: .finishing),
            to: context
        )
        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.pendingRecoverySnapshot?.state, .finishing)
        XCTAssertNil(restored.celebration)
    }

    func testFinishingSnapshotWithMatchingResultClearsWithoutPrompt() throws {
        let (store, context) = try plannedStore()
        let blueprint = try XCTUnwrap(store.plan?.workouts.first?.blueprint)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_430)
        try store.record(sampleResult(workoutID: blueprint.id, startedAt: startedAt, healthState: .pending))
        try ActiveSessionStore.save(
            snapshot(blueprint: blueprint, startedAt: startedAt, state: .finishing),
            to: context
        )
        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertNil(restored.pendingRecoverySnapshot)
        XCTAssertEqual(restored.results.count, 1)
    }

    func testRepositorySaveFailurePreservesRecoveryAndDoesNotCelebrate() throws {
        let (store, context) = try plannedStore()
        let blueprint = try XCTUnwrap(store.plan?.workouts.first?.blueprint)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_440)
        try ActiveSessionStore.save(
            snapshot(blueprint: blueprint, startedAt: startedAt, state: .finishing),
            to: context
        )
        store.setForceSaveFailureForTesting(true)

        XCTAssertThrowsError(
            try store.record(sampleResult(workoutID: blueprint.id, startedAt: startedAt, healthState: .pending))
        )
        XCTAssertEqual(store.results.count, 0)
        XCTAssertNil(store.celebration)
        XCTAssertEqual(store.plan?.workouts.first?.status, .scheduled)
        XCTAssertNotNil(store.errorMessage)

        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.pendingRecoverySnapshot?.state, .finishing)
        XCTAssertEqual(restored.results.count, 0)
        XCTAssertNil(restored.celebration)
        XCTAssertEqual(restored.plan?.workouts.first?.status, .scheduled)
    }

    func testSavedSnapshotDoesNotProduceStaleRecovery() throws {
        let (_, context) = try makeStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        try ActiveSessionStore.save(
            snapshot(blueprint: blueprint, startedAt: Date(timeIntervalSince1970: 1_700_000_450), state: .saved),
            to: context
        )
        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertNil(restored.pendingRecoverySnapshot)
    }

    func testTerminalSnapshotDoesNotClearFinishingRecovery() throws {
        let (store, context) = try makeStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let startedAt = Date(timeIntervalSince1970: 1_700_000_460)
        try ActiveSessionStore.save(
            snapshot(blueprint: blueprint, startedAt: startedAt, state: .finishing),
            to: context
        )
        store.session.onSnapshot?(
            try snapshot(blueprint: blueprint, startedAt: startedAt, state: .saved)
        )
        let loaded = try ActiveSessionStore.load(from: context)
        XCTAssertEqual(loaded?.state, .finishing)
        XCTAssertNil(store.pendingRecoverySnapshot)
    }
}
