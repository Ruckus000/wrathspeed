import Foundation
import XCTest
@testable import WrathspeedCore

final class MissedWorkTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDetectsMissedScheduledRuns() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let missedDay = calendar.date(byAdding: .day, value: -2, to: today)!
        let workout = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: missedDay,
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        let plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [workout]
        )
        let situation = MissedWorkService.detect(plan: plan, asOf: today, calendar: calendar)
        XCTAssertEqual(situation?.missedWorkouts.count, 1)
    }

    func testRacePlanCannotExtend() {
        let raceGoal = TrainingGoal(kind: .fiveK, raceDate: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!)
        XCTAssertFalse(MissedWorkService.canExtend(plan: TrainingPlan(
            goal: raceGoal,
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: []
        )))
    }

    func testSkipDoesNotStackMissedWork() throws {
        let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let missed = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: calendar.date(byAdding: .day, value: -1, to: today)!,
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        let future = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: calendar.date(byAdding: .day, value: 2, to: today)!,
            kind: .easy,
            title: "Future",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        let plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [missed, future]
        )
        let situation = try XCTUnwrap(MissedWorkService.detect(plan: plan, asOf: today, calendar: calendar))
        let updated = MissedWorkService.applySkip(plan: plan, situation: situation)
        XCTAssertEqual(updated.workouts.first(where: { $0.id == missed.id })?.status, .skipped)
        XCTAssertEqual(updated.workouts.first(where: { $0.id == future.id })?.date, future.date)
    }
}
