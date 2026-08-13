import Foundation
import XCTest
@testable import WrathspeedCore

final class PlanScheduleTests: XCTestCase {
    func testPreventsTwoRunsSameDay() {
        let calendar = Calendar(identifier: .gregorian)
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
        let plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [existing, moving]
        )
        let validation = PlanScheduleService.canMove(workout: moving, to: day, plan: plan, calendar: calendar)
        XCTAssertFalse(validation.allowed)
    }
}
