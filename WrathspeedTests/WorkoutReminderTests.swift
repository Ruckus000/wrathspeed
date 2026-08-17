import SwiftData
import XCTest
@testable import Wrathspeed
import WrathspeedCore

@MainActor
final class WorkoutReminderTests: XCTestCase {
    private func makeStore(reminder: MockWorkoutReminderScheduler) throws -> (AppStore, ModelContext) {
        let container = try ModelContainer(
            for: Schema([
                SnapshotEntity.self,
                MigrationMarkerEntity.self,
                AppSettingsEntity.self,
                TrainingPlanEntity.self,
                ScheduledWorkoutEntity.self,
                WorkoutResultEntity.self,
                PlanChangeEntity.self,
            ]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = AppStore(reminderScheduler: reminder)
        store.attach(context: context)
        return (store, context)
    }

    func testReminderSchedulingPreservesPlanOnPermissionDenial() async throws {
        let reminder = MockWorkoutReminderScheduler()
        reminder.authorizationGranted = false
        let (store, _) = try makeStore(reminder: reminder)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        store.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [
                ScheduledWorkout(blueprint: WorkoutBlueprint(
                    date: Date(),
                    kind: .easy,
                    title: "Easy",
                    steps: [],
                    plannedDistanceMeters: 5_000,
                    usesPaceTargets: true
                )),
            ]
        )
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)

        store.move(workout, to: tomorrow, scheduledTimeMinutes: 420, reminderEnabled: true)
        await store.awaitReminderReconciliation()
        XCTAssertEqual(store.plan?.workouts.first?.blueprint.date, Calendar.current.startOfDay(for: tomorrow))
        XCTAssertNotNil(store.reminderNotice)
        XCTAssertTrue(reminder.scheduled.isEmpty)
    }

    func testPersistFailureDoesNotScheduleReminder() async throws {
        let reminder = MockWorkoutReminderScheduler()
        let (store, _) = try makeStore(reminder: reminder)
        store.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [
                ScheduledWorkout(blueprint: WorkoutBlueprint(
                    date: Date(),
                    kind: .easy,
                    title: "Easy",
                    steps: [],
                    plannedDistanceMeters: 5_000,
                    usesPaceTargets: true
                )),
            ]
        )
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        store.setForceSaveFailureAfterMutationForTesting(true)
        store.move(workout, to: Calendar.current.date(byAdding: .day, value: 2, to: Date())!, scheduledTimeMinutes: 420, reminderEnabled: true)
        await store.awaitReminderReconciliation()
        XCTAssertTrue(reminder.scheduled.isEmpty)
    }

    func testMoveWithEnabledReminderSchedulesOnce() async throws {
        let reminder = MockWorkoutReminderScheduler()
        let (store, _) = try makeStore(reminder: reminder)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        store.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [
                ScheduledWorkout(blueprint: WorkoutBlueprint(
                    date: Date(),
                    kind: .easy,
                    title: "Easy",
                    steps: [],
                    plannedDistanceMeters: 5_000,
                    usesPaceTargets: true
                )),
            ]
        )
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        store.move(workout, to: tomorrow, scheduledTimeMinutes: 420, reminderEnabled: true)
        await store.awaitReminderReconciliation()
        XCTAssertEqual(reminder.scheduled.count, 1)
    }

    func testUndoMoveRestoresOriginalReminder() async throws {
        let reminder = MockWorkoutReminderScheduler()
        let (store, _) = try makeStore(reminder: reminder)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let originalDay = Calendar.current.startOfDay(for: Date())
        var workout = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: originalDay,
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        workout.reminderEnabled = true
        workout.scheduledTimeMinutes = 420
        store.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [workout]
        )
        store.profile = store.plan?.profile
        store.save()
        let scheduled = try XCTUnwrap(store.plan?.workouts.first)
        store.move(scheduled, to: tomorrow, scheduledTimeMinutes: 420, reminderEnabled: true)
        await store.awaitReminderReconciliation()
        store.undoLastPlanChange()
        await store.awaitReminderReconciliation()
        let fireDate = try XCTUnwrap(reminder.scheduled[scheduled.id])
        XCTAssertEqual(Calendar.current.startOfDay(for: fireDate), originalDay)
    }
}
