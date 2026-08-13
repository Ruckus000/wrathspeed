import Foundation
import XCTest
@testable import WrathspeedCore

final class HealthImportTests: XCTestCase {
    func testUUIDDedupMergesImportedOntoExisting() {
        let uuid = UUID()
        let existing = WorkoutResult(
            workoutID: UUID(),
            startedAt: Date(),
            duration: 1_800,
            distanceMeters: 5_000,
            averagePaceSecPerKm: 360,
            location: .outdoor,
            healthKitUUID: uuid,
            source: .wrathspeedPhone
        )
        let imported = ImportedHealthWorkout(
            healthKitUUID: uuid,
            startedAt: existing.startedAt,
            endedAt: existing.startedAt.addingTimeInterval(2_000),
            duration: 2_000,
            distanceMeters: 5_400,
            location: .outdoor
        )
        let merged = HealthImportMerge.merge(existing: [existing], imports: [imported])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].distanceMeters, 5_400)
        XCTAssertEqual(merged[0].healthKitUUID, uuid)
        XCTAssertEqual(merged[0].source, .wrathspeedPhone)
    }

    func testAmbiguousMatchingRanksClosest() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date())
        let result = WorkoutResult(
            workoutID: UUID(),
            startedAt: day.addingTimeInterval(18_000),
            duration: 2_400,
            distanceMeters: 8_000,
            averagePaceSecPerKm: 300,
            location: .outdoor,
            source: .appleHealth
        )
        let close = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: day.addingTimeInterval(18_100),
            kind: .tempo,
            title: "Tempo",
            location: .outdoor,
            steps: [],
            plannedDistanceMeters: 8_000,
            usesPaceTargets: true
        ))
        let far = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: day.addingTimeInterval(8_000),
            kind: .easy,
            title: "Easy",
            location: .outdoor,
            steps: [],
            plannedDistanceMeters: 8_500,
            usesPaceTargets: true
        ))
        let plan = TrainingPlan(
            goal: TrainingGoal(kind: .tenK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [close, far]
        )
        let best = WorkoutMatcher.bestSuggestion(for: result, plan: plan, calendar: calendar)
        XCTAssertEqual(best, close.id)
    }

    func testRejectedMatchingDoesNotResuggestSameWorkout() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date())
        let result = WorkoutResult(
            workoutID: UUID(),
            startedAt: day.addingTimeInterval(18_000),
            duration: 2_400,
            distanceMeters: 8_000,
            averagePaceSecPerKm: 300,
            location: .outdoor,
            source: .appleHealth,
            matchInfo: WorkoutMatchInfo(state: .ignored, rejectedWorkoutIDs: [UUID()])
        )
        let workout = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: day.addingTimeInterval(18_100),
            kind: .tempo,
            title: "Tempo",
            location: .outdoor,
            steps: [],
            plannedDistanceMeters: 8_000,
            usesPaceTargets: true
        ))
        var rejected = result.matchInfo
        rejected.rejectedWorkoutIDs = [workout.id]
        let updated = WorkoutResult(
            workoutID: result.workoutID,
            startedAt: result.startedAt,
            duration: result.duration,
            distanceMeters: result.distanceMeters,
            averagePaceSecPerKm: result.averagePaceSecPerKm,
            location: result.location,
            source: .appleHealth,
            matchInfo: rejected
        )
        let plan = TrainingPlan(
            goal: TrainingGoal(kind: .tenK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [workout]
        )
        XCTAssertNil(WorkoutMatcher.bestSuggestion(for: updated, plan: plan, rejectedIDs: Set([workout.id]), calendar: calendar))
    }

    func testMissingOptionalMetricsStillImports() {
        let imported = ImportedHealthWorkout(
            healthKitUUID: UUID(),
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(1_800),
            duration: 1_800,
            distanceMeters: 4_500,
            location: .outdoor
        )
        let result = imported.asWorkoutResult()
        XCTAssertNil(result.heartRateAverage)
        XCTAssertNil(result.cadenceAverage)
        XCTAssertEqual(result.source, .appleHealth)
    }
}
