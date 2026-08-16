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

    func testLocalTreadmillImportPreservesConfirmedDistanceAndEnrichesMetrics() {
        for source in [WorkoutSource.wrathspeedPhone, .wrathspeedWatch, .instant] {
            let uuid = UUID()
            let workoutID = UUID()
            let startedAt = Date(timeIntervalSince1970: 1_730_100_000)
            let matchInfo = WorkoutMatchInfo(state: .matched, scheduledWorkoutID: UUID())
            let route = [RoutePoint(latitude: 40.7, longitude: -74.0, timestamp: startedAt)]
            let splits = [WorkoutSplit(index: 1, distanceMeters: 1_000, duration: 360, paceSecPerKm: 360)]
            let existing = WorkoutResult(
                workoutID: workoutID,
                startedAt: startedAt,
                duration: 1_800,
                distanceMeters: 6_200,
                averagePaceSecPerKm: (1_800 / 6_200) * 1_000,
                location: .treadmill,
                healthKitUUID: uuid,
                route: route,
                splits: splits,
                source: source,
                matchInfo: matchInfo,
                isUnavailableInHealth: true,
                healthSync: HealthSyncMetadata(state: .synced, healthKitUUID: uuid)
            )
            let imported = ImportedHealthWorkout(
                healthKitUUID: uuid,
                startedAt: startedAt.addingTimeInterval(30),
                endedAt: startedAt.addingTimeInterval(2_000),
                duration: 1_920,
                distanceMeters: 5_000,
                location: .outdoor,
                heartRateAverage: 148,
                energyKilocalories: 410,
                cadenceAverage: 172
            )

            let merged = HealthImportMerge.merge(existing: [existing], imports: [imported])

            XCTAssertEqual(merged.count, 1, "source \(source.rawValue)")
            XCTAssertEqual(merged[0].distanceMeters, 6_200, accuracy: 0.01)
            XCTAssertEqual(merged[0].duration, 1_920, accuracy: 0.01)
            XCTAssertEqual(
                merged[0].averagePaceSecPerKm ?? 0,
                (1_920 / 6_200) * 1_000,
                accuracy: 0.01
            )
            XCTAssertEqual(merged[0].heartRateAverage, 148)
            XCTAssertEqual(merged[0].energyKilocalories, 410)
            XCTAssertEqual(merged[0].cadenceAverage, 172)
            XCTAssertEqual(merged[0].healthSync.state, HealthSyncState.synced)
            XCTAssertEqual(merged[0].healthSync.healthKitUUID, uuid)
            XCTAssertEqual(merged[0].healthKitUUID, uuid)
            XCTAssertFalse(merged[0].isUnavailableInHealth)
            XCTAssertEqual(merged[0].source, source)
            XCTAssertEqual(merged[0].matchInfo, matchInfo)
            XCTAssertEqual(merged[0].route, route)
            XCTAssertEqual(merged[0].splits, splits)
            XCTAssertEqual(merged[0].workoutID, workoutID)
            XCTAssertEqual(merged[0].startedAt, startedAt)
            XCTAssertEqual(merged[0].location, RunLocation.treadmill)
        }
    }

    func testAppleHealthTreadmillImportAcceptsUpdatedDistanceAndPace() {
        let uuid = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_730_100_100)
        let existing = WorkoutResult(
            workoutID: uuid,
            startedAt: startedAt,
            duration: 1_800,
            distanceMeters: 5_000,
            averagePaceSecPerKm: 360,
            location: .treadmill,
            healthKitUUID: uuid,
            source: .appleHealth,
            healthSync: HealthSyncMetadata(state: .synced, healthKitUUID: uuid)
        )
        let imported = ImportedHealthWorkout(
            healthKitUUID: uuid,
            startedAt: startedAt.addingTimeInterval(12),
            endedAt: startedAt.addingTimeInterval(1_920),
            duration: 1_920,
            distanceMeters: 5_400,
            location: .treadmill,
            heartRateAverage: 151
        )

        let merged = HealthImportMerge.merge(existing: [existing], imports: [imported])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].distanceMeters, 5_400, accuracy: 0.01)
        XCTAssertEqual(merged[0].duration, 1_920, accuracy: 0.01)
        XCTAssertEqual(merged[0].averagePaceSecPerKm ?? 0, (1_920 / 5_400) * 1_000, accuracy: 0.01)
        XCTAssertEqual(merged[0].heartRateAverage, 151)
        XCTAssertEqual(merged[0].source, .appleHealth)
        XCTAssertEqual(merged[0].startedAt, imported.startedAt)
        XCTAssertEqual(merged[0].location, .treadmill)
    }

    func testLocalOutdoorImportStillReplacesDistance() {
        let uuid = UUID()
        let workoutID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_730_100_200)
        let existing = WorkoutResult(
            workoutID: workoutID,
            startedAt: startedAt,
            duration: 1_800,
            distanceMeters: 5_000,
            averagePaceSecPerKm: 360,
            location: .outdoor,
            healthKitUUID: uuid,
            source: .wrathspeedPhone,
            healthSync: HealthSyncMetadata(state: .synced, healthKitUUID: uuid)
        )
        let imported = ImportedHealthWorkout(
            healthKitUUID: uuid,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(2_000),
            duration: 2_000,
            distanceMeters: 5_400,
            location: .outdoor,
            heartRateAverage: 140
        )

        let merged = HealthImportMerge.merge(existing: [existing], imports: [imported])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].distanceMeters, 5_400, accuracy: 0.01)
        XCTAssertEqual(merged[0].duration, 2_000, accuracy: 0.01)
        XCTAssertEqual(merged[0].averagePaceSecPerKm, 360)
        XCTAssertEqual(merged[0].heartRateAverage, 140)
        XCTAssertEqual(merged[0].source, .wrathspeedPhone)
        XCTAssertEqual(merged[0].workoutID, workoutID)
        XCTAssertEqual(merged[0].startedAt, startedAt)
        XCTAssertEqual(merged[0].location, .outdoor)
    }
}
