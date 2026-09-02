import XCTest
@testable import WrathspeedCore

/// `w1..wN` are computed in two places -- the prompt context and the proposal diff -- from one
/// function. These pin the contract that makes that safe: the numbering skips nothing the model
/// can act on, includes nothing it cannot, and the capped list the model sees is a prefix of the
/// uncapped list the card uses.
final class CoachReferenceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }

    private var asOf: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))! }

    private func workout(dayOffset: Int, status: WorkoutStatus = .scheduled) -> ScheduledWorkout {
        let date = calendar.date(byAdding: .day, value: dayOffset, to: asOf)!
        var workout = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: date, kind: .easy, title: "Easy", steps: [],
            plannedDistanceMeters: 5_000, usesPaceTargets: true
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

    func testCompletedAndPastWorkoutsAreNotNumbered() {
        // Late in a plan: many finished runs precede today. Before, these took the first 28
        // numbers and the prompt rendered nothing the coach could edit.
        let past = (1...40).map { workout(dayOffset: -$0, status: .completed) }
        let upcoming = (0..<5).map { workout(dayOffset: $0) }
        let refs = CoachPlanRules.references(in: plan(past + upcoming), asOf: asOf, calendar: calendar)

        XCTAssertEqual(refs.count, 5, "only unstarted workouts get a handle")
        XCTAssertEqual(refs.map(\.reference), ["w1", "w2", "w3", "w4", "w5"])
        XCTAssertEqual(refs.first?.workout.id, upcoming[0].id, "w1 is the first thing the coach can act on")
    }

    func testSkippedAndPastScheduledWorkoutsAreExcluded() {
        // A missed run is `.scheduled` with a past date; the coach cannot edit it either.
        let missed = workout(dayOffset: -2)
        let skipped = workout(dayOffset: 1, status: .skipped)
        let live = workout(dayOffset: 2)
        let refs = CoachPlanRules.references(in: plan([missed, skipped, live]), asOf: asOf, calendar: calendar)

        XCTAssertEqual(refs.map(\.workout.id), [live.id])
    }

    func testTodayCountsAsUnstarted() {
        let today = workout(dayOffset: 0)
        let refs = CoachPlanRules.references(in: plan([today]), asOf: asOf, calendar: calendar)
        XCTAssertEqual(refs.map(\.reference), ["w1"], "a run scheduled for today is still ahead of the runner")
    }

    func testTheModelWindowIsAPrefixOfTheFullNumbering() {
        let many = (0..<40).map { workout(dayOffset: $0) }
        let shuffled = many.shuffled()   // array order must not matter
        let full = CoachPlanRules.references(in: plan(shuffled), asOf: asOf, calendar: calendar)
        let shown = CoachPlanRules.references(
            in: plan(shuffled), asOf: asOf, calendar: calendar, limit: CoachPlanRules.modelReferenceLimit
        )

        XCTAssertEqual(shown.count, 28)
        XCTAssertEqual(full.count, 40)
        XCTAssertEqual(
            shown.map { "\($0.reference):\($0.workout.id)" },
            Array(full.prefix(28)).map { "\($0.reference):\($0.workout.id)" },
            "every number the model sees must mean the same workout on the card"
        )
        XCTAssertEqual(full.map(\.workout.date), full.map(\.workout.date).sorted(), "numbered in date order")
    }

    func testNumberingIsDateOrderNotArrayOrder() {
        let later = workout(dayOffset: 3)
        let sooner = workout(dayOffset: 1)
        let refs = CoachPlanRules.references(in: plan([later, sooner]), asOf: asOf, calendar: calendar)
        XCTAssertEqual(refs.map(\.workout.id), [sooner.id, later.id])
    }
}
