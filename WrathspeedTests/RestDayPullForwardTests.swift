import SwiftData
import XCTest
@testable import Wrathspeed
import WrathspeedCore

/// A generated plan runs three to five days a week, so on the other days Today had no way to
/// start the planned session at all -- which is what the "start run isn't working" report
/// turned out to be.
@MainActor
final class RestDayPullForwardTests: XCTestCase {
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

    private func makeStore() throws -> AppStore {
        let container = try ModelContainer(
            for: Schema(modelTypes),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = AppStore(reminderScheduler: MockWorkoutReminderScheduler())
        store.attach(context: ModelContext(container))
        return store
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))!
    }

    private func workout(
        _ offset: Int,
        kind: WorkoutKind = .easy,
        title: String = "Easy",
        status: WorkoutStatus = .scheduled
    ) -> ScheduledWorkout {
        var scheduled = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: day(offset),
            kind: kind,
            title: title,
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        scheduled.status = status
        return scheduled
    }

    private func install(_ workouts: [ScheduledWorkout], on store: AppStore) {
        let profile = RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers)
        store.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: profile,
            workouts: workouts
        )
        store.profile = profile
        store.save()
    }

    func testOffersTomorrowsRunOnARestDay() throws {
        let store = try makeStore()
        install([workout(1)], on: store)

        let next = try XCTUnwrap(store.nextRunToPullForward, "A rest day with a run tomorrow should offer it")
        XCTAssertEqual(next.blueprint.title, "Easy")
    }

    func testNotOfferedWhenTodayAlreadyHasARun() throws {
        let store = try makeStore()
        install([workout(0), workout(2)], on: store)
        XCTAssertNil(store.nextRunToPullForward, "Today already has its own run")

        install([workout(0, status: .completed), workout(2)], on: store)
        XCTAssertNil(store.nextRunToPullForward, "Today's run is done; Today should say so, not offer another")
    }

    /// AdaptationRules.canMoveLongRun caps a long run's travel at 48 hours. Offering a button
    /// whose only outcome is that refusal would be worse than not offering one.
    func testNotOfferedWhenTheNextRunIsALongRunBeyondItsMoveWindow() throws {
        let store = try makeStore()
        install([workout(5, kind: .longRun, title: "Long run")], on: store)
        XCTAssertNil(store.nextRunToPullForward)

        install([workout(1, kind: .longRun, title: "Long run")], on: store)
        XCTAssertNotNil(store.nextRunToPullForward, "Within 48 hours a long run can still move")
    }

    /// A pause block skips every run inside its window, so `upcomingRuns` returns the first
    /// run after it. Pulling that forward is exactly what the user opted out of.
    func testNotOfferedDuringAPauseBlock() throws {
        let store = try makeStore()
        install([workout(6)], on: store)
        store.n100 = N100Adjustment(start: day(-1), dayCount: 7, mode: .pause, returnPace: .balanced)
        XCTAssertTrue(store.isN100PauseActive)
        XCTAssertNil(store.nextRunToPullForward)

        store.n100 = nil
        XCTAssertNotNil(store.nextRunToPullForward, "Outside a pause the same run is offered")
    }

    func testPullingForwardMovesTheRunOntoTodayAndOpensPreflight() throws {
        let store = try makeStore()
        var tomorrow = workout(1)
        // `move` defaults reminderEnabled to false and assigns it unconditionally, so the
        // plain call would silently clear a reminder the user had set.
        tomorrow.reminderEnabled = true
        tomorrow.scheduledTimeMinutes = 7 * 60
        install([tomorrow], on: store)

        let next = try XCTUnwrap(store.nextRunToPullForward)
        store.pullForwardAndStart(next)

        XCTAssertNil(store.errorMessage)
        let today = try XCTUnwrap(store.todaysRuns.first, "The run should now be today's")
        XCTAssertTrue(Calendar.current.isDateInToday(today.date))
        XCTAssertEqual(store.pendingPreflight?.blueprint.id, today.blueprint.id, "Preflight should open for the moved run")
        XCTAssertTrue(today.reminderEnabled, "Moving must not clear the workout's reminder")
        XCTAssertEqual(today.scheduledTimeMinutes, 7 * 60)
        XCTAssertNil(store.nextRunToPullForward, "Today is no longer a rest day")
    }
}
