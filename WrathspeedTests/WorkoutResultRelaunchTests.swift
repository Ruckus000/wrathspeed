import SwiftData
import XCTest
@testable import Wrathspeed
import WrathspeedCore

@MainActor
final class WorkoutResultRelaunchTests: XCTestCase {
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
                MobilitySessionEntity.self,
                MobilitySessionResultEntity.self,
                PlanAdjustmentEntity.self,
                PlanChangeEntity.self,
                ActiveSessionSnapshotEntity.self,
                PendingHealthOpEntity.self,
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
        source: WorkoutSource = .wrathspeedPhone,
        route: [RoutePoint]? = nil,
        splits: [WorkoutSplit]? = nil,
        heartRateAverage: Double? = nil,
        energyKilocalories: Double? = nil,
        cadenceAverage: Double? = nil
    ) -> WorkoutResult {
        WorkoutResult(
            workoutID: workoutID,
            startedAt: startedAt,
            duration: 1_800,
            distanceMeters: 5_000,
            averagePaceSecPerKm: 360,
            heartRateAverage: heartRateAverage,
            location: .outdoor,
            healthKitUUID: healthKitUUID,
            route: route,
            splits: splits,
            source: source,
            energyKilocalories: energyKilocalories,
            cadenceAverage: cadenceAverage,
            healthSync: HealthSyncMetadata(state: healthState, healthKitUUID: healthKitUUID)
        )
    }

    private func snapshot(
        blueprint: WorkoutBlueprint,
        startedAt: Date,
        state: ActiveSessionState
    ) throws -> ActiveSessionSnapshot {
        ActiveSessionSnapshot(
            workoutID: blueprint.id,
            blueprintData: try JSONEncoder().encode(blueprint),
            source: .wrathspeedPhone,
            state: state,
            startedAt: startedAt,
            elapsedSeconds: 1_800,
            distanceMeters: 5_000
        )
    }

    private func relaunch(_ context: ModelContext) -> AppStore {
        let store = AppStore()
        store.attach(context: context)
        return store
    }

    func testA_pendingThenSyncedReloadsAsOneSyncedResult() throws {
        let (store, context) = try plannedStore()
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.blueprint.id)
        let startedAt = Date(timeIntervalSince1970: 1_710_000_000)
        let healthUUID = UUID()

        try store.record(sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .pending))
        try store.record(sampleResult(
            workoutID: workoutID,
            startedAt: startedAt,
            healthState: .synced,
            healthKitUUID: healthUUID
        ))

        let restored = relaunch(context)
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertEqual(restored.results.first?.healthSync.state, .synced)
        XCTAssertEqual(restored.results.first?.healthKitUUID, healthUUID)
        XCTAssertEqual(restored.results.first?.healthSync.healthKitUUID, healthUUID)
        XCTAssertEqual(restored.results.first?.id, "hk:\(healthUUID.uuidString)")
    }

    func testB_pendingThenFailedReloadsAsOneFailedResult() throws {
        let (store, context) = try plannedStore()
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.blueprint.id)
        let startedAt = Date(timeIntervalSince1970: 1_710_000_010)

        try store.record(sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .pending))
        var failed = sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .failed)
        failed.healthSync = HealthSyncMetadata(state: .failed, failureMessage: "offline")
        try store.record(failed)

        let restored = relaunch(context)
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertEqual(restored.results.first?.healthSync.state, .failed)
        XCTAssertEqual(restored.results.first?.healthSync.failureMessage, "offline")
    }

    func testC_failedThenSyncedReloadsAsOneSyncedResult() throws {
        let (store, context) = try plannedStore()
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.blueprint.id)
        let startedAt = Date(timeIntervalSince1970: 1_710_000_020)
        let healthUUID = UUID()

        try store.record(sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .failed))
        try store.record(sampleResult(
            workoutID: workoutID,
            startedAt: startedAt,
            healthState: .synced,
            healthKitUUID: healthUUID
        ))

        let restored = relaunch(context)
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertEqual(restored.results.first?.healthSync.state, .synced)
        XCTAssertEqual(restored.results.first?.healthKitUUID, healthUUID)
    }

    func testD_syncedThenPendingRemainsSyncedAfterReload() throws {
        let (store, context) = try plannedStore()
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.blueprint.id)
        let startedAt = Date(timeIntervalSince1970: 1_710_000_030)
        let healthUUID = UUID()

        try store.record(sampleResult(
            workoutID: workoutID,
            startedAt: startedAt,
            healthState: .synced,
            healthKitUUID: healthUUID
        ))
        try store.record(sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .pending))

        let restored = relaunch(context)
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertEqual(restored.results.first?.healthSync.state, .synced)
        XCTAssertEqual(restored.results.first?.healthKitUUID, healthUUID)
    }

    func testE_conflictingHealthKitUUIDsReloadAsTwoResults() throws {
        let (store, context) = try plannedStore()
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.blueprint.id)
        let startedAt = Date(timeIntervalSince1970: 1_710_000_040)
        let firstUUID = UUID()
        let secondUUID = UUID()

        try store.record(sampleResult(
            workoutID: workoutID,
            startedAt: startedAt,
            healthState: .synced,
            healthKitUUID: firstUUID
        ))
        try store.record(sampleResult(
            workoutID: workoutID,
            startedAt: startedAt,
            healthState: .synced,
            healthKitUUID: secondUUID
        ))

        let restored = relaunch(context)
        XCTAssertEqual(restored.results.count, 2)
        let uuids = Set(restored.results.compactMap(\.healthKitUUID))
        XCTAssertEqual(uuids, [firstUUID, secondUUID])
        XCTAssertEqual(Set(restored.results.map(\.id)), ["hk:\(firstUUID.uuidString)", "hk:\(secondUUID.uuidString)"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 2)
    }

    func testF_routeSplitsAndMetadataSurviveEnrichmentAndReload() throws {
        let (store, context) = try plannedStore()
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.blueprint.id)
        let startedAt = Date(timeIntervalSince1970: 1_710_000_050)
        let healthUUID = UUID()
        let route = [RoutePoint(latitude: 40.7, longitude: -74.0, timestamp: startedAt)]
        let splits = [WorkoutSplit(index: 1, distanceMeters: 1_000, duration: 360, paceSecPerKm: 360)]

        try store.record(sampleResult(
            workoutID: workoutID,
            startedAt: startedAt,
            healthState: .pending,
            source: .wrathspeedPhone
        ))
        try store.record(sampleResult(
            workoutID: workoutID,
            startedAt: startedAt,
            healthState: .synced,
            healthKitUUID: healthUUID,
            source: .wrathspeedWatch,
            route: route,
            splits: splits,
            heartRateAverage: 148,
            energyKilocalories: 420,
            cadenceAverage: 172
        ))

        let restored = relaunch(context)
        let result = try XCTUnwrap(restored.results.first)
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertEqual(result.healthSync.state, .synced)
        XCTAssertEqual(result.healthKitUUID, healthUUID)
        XCTAssertEqual(result.route, route)
        XCTAssertEqual(result.splits, splits)
        XCTAssertEqual(result.heartRateAverage, 148)
        XCTAssertEqual(result.energyKilocalories, 420)
        XCTAssertEqual(result.cadenceAverage, 172)
        XCTAssertEqual(result.source, .wrathspeedPhone)
        XCTAssertEqual(result.workoutID, workoutID)
        XCTAssertEqual(result.startedAt, startedAt)
    }

    func testG_stalePendingPlanEmbeddingCannotOverwriteSyncedCanonical() throws {
        let (store, context) = try plannedStore()
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.blueprint.id)
        let startedAt = Date(timeIntervalSince1970: 1_710_000_060)
        let healthUUID = UUID()
        let pending = sampleResult(workoutID: workoutID, startedAt: startedAt, healthState: .pending)

        try store.record(pending)
        try store.record(sampleResult(
            workoutID: workoutID,
            startedAt: startedAt,
            healthState: .synced,
            healthKitUUID: healthUUID,
            route: [RoutePoint(latitude: 1, longitude: 2, timestamp: startedAt)]
        ))

        var plan = try XCTUnwrap(store.plan)
        plan.workouts[0].result = pending
        store.plan = plan
        store.save()

        let restored = relaunch(context)
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertEqual(restored.results.first?.healthSync.state, .synced)
        XCTAssertEqual(restored.results.first?.healthKitUUID, healthUUID)
        XCTAssertEqual(restored.results.first?.route?.count, 1)
        XCTAssertEqual(restored.plan?.workouts.first?.result?.healthSync.state, .synced)
        XCTAssertEqual(restored.plan?.workouts.first?.result?.healthKitUUID, healthUUID)
    }

    func testH_unrelatedSaveDoesNotChangeCanonicalResults() throws {
        let (store, context) = try plannedStore()
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.blueprint.id)
        let startedAt = Date(timeIntervalSince1970: 1_710_000_070)
        let healthUUID = UUID()
        try store.record(sampleResult(
            workoutID: workoutID,
            startedAt: startedAt,
            healthState: .synced,
            healthKitUUID: healthUUID
        ))

        let first = relaunch(context)
        first.cuesEnabled.toggle()
        first.save()

        let second = relaunch(context)
        XCTAssertEqual(second.results.count, 1)
        XCTAssertEqual(second.results.first?.healthKitUUID, healthUUID)
        XCTAssertEqual(second.results.first?.healthSync.state, .synced)
        XCTAssertEqual(second.results.first?.workoutID, workoutID)
        XCTAssertEqual(second.results.first?.startedAt, startedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 1)
    }

    func testMissingRepositoryThrowsAndDoesNotRecord() throws {
        let store = AppStore()
        XCTAssertThrowsError(
            try store.record(sampleResult(workoutID: UUID(), startedAt: Date(), healthState: .pending))
        ) { error in
            XCTAssertEqual(error as? AppPersistenceError, .storageUnavailable)
        }
        XCTAssertEqual(store.results.count, 0)
        XCTAssertNil(store.celebration)
    }

    func testPostMutationSaveFailureRollsBackAndRetrySucceedsOnce() throws {
        let (store, context) = try plannedStore()
        let blueprint = try XCTUnwrap(store.plan?.workouts.first?.blueprint)
        let startedAt = Date(timeIntervalSince1970: 1_710_000_080)
        try ActiveSessionStore.save(
            snapshot(blueprint: blueprint, startedAt: startedAt, state: .finishing),
            to: context
        )

        let resultsBefore = store.results
        let planStatusBefore = store.plan?.workouts.first?.status
        let embeddedBefore = store.plan?.workouts.first?.result
        let celebrationBefore = store.celebration
        let suggestionBefore = store.pendingSuggestion
        let freezeBefore = store.freezeMileage

        store.setForceSaveFailureAfterMutationForTesting(true)
        XCTAssertThrowsError(
            try store.record(sampleResult(workoutID: blueprint.id, startedAt: startedAt, healthState: .pending))
        )

        XCTAssertEqual(store.results, resultsBefore)
        XCTAssertEqual(store.plan?.workouts.first?.status, planStatusBefore)
        XCTAssertEqual(store.plan?.workouts.first?.result, embeddedBefore)
        XCTAssertEqual(store.celebration, celebrationBefore)
        XCTAssertEqual(store.pendingSuggestion, suggestionBefore)
        XCTAssertEqual(store.freezeMileage, freezeBefore)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 0)
        XCTAssertFalse(context.hasChanges)

        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 0)

        let afterUnrelatedSave = relaunch(context)
        XCTAssertEqual(afterUnrelatedSave.results.count, 0)
        XCTAssertEqual(afterUnrelatedSave.pendingRecoverySnapshot?.state, .finishing)
        XCTAssertEqual(afterUnrelatedSave.plan?.workouts.first?.status, .scheduled)
        XCTAssertNil(afterUnrelatedSave.celebration)
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .finishing)

        store.setForceSaveFailureAfterMutationForTesting(false)
        try store.record(sampleResult(workoutID: blueprint.id, startedAt: startedAt, healthState: .pending))
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.plan?.workouts.first?.status, .completed)
        XCTAssertNotNil(store.celebration)
        XCTAssertNil(try ActiveSessionStore.load(from: context))

        let restored = relaunch(context)
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertEqual(restored.results.first?.healthSync.state, .pending)
        XCTAssertEqual(restored.plan?.workouts.first?.status, .completed)
        XCTAssertNil(restored.pendingRecoverySnapshot)
    }
}
