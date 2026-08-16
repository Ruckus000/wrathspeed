import SwiftData
import XCTest
@testable import Wrathspeed
import WrathspeedCore

@MainActor
final class WorkoutResultTreadmillTests: XCTestCase {
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
            location: .treadmill,
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

    private func pendingResult(
        workoutID: UUID,
        startedAt: Date,
        healthKitUUID: UUID? = nil,
        distanceMeters: Double = 5_000,
        duration: TimeInterval = 1_800
    ) -> WorkoutResult {
        WorkoutResult(
            workoutID: workoutID,
            startedAt: startedAt,
            duration: duration,
            distanceMeters: distanceMeters,
            averagePaceSecPerKm: distanceMeters > 0 ? (duration / distanceMeters) * 1_000 : 360,
            location: .treadmill,
            healthKitUUID: healthKitUUID,
            source: .wrathspeedPhone,
            healthSync: HealthSyncMetadata(
                state: healthKitUUID == nil ? .pending : .synced,
                healthKitUUID: healthKitUUID
            )
        )
    }

    private func snapshot(blueprint: WorkoutBlueprint, startedAt: Date) throws -> ActiveSessionSnapshot {
        ActiveSessionSnapshot(
            workoutID: blueprint.id,
            blueprintData: try JSONEncoder().encode(blueprint),
            source: .wrathspeedPhone,
            state: .finishing,
            startedAt: startedAt,
            elapsedSeconds: 1_800,
            distanceMeters: 5_000
        )
    }

    private func confirmedPace(duration: TimeInterval = 1_800, meters: Double = 6_200) -> Double {
        (duration / meters) * 1_000
    }

