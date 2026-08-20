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

    func testConcentratedLoadWarning() {
        let today = calendar.startOfDay(for: Date())
        let lightWeek = calendar.date(byAdding: .day, value: 14, to: today)!
        let heavyWeek = calendar.date(byAdding: .day, value: 7, to: today)!
        let heavyWorkouts = (0..<3).map { offset in
            ScheduledWorkout(blueprint: WorkoutBlueprint(
                date: calendar.date(byAdding: .day, value: offset, to: heavyWeek)!,
                kind: .easy,
                title: "Easy",
                steps: [],
                plannedDistanceMeters: 12_000,
                usesPaceTargets: true
            ))
        }
        let light = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: lightWeek,
            kind: .easy,
            title: "Light",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        let moving = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: calendar.date(byAdding: .day, value: 10, to: today)!,
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 10_000,
            usesPaceTargets: true
        ))
        let plan = makePlan(workouts: heavyWorkouts + [light, moving])
        let targetDay = calendar.date(byAdding: .day, value: 3, to: heavyWeek)!
        let validation = PlanScheduleService.canMove(
            workout: moving,
            to: targetDay,
            plan: plan,
            asOf: today,
            calendar: calendar
        )
        XCTAssertTrue(validation.allowed)
        XCTAssertTrue(validation.warnings.contains(where: { $0.contains("concentrate") }))
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
