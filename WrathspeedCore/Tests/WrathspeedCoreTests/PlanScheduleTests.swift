import Foundation
import XCTest
@testable import WrathspeedCore

final class PlanScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makePlan(workouts: [ScheduledWorkout]) -> TrainingPlan {
        TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(
                ability: .intermediate,
                daysPerWeek: 4,
                longRunWeekday: .sunday,
                unit: .kilometers
            ),
            workouts: workouts
        )
    }

    func testNavigableWeekStartsIncludePreviousCurrentAndNext() throws {
        let asOf = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        let weeks = PlanScheduleService.navigableWeekStarts(centeredOn: asOf, calendar: calendar)
        XCTAssertEqual(weeks.count, 3)
        let current = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: asOf)?.start)
        XCTAssertEqual(weeks[1], current)
    }

    func testPreventsTwoRunsSameDay() {
        let day = calendar.startOfDay(for: Date().addingTimeInterval(86_400))
        let existing = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: day,
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        let moving = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: day.addingTimeInterval(3_600),
            kind: .tempo,
            title: "Tempo",
            steps: [],
            plannedDistanceMeters: 6_000,
            usesPaceTargets: true
        ))
        let plan = makePlan(workouts: [existing, moving])
        let validation = PlanScheduleService.canMove(workout: moving, to: day, plan: plan, calendar: calendar)
        XCTAssertFalse(validation.allowed)
    }

    func testRejectsPastDate() {
        let today = calendar.startOfDay(for: Date())
        let workout = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: today,
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        let past = calendar.date(byAdding: .day, value: -1, to: today)!
        let validation = PlanScheduleService.canMove(
            workout: workout,
            to: past,
            plan: makePlan(workouts: [workout]),
            asOf: today,
            calendar: calendar
        )
        XCTAssertFalse(validation.allowed)
    }

    func testAdjacentQualityWarningRequiresOverride() {
        let monday = calendar.startOfDay(for: Date())
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday)!
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let qualityA = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: monday,
            kind: .tempo,
            title: "Tempo",
            steps: [],
            plannedDistanceMeters: 8_000,
            usesPaceTargets: true
        ))
        let qualityB = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: wednesday,
            kind: .intervals,
            title: "Intervals",
            steps: [],
            plannedDistanceMeters: 6_000,
            usesPaceTargets: true
        ))
        let plan = makePlan(workouts: [qualityA, qualityB])
        let validation = PlanScheduleService.canMove(
            workout: qualityB,
            to: tuesday,
            plan: plan,
            asOf: monday,
            calendar: calendar
        )
        XCTAssertTrue(validation.allowed)
        XCTAssertFalse(validation.warnings.isEmpty)
    }

    /// A week already carrying three 12 km runs, plus a 10 km run sitting in the
    /// following, lighter week. Moving that run into the heavy week should warn.
    ///
    /// Dates are aligned to real week boundaries rather than offset by raw days from the
    /// anchor. The warning only fires when the target lands in the same week as the heavy
    /// block, and a plain day offset crossed that boundary or not depending on which
    /// weekday the anchor happened to fall on.
    private func concentratedLoadScenario(
        anchor today: Date
    ) throws -> (plan: TrainingPlan, moving: ScheduledWorkout, target: Date) {
        let heavyWeekStart = try XCTUnwrap(
            calendar.dateInterval(
                of: .weekOfYear,
                for: calendar.date(byAdding: .day, value: 7, to: today)!
            )?.start
        )
        let lightWeekStart = calendar.date(byAdding: .day, value: 7, to: heavyWeekStart)!

        let heavyWorkouts = (0..<3).map { offset in
            ScheduledWorkout(blueprint: WorkoutBlueprint(
                date: calendar.date(byAdding: .day, value: offset, to: heavyWeekStart)!,
                kind: .easy,
                title: "Easy",
                steps: [],
                plannedDistanceMeters: 12_000,
                usesPaceTargets: true
            ))
        }
        let light = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: lightWeekStart,
            kind: .easy,
            title: "Light",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        // Starts in the light week, so moving it into the heavy week is a real move.
        let moving = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: calendar.date(byAdding: .day, value: 1, to: lightWeekStart)!,
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 10_000,
            usesPaceTargets: true
        ))
        // Fourth day of the heavy week: inside it whatever the calendar's first weekday
        // is, and the only one of those four days the heavy block does not occupy.
        let target = calendar.date(byAdding: .day, value: 3, to: heavyWeekStart)!
        return (makePlan(workouts: heavyWorkouts + [light, moving]), moving, target)
    }

    func testConcentratedLoadWarning() throws {
        let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let scenario = try concentratedLoadScenario(anchor: today)
        let validation = PlanScheduleService.canMove(
            workout: scenario.moving,
            to: scenario.target,
            plan: scenario.plan,
            asOf: today,
            calendar: calendar
        )
        XCTAssertTrue(validation.allowed)
        XCTAssertTrue(validation.warnings.contains(where: { $0.contains("concentrate") }))
    }

    /// Guards the fixture above against going back to raw day offsets. That version was
    /// anchored to `Date()` and silently stopped warning on two weekdays out of seven,
    /// so it failed only on the days nobody happened to run it.
    func testConcentratedLoadWarningHoldsWhicheverWeekdayTheSuiteRunsOn() throws {
        let base = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        for dayOffset in 0..<7 {
            let today = calendar.date(byAdding: .day, value: dayOffset, to: base)!
            let scenario = try concentratedLoadScenario(anchor: today)
            let validation = PlanScheduleService.canMove(
                workout: scenario.moving,
                to: scenario.target,
                plan: scenario.plan,
                asOf: today,
                calendar: calendar
            )
            let weekday = calendar.component(.weekday, from: today)
            XCTAssertTrue(validation.allowed, "blocked when the anchor is weekday \(weekday)")
            XCTAssertTrue(
                validation.warnings.contains(where: { $0.contains("concentrate") }),
                "no concentration warning when the anchor is weekday \(weekday)"
            )
        }
    }

    func testLongRunPlacementWarning() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7))!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6))!
        let longRun = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: saturday,
            kind: .longRun,
            title: "Long",
            steps: [],
            plannedDistanceMeters: 16_000,
            usesPaceTargets: true
        ))
        let profile = RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers)
        let plan = makePlan(workouts: [longRun])
        let validation = PlanScheduleService.canMove(
            workout: longRun,
            to: friday,
            plan: plan,
            profile: profile,
            asOf: today,
            calendar: calendar
        )
        XCTAssertTrue(validation.allowed)
        XCTAssertTrue(validation.warnings.contains(where: { $0.contains("Long runs") }))
    }

    func testDaylightSavingPreservesPlanDay() {
        var laCalendar = Calendar(identifier: .gregorian)
        laCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let beforeDST = laCalendar.date(from: DateComponents(
            timeZone: laCalendar.timeZone,
            year: 2026,
            month: 3,
            day: 7,
            hour: 23
        ))!
        let normalized = PlanScheduleService.planDay(for: beforeDST, calendar: laCalendar)
        XCTAssertEqual(laCalendar.component(.day, from: normalized), 7)
    }

    func testNonDefaultTimeZoneMatchesPlanDayBehavior() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let day = tokyo.date(from: DateComponents(timeZone: tokyo.timeZone, year: 2026, month: 5, day: 12, hour: 1))!
        let normalized = PlanScheduleService.planDay(for: day, calendar: tokyo)
        XCTAssertEqual(tokyo.component(.day, from: normalized), 12)
    }
}