    func testPreMutationFailureKeepsPendingConfirmation() throws {
        let (store, context) = try plannedStore()
        let blueprint = try XCTUnwrap(store.plan?.workouts.first?.blueprint)
        let startedAt = Date(timeIntervalSince1970: 1_730_000_000)
        try ActiveSessionStore.save(snapshot(blueprint: blueprint, startedAt: startedAt), to: context)
        let watchBefore = store.watchPublicationCountForTesting

        store.pendingTreadmillDistance = PendingTreadmillDistance(
            result: pendingResult(workoutID: blueprint.id, startedAt: startedAt),
            estimateMeters: 5_000
        )
        store.setForceSaveFailureForTesting(true)
        store.confirmTreadmillDistance(6.2)

        XCTAssertNotNil(store.pendingTreadmillDistance)
        XCTAssertEqual(store.pendingTreadmillDistance?.result.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(store.pendingTreadmillDistance?.result.averagePaceSecPerKm ?? 0, confirmedPace(), accuracy: 0.01)
        XCTAssertEqual(store.results.count, 0)
        XCTAssertEqual(store.plan?.workouts.first?.status, .scheduled)
        XCTAssertNil(store.plan?.workouts.first?.result)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.celebration)
        XCTAssertNil(store.toastMessage)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 0)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .finishing)
    }

    func testPostMutationFailureKeepsPendingAndLeavesNoEntity() throws {
        let (store, context) = try plannedStore()
        let blueprint = try XCTUnwrap(store.plan?.workouts.first?.blueprint)
        let startedAt = Date(timeIntervalSince1970: 1_730_000_010)
        try ActiveSessionStore.save(snapshot(blueprint: blueprint, startedAt: startedAt), to: context)
        let watchBefore = store.watchPublicationCountForTesting

        store.pendingTreadmillDistance = PendingTreadmillDistance(
            result: pendingResult(workoutID: blueprint.id, startedAt: startedAt),
            estimateMeters: 5_000
        )
        store.setForceSaveFailureAfterMutationForTesting(true)
        store.confirmTreadmillDistance(6.2)

        XCTAssertNotNil(store.pendingTreadmillDistance)
        XCTAssertEqual(store.pendingTreadmillDistance?.result.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(store.pendingTreadmillDistance?.result.averagePaceSecPerKm ?? 0, confirmedPace(), accuracy: 0.01)
        XCTAssertEqual(store.results.count, 0)
        XCTAssertEqual(store.plan?.workouts.first?.status, .scheduled)
        XCTAssertNil(store.plan?.workouts.first?.result)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 0)
        XCTAssertFalse(context.hasChanges)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.celebration)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore)
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .finishing)

        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 0)
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .finishing)
    }

    func testRetryAfterFailureSavesConfirmedDistanceOnce() throws {
        let (store, context) = try plannedStore()
        let blueprint = try XCTUnwrap(store.plan?.workouts.first?.blueprint)
        let startedAt = Date(timeIntervalSince1970: 1_730_000_020)
        try ActiveSessionStore.save(snapshot(blueprint: blueprint, startedAt: startedAt), to: context)
        let watchBefore = store.watchPublicationCountForTesting

        store.pendingTreadmillDistance = PendingTreadmillDistance(
            result: pendingResult(workoutID: blueprint.id, startedAt: startedAt),
            estimateMeters: 5_000
        )
        store.setForceSaveFailureAfterMutationForTesting(true)
        store.confirmTreadmillDistance(6.2)
        XCTAssertEqual(store.results.count, 0)
        XCTAssertNotNil(store.pendingTreadmillDistance)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore)

        store.setForceSaveFailureAfterMutationForTesting(false)
        store.errorMessage = nil
        store.confirmTreadmillDistance(6.2)

        XCTAssertNil(store.pendingTreadmillDistance)
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(store.results.first?.averagePaceSecPerKm ?? 0, confirmedPace(), accuracy: 0.01)
        XCTAssertEqual(store.plan?.workouts.first?.status, .completed)
        XCTAssertEqual(store.plan?.workouts.first?.result?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 1)
        XCTAssertNotNil(store.celebration)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore + 1)
        XCTAssertNil(try ActiveSessionStore.load(from: context))

        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertEqual(restored.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(restored.plan?.workouts.first?.status, .completed)
        XCTAssertNil(restored.pendingRecoverySnapshot)
        XCTAssertNil(restored.pendingTreadmillDistance)
    }

    func testHealthMetadataSurvivesFailureAndRetry() throws {
        let (store, context) = try plannedStore()
        let blueprint = try XCTUnwrap(store.plan?.workouts.first?.blueprint)
        let startedAt = Date(timeIntervalSince1970: 1_730_000_030)
        let healthUUID = UUID()
        let route = [RoutePoint(latitude: 40.7, longitude: -74.0, timestamp: startedAt)]
        let splits = [WorkoutSplit(index: 1, distanceMeters: 1_000, duration: 360, paceSecPerKm: 360)]

        store.pendingTreadmillDistance = PendingTreadmillDistance(
            result: pendingResult(workoutID: blueprint.id, startedAt: startedAt),
            estimateMeters: 5_000
        )
        var synced = pendingResult(workoutID: blueprint.id, startedAt: startedAt, healthKitUUID: healthUUID)
        synced.route = route
        synced.splits = splits
        store.testing_handleWorkoutResult(synced)

        XCTAssertEqual(store.pendingTreadmillDistance?.result.healthKitUUID, healthUUID)
        XCTAssertEqual(store.pendingTreadmillDistance?.result.healthSync.state, .synced)
        XCTAssertEqual(store.pendingTreadmillDistance?.result.distanceMeters ?? 0, 5_000, accuracy: 0.01)

        store.setForceSaveFailureForTesting(true)
        store.confirmTreadmillDistance(6.2)
        XCTAssertEqual(store.pendingTreadmillDistance?.result.healthKitUUID, healthUUID)
        XCTAssertEqual(store.pendingTreadmillDistance?.result.route, route)
        XCTAssertEqual(store.pendingTreadmillDistance?.result.splits, splits)
        XCTAssertEqual(store.pendingTreadmillDistance?.result.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(store.results.count, 0)

        store.setForceSaveFailureForTesting(false)
        store.confirmTreadmillDistance(6.2)
        XCTAssertNil(store.pendingTreadmillDistance)
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.healthKitUUID, healthUUID)
        XCTAssertEqual(store.results.first?.healthSync.state, .synced)
        XCTAssertEqual(store.results.first?.route, route)
        XCTAssertEqual(store.results.first?.splits, splits)
        XCTAssertEqual(store.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)

        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.results.first?.healthKitUUID, healthUUID)
        XCTAssertEqual(restored.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(restored.results.first?.route, route)
        XCTAssertEqual(restored.results.first?.splits, splits)
    }

    func testDifferentStartedAtIsNotTreatedAsPendingResult() throws {
        let (store, _) = try plannedStore()
        let blueprint = try XCTUnwrap(store.plan?.workouts.first?.blueprint)
        let startedAt = Date(timeIntervalSince1970: 1_730_000_040)
        let otherStartedAt = startedAt.addingTimeInterval(120)
        let otherUUID = UUID()

        store.pendingTreadmillDistance = PendingTreadmillDistance(
            result: pendingResult(workoutID: blueprint.id, startedAt: startedAt),
            estimateMeters: 5_000
        )
        store.testing_handleWorkoutResult(
            pendingResult(workoutID: blueprint.id, startedAt: otherStartedAt, healthKitUUID: otherUUID)
        )

        XCTAssertEqual(store.pendingTreadmillDistance?.result.startedAt, startedAt)
        XCTAssertNil(store.pendingTreadmillDistance?.result.healthKitUUID)
        XCTAssertEqual(store.pendingTreadmillDistance?.result.healthSync.state, .pending)
        XCTAssertEqual(store.pendingTreadmillDistance?.result.distanceMeters ?? 0, 5_000, accuracy: 0.01)
        XCTAssertNotEqual(store.pendingTreadmillDistance?.result.healthKitUUID, otherUUID)
    }

    func testLateSyncedCallbackPreservesConfirmedDistanceAndEnrichesHealth() throws {
        let (store, context) = try plannedStore()
        let blueprint = try XCTUnwrap(store.plan?.workouts.first?.blueprint)
        let startedAt = Date(timeIntervalSince1970: 1_730_000_050)
        let healthUUID = UUID()
        let route = [RoutePoint(latitude: 40.71, longitude: -74.01, timestamp: startedAt)]
        let splits = [WorkoutSplit(index: 1, distanceMeters: 1_000, duration: 360, paceSecPerKm: 360)]
        try ActiveSessionStore.save(snapshot(blueprint: blueprint, startedAt: startedAt), to: context)

        store.pendingTreadmillDistance = PendingTreadmillDistance(
            result: pendingResult(workoutID: blueprint.id, startedAt: startedAt),
            estimateMeters: 5_000
        )
        store.confirmTreadmillDistance(6.2)

        XCTAssertNil(store.pendingTreadmillDistance)
        XCTAssertEqual(store.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(store.results.first?.averagePaceSecPerKm ?? 0, confirmedPace(), accuracy: 0.01)

        var late = pendingResult(
            workoutID: blueprint.id,
            startedAt: startedAt,
            healthKitUUID: healthUUID,
            distanceMeters: 5_000
        )
        late.route = route
        late.splits = splits
        store.testing_handleWorkoutResult(late)

        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(store.results.first?.averagePaceSecPerKm ?? 0, confirmedPace(), accuracy: 0.01)
        XCTAssertEqual(store.results.first?.healthKitUUID, healthUUID)
        XCTAssertEqual(store.results.first?.healthSync.state, .synced)
        XCTAssertEqual(store.results.first?.route, route)
        XCTAssertEqual(store.results.first?.splits, splits)
        XCTAssertEqual(store.plan?.workouts.first?.result?.distanceMeters ?? 0, 6_200, accuracy: 0.01)

        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertEqual(restored.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(restored.results.first?.averagePaceSecPerKm ?? 0, confirmedPace(), accuracy: 0.01)
        XCTAssertEqual(restored.results.first?.healthKitUUID, healthUUID)
        XCTAssertEqual(restored.results.first?.healthSync.state, .synced)
        XCTAssertEqual(restored.results.first?.route, route)
        XCTAssertEqual(restored.results.first?.splits, splits)
    }
}
