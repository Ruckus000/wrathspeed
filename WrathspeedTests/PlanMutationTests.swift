import SwiftData
import XCTest
@testable import Wrathspeed
import WrathspeedCore

@MainActor
final class PlanMutationTests: XCTestCase {
    private let modelTypes: [any PersistentModel.Type] = [
        SnapshotEntity.self,
        MigrationMarkerEntity.self,
        AppSettingsEntity.self,
        TrainingPlanEntity.self,
        ScheduledWorkoutEntity.self,
        WorkoutResultEntity.self,
        StrengthSessionEntity.self,
        StrengthSessionResultEntity.self,
        MobilitySessionResultEntity.self,
        PlanChangeEntity.self,
        ActiveSessionSnapshotEntity.self,
    ]

    private func makeStore(reminder: MockWorkoutReminderScheduler = MockWorkoutReminderScheduler()) throws -> (AppStore, ModelContext) {
        let container = try ModelContainer(for: Schema(modelTypes), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let store = AppStore(reminderScheduler: reminder)
        store.attach(context: context)
        return (store, context)
    }

    private func planChangeCount(_ context: ModelContext) -> Int {
        (try? context.fetch(FetchDescriptor<PlanChangeEntity>()).count) ?? 0
    }

    private func samplePlan(workoutDate: Date = Date()) -> TrainingPlan {
        let easy = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: workoutDate,
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        return TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [easy]
        )
    }

    func testSkipWritesOnePlanChangeAndPublishesAfterPersist() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        let watchBefore = store.watchPublicationCountForTesting

        store.skip(workout)
        XCTAssertEqual(planChangeCount(context), 1)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore + 1)
    }

    func testStaleSkipIsIdempotent() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        store.skip(workout)
        let afterFirst = planChangeCount(context)
        let skipped = try XCTUnwrap(store.plan?.workouts.first(where: { $0.id == workout.id }))
        store.skip(skipped)
        XCTAssertEqual(planChangeCount(context), afterFirst)
    }

    func testMovePersistsAndSurvivesRelaunch() throws {
        let reminder = MockWorkoutReminderScheduler()
        let (store, context) = try makeStore(reminder: reminder)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)

        store.move(workout, to: tomorrow, scheduledTimeMinutes: 480, reminderEnabled: true)
        XCTAssertEqual(store.plan?.workouts.first?.scheduledTimeMinutes, 480)
        XCTAssertTrue(store.plan?.workouts.first?.reminderEnabled == true)

        let restored = AppStore(reminderScheduler: reminder)
        restored.attach(context: context)
        XCTAssertEqual(restored.plan?.workouts.first?.blueprint.date, Calendar.current.startOfDay(for: tomorrow))
        XCTAssertEqual(restored.plan?.workouts.first?.scheduledTimeMinutes, 480)
    }

    func testPersistFailureRestoresMemoryAndSkipsWatchPublication() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        let originalDate = workout.date
        let watchBefore = store.watchPublicationCountForTesting

        store.setForceSaveFailureAfterMutationForTesting(true)
        store.move(workout, to: Calendar.current.date(byAdding: .day, value: 2, to: Date())!)
        XCTAssertEqual(store.plan?.workouts.first?.date, originalDate)
        XCTAssertEqual(planChangeCount(context), 0)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore)
    }

    func testUndoRestoresOriginalPlan() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        let target = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        store.move(workout, to: target)
        store.undoLastPlanChange()
        XCTAssertEqual(store.plan?.workouts.first?.date, workout.date)
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testFailedUndoLeavesMutatedState() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        let target = Calendar.current.date(byAdding: .day, value: 4, to: Date())!
        store.move(workout, to: target)
        store.setForceSaveFailureAfterMutationForTesting(true)
        store.undoLastPlanChange()
        XCTAssertEqual(store.plan?.workouts.first?.blueprint.date, Calendar.current.startOfDay(for: target))
        XCTAssertEqual(planChangeCount(context), 1)
    }

    func testNotFeeling100OverlayPreservesBasePlan() throws {
        let (store, _) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        let quality = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
            kind: .tempo,
            title: "Tempo",
            steps: [],
            plannedDistanceMeters: 8_000,
            usesPaceTargets: true
        ))
        store.plan?.workouts.append(quality)
        store.save()

        store.applyNotFeeling100(N100Adjustment(start: Date(), dayCount: 7, mode: .reducedDifficulty, returnPace: .balanced))
        XCTAssertEqual(store.plan?.workouts.last?.blueprint.kind, .tempo)
        XCTAssertEqual(store.displayPlan?.workouts.last?.blueprint.kind, .easy)
        store.endNotFeeling100()
        XCTAssertEqual(store.displayPlan?.workouts.last?.blueprint.kind, .tempo)
    }
}
