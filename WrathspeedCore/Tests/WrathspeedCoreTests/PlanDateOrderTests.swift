import Foundation
import XCTest
@testable import WrathspeedCore

/// `TrainingPlan.workouts` is expected to be in date order: every producer sorts before handing a
/// plan over, and the weekly calendar renders the array straight into a `ForEach`, so array order
/// is display order.
///
/// Rescheduling used to break it silently. Moving a workout rewrites `blueprint.date` in place,
/// which leaves it at its old index — so a run moved to Friday still rendered where Tuesday had
/// been. These pin the invariant at the point it is restored.
final class PlanDateOrderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }

    private func workout(on date: Date, kind: WorkoutKind = .easy, status: WorkoutStatus = .scheduled) -> ScheduledWorkout {
        var workout = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: date,
            kind: kind,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        workout.status = status
        return workout
    }

    private func plan(_ workouts: [ScheduledWorkout]) -> TrainingPlan {
        TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: workouts
        )
    }

    private func day(_ offset: Int, from base: Date) throws -> Date {
        try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: base))
    }

    // MARK: - The invariant itself

    func testRestoreDateOrderSortsAScrambledPlan() throws {
        let base = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        var subject = plan([
            try workout(on: try day(5, from: base)),
            try workout(on: try day(1, from: base)),
            try workout(on: try day(9, from: base)),
            try workout(on: try day(3, from: base))
        ])

        subject.restoreDateOrder()

        XCTAssertEqual(subject.workouts.map(\.date), subject.workouts.map(\.date).sorted())
    }

    func testRestoreDateOrderKeepsEveryWorkout() throws {
        let base = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let workouts = [
            try workout(on: try day(4, from: base)),
            try workout(on: try day(0, from: base)),
            try workout(on: try day(4, from: base))
        ]
        var subject = plan(workouts)

        subject.restoreDateOrder()

        XCTAssertEqual(Set(subject.workouts.map(\.id)), Set(workouts.map(\.id)), "sorting must not drop or duplicate")
        XCTAssertEqual(subject.workouts.count, 3, "equal dates are kept, not collapsed")
    }

    // MARK: - The reschedulers that used to break it

    func testMovingMissedWorkLeavesThePlanInDateOrder() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)))
        // The missed run has to land *after* workouts that follow it in the array, or the plan
        // stays sorted by accident and this proves nothing. `applyMoveEligible` puts it on the
        // first open day from today, so today, +1 and +2 are occupied to push it out to +3 —
        // past all three of them, and past its own old index.
        let missed = try workout(on: try day(-2, from: today))
        let subject = plan([
            missed,
            try workout(on: try day(0, from: today)),
            try workout(on: try day(1, from: today)),
            try workout(on: try day(2, from: today))
        ])
        let situation = try XCTUnwrap(
            MissedWorkService.detect(plan: subject, asOf: today, calendar: calendar),
            "fixture should present as missed work"
        )

        let result = MissedWorkService.applyMoveEligible(
            plan: subject,
            situation: situation,
            calendar: calendar,
            asOf: today
        )

        let dates: [Date] = result.workouts.map(\.date)
        XCTAssertEqual(
            dates,
            dates.sorted(),
            "rescheduling missed work left the plan out of date order"
        )
        XCTAssertEqual(result.workouts.count, subject.workouts.count, "no workout lost in the move")
    }
}
