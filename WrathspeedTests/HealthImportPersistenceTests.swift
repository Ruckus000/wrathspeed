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
        XCTAssertNotNil(store.errorMessage)
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
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.toastMessage, previousToast)
        XCTAssertEqual(store.celebration, previousCelebration)
        XCTAssertEqual(mock.importCallCount, 1)

        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 0)
        XCTAssertEqual(try HealthImportAnchorStore.load(from: context), previousAnchor)

        store.setForceSaveFailureAfterMutationForTesting(false)
        store.errorMessage = nil
        await store.importHealthWorkouts()

        XCTAssertEqual(mock.importCallCount, 2)
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.healthKitUUID, uuid)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 1)
        XCTAssertEqual(try HealthImportAnchorStore.load(from: context), mock.anchor)
        XCTAssertNil(store.errorMessage)

        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertEqual(restored.results.first?.healthKitUUID, uuid)
        XCTAssertEqual(Set(restored.results.map(\.id)).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, 1)
    }
}
