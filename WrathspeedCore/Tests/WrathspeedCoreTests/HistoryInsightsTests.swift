import Foundation
import XCTest
@testable import WrathspeedCore

final class HistoryInsightsTests: XCTestCase {
    func testUnmatchedHealthRunCountsTowardLoadNotAdherence() {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())!.start
        let workout = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: weekStart,
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
        let external = WorkoutResult(
            workoutID: UUID(),
            startedAt: weekStart.addingTimeInterval(3_600),
            duration: 1_800,
            distanceMeters: 4_000,
            averagePaceSecPerKm: 450,
            location: .outdoor,
            source: .appleHealth
        )
        let summary = HistoryInsights.weeklySummary(plan: plan, results: [external], weekStart: weekStart)
        XCTAssertEqual(summary.actualMeters, 4_000)
        XCTAssertEqual(summary.confirmedAdherenceCount, 0)
        XCTAssertEqual(summary.unmatchedExtraMeters, 4_000)
    }

    func testConfirmedMatchCountsAdherenceOnce() {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())!.start
        var completed = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: weekStart,
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        completed.status = .completed
        let result = WorkoutResult(
            workoutID: completed.blueprint.id,
            startedAt: weekStart.addingTimeInterval(3_600),
            duration: 1_800,
            distanceMeters: 5_000,
            averagePaceSecPerKm: 360,
            location: .outdoor,
            matchInfo: WorkoutMatchInfo(state: .matched, scheduledWorkoutID: completed.id)
        )
        completed.result = result
        let plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [completed]
        )
        let duplicate = result
        let summary = HistoryInsights.weeklySummary(plan: plan, results: [result, duplicate], weekStart: weekStart)
        XCTAssertEqual(summary.confirmedAdherenceCount, 1)
        XCTAssertEqual(summary.actualMeters, 5_000)
    }
}
