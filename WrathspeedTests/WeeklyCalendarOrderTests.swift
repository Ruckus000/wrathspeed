import Foundation
import XCTest
@testable import Wrathspeed
@testable import WrathspeedCore

/// The weekly calendar renders its workouts with `ForEach`, so array order *is* display order.
///
/// It sorted them with `… ?? [] .sorted { … }`, where `??` binds looser than member access -- so
/// the sort applied to the empty fallback and the filtered list came back in whatever order the
/// plan array happened to be in. `plan.workouts` is sorted when a plan is generated, but both
/// `updateWorkoutInPlan` and `MissedWorkService` rewrite a workout's date in place without
/// re-sorting, so moving a run to another day left it at its old index and it rendered in the
/// wrong place.
///
/// Scrambled input is therefore the case that matters: an already-sorted fixture passes either
/// way and proves nothing.
final class WeeklyCalendarOrderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 1
        return calendar
    }

    /// `ScheduledWorkout.date` is computed from `blueprint.date`, so the date has to be set there.
    private func workout(on date: Date, miles: Double = 5) -> ScheduledWorkout {
        ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: date,
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: miles * 1_609.344,
            usesPaceTargets: true
        ))
    }

    private func plan(_ workouts: [ScheduledWorkout]) -> TrainingPlan {
        TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .miles),
            workouts: workouts
        )
    }

    private func day(_ day: Int, month: Int = 8) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
    }

    func testScrambledWorkoutsComeBackInDateOrder() throws {
        let week = try XCTUnwrap(WeekWindow(startingAt: try day(30), calendar: calendar))
        // Deliberately not in date order -- this is the state a moved workout leaves behind.
        let scrambled = [
            try workout(on: try day(3, month: 9)),
            try workout(on: try day(30)),
            try workout(on: try day(5, month: 9)),
            try workout(on: try day(1, month: 9))
        ]

        let result = WeeklyCalendarView.workouts(in: week, from: plan(scrambled))

        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(
            result.map(\.date),
            result.map(\.date).sorted(),
            "the weekly calendar rendered its workouts in plan-array order, not date order"
        )
    }

    func testTheFirstInstantOfTheWeekIsIncludedAndTheLastIsNot() throws {
        let week = try XCTUnwrap(WeekWindow(startingAt: try day(30), calendar: calendar))
        let onStart = try workout(on: week.start)
        let onEnd = try workout(on: week.end)

        let result = WeeklyCalendarView.workouts(in: week, from: plan([onEnd, onStart]))

        XCTAssertEqual(result.map(\.id), [onStart.id], "the week is half-open: start belongs, end does not")
    }

    func testWorkoutsOutsideTheWeekAreDropped() throws {
        let week = try XCTUnwrap(WeekWindow(startingAt: try day(30), calendar: calendar))
        let inside = try workout(on: try day(1, month: 9))
        let before = try workout(on: try day(29))
        let after = try workout(on: try day(9, month: 9))

        let result = WeeklyCalendarView.workouts(in: week, from: plan([after, inside, before]))

        XCTAssertEqual(result.map(\.id), [inside.id])
    }

    func testEqualDatesAreKeptAndDoNotTrapTheSort() throws {
        let week = try XCTUnwrap(WeekWindow(startingAt: try day(30), calendar: calendar))
        let same = try day(2, month: 9)
        let result = WeeklyCalendarView.workouts(
            in: week,
            from: plan([try workout(on: same), try workout(on: same)])
        )

        // `sorted(by:)` is not guaranteed stable, so assert the count and the dates rather than
        // an order between two equal elements.
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.date)), [same])
    }

    func testNoPlanYieldsNothing() throws {
        let week = try XCTUnwrap(WeekWindow(startingAt: try day(30), calendar: calendar))
        XCTAssertTrue(WeeklyCalendarView.workouts(in: week, from: nil).isEmpty)
    }
}
