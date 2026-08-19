import SwiftData
import XCTest
@testable import Wrathspeed
import WrathspeedCore

@MainActor
final class HealthImportPersistenceTests: XCTestCase {
    private func makeStore(importer: MockHealthImportService) throws -> (AppStore, ModelContext) {
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
        store.attach(context: context, healthImporter: importer)
        return (store, context)
    }

    private func onboardedStore(importer: MockHealthImportService) throws -> (AppStore, ModelContext) {
        let pair = try makeStore(importer: importer)
        let workout = ScheduledWorkout(
            blueprint: WorkoutBlueprint(
                date: Date(),
                kind: .easy,
                title: "Easy",
                steps: [],
                plannedDistanceMeters: 5_000,
                usesPaceTargets: true
            )
        )
        pair.0.hasOnboarded = true
        pair.0.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [workout]
        )
        pair.0.profile = pair.0.plan?.profile
        pair.0.save()
        return pair
    }

    private func importedWorkout(uuid: UUID, startedAt: Date) -> ImportedHealthWorkout {
        ImportedHealthWorkout(
            healthKitUUID: uuid,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            duration: 1_800,
            distanceMeters: 5_000,
            location: .outdoor
        )
    }

    func testImportPersistFailureRestoresStateAndDoesNotAdvanceAnchor() async throws {
        let mock = MockHealthImportService()
        let uuid = UUID()
        let startedAt = Date().addingTimeInterval(-3_600)
        mock.workouts = [importedWorkout(uuid: uuid, startedAt: startedAt)]
        let (store, context) = try onboardedStore(importer: mock)
        let previousResults = store.results
        let previousPlan = store.plan
        let previousAnchor = try HealthImportAnchorStore.load(from: context)

        store.setForceSaveFailureForTesting(true)
        await store.importHealthWorkouts()

        XCTAssertEqual(store.results, previousResults)
        XCTAssertEqual(store.plan, previousPlan)
        XCTAssertEqual(try HealthImportAnchorStore.load(from: context), previousAnchor)
        XCTAssertNotNil(store.healthImportErrorMessage)
        XCTAssertEqual(mock.importCallCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 0)
    }

    func testImportRetryAfterFailureImportsOnce() async throws {
        let mock = MockHealthImportService()
        let uuid = UUID()
        let startedAt = Date().addingTimeInterval(-1_800)
        mock.workouts = [importedWorkout(uuid: uuid, startedAt: startedAt)]
        let (store, context) = try onboardedStore(importer: mock)

        store.setForceSaveFailureForTesting(true)
        await store.importHealthWorkouts()
        XCTAssertEqual(store.results.count, 0)
        XCTAssertNil(try HealthImportAnchorStore.load(from: context))

        store.setForceSaveFailureForTesting(false)
        await store.importHealthWorkouts()

        XCTAssertEqual(mock.importCallCount, 2)
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.healthKitUUID, uuid)
        XCTAssertEqual(try HealthImportAnchorStore.load(from: context), mock.anchor)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 1)
    }

    func testImportPostMutationPersistFailureRestoresStateAndRetryImportsOnce() async throws {
        let mock = MockHealthImportService()
        let uuid = UUID()
        let startedAt = Date().addingTimeInterval(-2_400)
        mock.workouts = [importedWorkout(uuid: uuid, startedAt: startedAt)]
        let (store, context) = try onboardedStore(importer: mock)
        let previousResults = store.results
        let previousPlan = store.plan
        let previousAnchor = try HealthImportAnchorStore.load(from: context)
        let previousToast = store.toastMessage
        let previousCelebration = store.celebration

        store.setForceSaveFailureAfterMutationForTesting(true)
        await store.importHealthWorkouts()

        XCTAssertEqual(store.results, previousResults)
        XCTAssertEqual(store.plan, previousPlan)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 0)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try HealthImportAnchorStore.load(from: context), previousAnchor)
        XCTAssertNotNil(store.healthImportErrorMessage)
        XCTAssertEqual(store.toastMessage, previousToast)
        XCTAssertEqual(store.celebration, previousCelebration)
        XCTAssertEqual(mock.importCallCount, 1)

        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 0)
        XCTAssertEqual(try HealthImportAnchorStore.load(from: context), previousAnchor)

        store.setForceSaveFailureAfterMutationForTesting(false)
        store.healthImportErrorMessage = nil
        await store.importHealthWorkouts()

        XCTAssertEqual(mock.importCallCount, 2)
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.healthKitUUID, uuid)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 1)
        XCTAssertEqual(try HealthImportAnchorStore.load(from: context), mock.anchor)
        XCTAssertNil(store.healthImportErrorMessage)

        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertEqual(restored.results.first?.healthKitUUID, uuid)
        XCTAssertEqual(Set(restored.results.map(\.id)).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 1)
    }

    private func treadmillPlanStore(importer: MockHealthImportService) throws -> (AppStore, ModelContext) {
        let pair = try makeStore(importer: importer)
        let workout = ScheduledWorkout(
            blueprint: WorkoutBlueprint(
                date: Date(),
                kind: .easy,
                title: "Easy",
                location: .treadmill,
                steps: [],
                plannedDistanceMeters: 5_000,
                usesPaceTargets: true
            )
        )
        pair.0.hasOnboarded = true
        pair.0.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [workout]
        )
        pair.0.profile = pair.0.plan?.profile
        pair.0.save()
        return pair
    }

    private func confirmedTreadmillResult(
        workoutID: UUID,
        startedAt: Date,
        healthKitUUID: UUID,
        source: WorkoutSource = .wrathspeedPhone,
        distanceMeters: Double = 6_200,
        duration: TimeInterval = 1_800
    ) -> WorkoutResult {
        WorkoutResult(
            workoutID: workoutID,
            startedAt: startedAt,
            duration: duration,
            distanceMeters: distanceMeters,
            averagePaceSecPerKm: (duration / distanceMeters) * 1_000,
            location: .treadmill,
            healthKitUUID: healthKitUUID,
            route: [RoutePoint(latitude: 40.7, longitude: -74.0, timestamp: startedAt)],
            splits: [WorkoutSplit(index: 1, distanceMeters: 1_000, duration: 360, paceSecPerKm: 360)],
            source: source,
            healthSync: HealthSyncMetadata(state: .synced, healthKitUUID: healthKitUUID)
        )
    }

    private func healthImport(
        uuid: UUID,
        startedAt: Date,
        duration: TimeInterval = 1_920,
        distanceMeters: Double = 5_000
    ) -> ImportedHealthWorkout {
        ImportedHealthWorkout(
            healthKitUUID: uuid,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            duration: duration,
            distanceMeters: distanceMeters,
            location: .treadmill,
            heartRateAverage: 148,
            energyKilocalories: 410,
            cadenceAverage: 172
        )
    }

    func testAutomaticImportPreservesConfirmedPlannedTreadmillDistance() async throws {
        let mock = MockHealthImportService()
        let (store, context) = try treadmillPlanStore(importer: mock)
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.id)
        let startedAt = Date().addingTimeInterval(-3_600)
        let uuid = UUID()
        try store.record(confirmedTreadmillResult(workoutID: workoutID, startedAt: startedAt, healthKitUUID: uuid))

        let watchBefore = store.watchPublicationCountForTesting
        let celebrationBefore = store.celebration
        mock.workouts = [healthImport(uuid: uuid, startedAt: startedAt)]

        await store.importHealthWorkouts()

        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(store.results.first?.averagePaceSecPerKm ?? 0, (1_920 / 6_200) * 1_000, accuracy: 0.01)
        XCTAssertEqual(store.results.first?.duration ?? 0, 1_920, accuracy: 0.01)
        XCTAssertEqual(store.results.first?.heartRateAverage, 148)
        XCTAssertEqual(store.results.first?.energyKilocalories, 410)
        XCTAssertEqual(store.results.first?.cadenceAverage, 172)
        XCTAssertEqual(store.results.first?.healthSync.state, .synced)
        XCTAssertEqual(store.results.first?.healthKitUUID, uuid)
        XCTAssertEqual(store.results.first?.workoutID, workoutID)
        XCTAssertEqual(store.results.first?.startedAt, startedAt)
        XCTAssertEqual(store.results.first?.source, .wrathspeedPhone)
        XCTAssertEqual(store.plan?.workouts.first?.result?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(store.plan?.workouts.first?.result?.id, store.results.first?.id)
        XCTAssertEqual(store.celebration, celebrationBefore)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore)
        XCTAssertEqual(try HealthImportAnchorStore.load(from: context), mock.anchor)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 1)

        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertEqual(restored.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(restored.results.first?.averagePaceSecPerKm ?? 0, (1_920 / 6_200) * 1_000, accuracy: 0.01)
        XCTAssertEqual(restored.results.first?.heartRateAverage, 148)
        XCTAssertEqual(restored.results.first?.healthKitUUID, uuid)
        XCTAssertEqual(restored.results.first?.id, store.results.first?.id)
        XCTAssertEqual(restored.plan?.workouts.first?.result?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 1)

        let planStatusBeforeDeletion = store.plan?.workouts.first?.status
        mock.workouts = []
        mock.deletedHealthKitUUIDs = [uuid]
        await store.importHealthWorkouts()

        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.id, restored.results.first?.id)
        XCTAssertTrue(store.results.first?.isUnavailableInHealth == true)
        XCTAssertEqual(store.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(store.plan?.workouts.first?.status, planStatusBeforeDeletion)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 1)
    }

    func testAutomaticImportPreservesConfirmedInstantTreadmillDistanceWithoutPlanCopy() async throws {
        let mock = MockHealthImportService()
        let (store, context) = try onboardedStore(importer: mock)
        let startedAt = Date().addingTimeInterval(-2_700)
        let uuid = UUID()
        let workoutID = UUID()
        try store.record(
            confirmedTreadmillResult(
                workoutID: workoutID,
                startedAt: startedAt,
                healthKitUUID: uuid,
                source: .instant
            )
        )
        XCTAssertNil(store.plan?.workouts.first?.result)

        let watchBefore = store.watchPublicationCountForTesting
        let celebrationBefore = store.celebration
        mock.workouts = [healthImport(uuid: uuid, startedAt: startedAt)]

        await store.importHealthWorkouts()

        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(store.results.first?.averagePaceSecPerKm ?? 0, (1_920 / 6_200) * 1_000, accuracy: 0.01)
        XCTAssertEqual(store.results.first?.source, .instant)
        XCTAssertNil(store.plan?.workouts.first?.result)
        XCTAssertEqual(store.celebration, celebrationBefore)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore)

        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertEqual(restored.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(restored.results.first?.source, .instant)
        XCTAssertNil(restored.plan?.workouts.first?.result)
    }

    func testConfirmedTreadmillImportPostMutationFailureRestoresAndRetriesOnce() async throws {
        let mock = MockHealthImportService()
        let (store, context) = try treadmillPlanStore(importer: mock)
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.id)
        let startedAt = Date().addingTimeInterval(-4_800)
        let uuid = UUID()
        try store.record(confirmedTreadmillResult(workoutID: workoutID, startedAt: startedAt, healthKitUUID: uuid))
        let previousResults = store.results
        let previousPlan = store.plan
        let previousAnchor = try HealthImportAnchorStore.load(from: context)
        let previousCelebration = store.celebration
        let watchBefore = store.watchPublicationCountForTesting
        mock.workouts = [healthImport(uuid: uuid, startedAt: startedAt)]

        store.setForceSaveFailureAfterMutationForTesting(true)
        await store.importHealthWorkouts()

        XCTAssertEqual(store.results, previousResults)
        XCTAssertEqual(store.plan, previousPlan)
        XCTAssertEqual(store.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(try HealthImportAnchorStore.load(from: context), previousAnchor)
        XCTAssertNotNil(store.healthImportErrorMessage)
        XCTAssertEqual(store.celebration, previousCelebration)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore)
        XCTAssertEqual(mock.importCallCount, 1)

        store.setForceSaveFailureAfterMutationForTesting(false)
        store.healthImportErrorMessage = nil
        await store.importHealthWorkouts()

        XCTAssertEqual(mock.importCallCount, 2)
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(store.results.first?.averagePaceSecPerKm ?? 0, (1_920 / 6_200) * 1_000, accuracy: 0.01)
        XCTAssertEqual(store.results.first?.heartRateAverage, 148)
        XCTAssertEqual(try HealthImportAnchorStore.load(from: context), mock.anchor)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 1)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore)
    }

    func testImportMatchesHealthSyncUUIDAndKeepsConfirmedTreadmillDistance() async throws {
        let mock = MockHealthImportService()
        let (store, context) = try treadmillPlanStore(importer: mock)
        let workoutID = try XCTUnwrap(store.plan?.workouts.first?.id)
        let startedAt = Date().addingTimeInterval(-3_300)
        let uuid = UUID()
        var confirmed = confirmedTreadmillResult(workoutID: workoutID, startedAt: startedAt, healthKitUUID: uuid)
        confirmed.healthKitUUID = nil
        try store.record(confirmed)

        let watchBefore = store.watchPublicationCountForTesting
        let celebrationBefore = store.celebration
        let toastBefore = store.toastMessage
        mock.workouts = [healthImport(uuid: uuid, startedAt: startedAt)]

        await store.importHealthWorkouts()

        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(store.results.first?.duration ?? 0, 1_920, accuracy: 0.01)
        XCTAssertEqual(store.results.first?.averagePaceSecPerKm ?? 0, (1_920 / 6_200) * 1_000, accuracy: 0.01)
        XCTAssertEqual(store.results.first?.heartRateAverage, 148)
        XCTAssertEqual(store.results.first?.energyKilocalories, 410)
        XCTAssertEqual(store.results.first?.cadenceAverage, 172)
        XCTAssertEqual(store.results.first?.healthKitUUID, uuid)
        XCTAssertEqual(store.results.first?.healthSync.healthKitUUID, uuid)
        XCTAssertEqual(store.results.first?.healthSync.state, .synced)
        XCTAssertEqual(store.plan?.workouts.first?.result?.id, store.results.first?.id)
        XCTAssertEqual(store.plan?.workouts.first?.result?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(store.plan?.workouts.first?.result?.duration ?? 0, 1_920, accuracy: 0.01)
        XCTAssertEqual(
            store.plan?.workouts.first?.result?.averagePaceSecPerKm ?? 0,
            (1_920 / 6_200) * 1_000,
            accuracy: 0.01
        )
        XCTAssertEqual(store.celebration, celebrationBefore)
        XCTAssertEqual(store.toastMessage, toastBefore)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 1)
        XCTAssertEqual(try HealthImportAnchorStore.load(from: context), mock.anchor)

        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 1)
        XCTAssertEqual(restored.results.first?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(restored.results.first?.averagePaceSecPerKm ?? 0, (1_920 / 6_200) * 1_000, accuracy: 0.01)
        XCTAssertEqual(restored.results.first?.healthKitUUID, uuid)
        XCTAssertEqual(restored.results.first?.healthSync.healthKitUUID, uuid)
        XCTAssertEqual(restored.plan?.workouts.first?.result?.id, restored.results.first?.id)
        XCTAssertEqual(restored.plan?.workouts.first?.result?.distanceMeters ?? 0, 6_200, accuracy: 0.01)
        XCTAssertEqual(restored.plan?.workouts.first?.result?.duration ?? 0, 1_920, accuracy: 0.01)
    }
}
