import Foundation
import SwiftData
import XCTest
@testable import Wrathspeed
@testable import WrathspeedCore

@MainActor
final class PersistenceMigrationTests: XCTestCase {
    private let modelTypes: [any PersistentModel.Type] = [
        SnapshotEntity.self,
        MigrationMarkerEntity.self,
        AppSettingsEntity.self,
        TrainingPlanEntity.self,
        ScheduledWorkoutEntity.self,
        WorkoutResultEntity.self,
        StrengthSessionEntity.self,
        StrengthSessionResultEntity.self,
        MobilitySessionEntity.self,
        MobilitySessionResultEntity.self,
        PlanAdjustmentEntity.self,
        PlanChangeEntity.self,
        ActiveSessionSnapshotEntity.self,
        PendingHealthOpEntity.self,
    ]

    func testEmptyInstallMigratesToVersionedRecords() throws {
        let context = try makeContext()
        let repository = AppStateRepository(context: context)
        let state = try repository.load()

        XCTAssertEqual(state.hasOnboarded, PersistedState.initial.hasOnboarded)
        XCTAssertNil(state.profile)
        XCTAssertNil(state.plan)
        XCTAssertTrue(try PersistenceMigration.hasMigrated(in: context))
        XCTAssertNil(repository.migrationError)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettingsEntity>()).count, 1)
    }

    func testMigrationFromInitialLegacySnapshot() throws {
        let context = try makeContext()
        try Persistence.save(.initial, to: context)

        let repository = AppStateRepository(context: context)
        let migrated = try repository.load()

        XCTAssertEqual(migrated.hasOnboarded, false)
        XCTAssertNil(migrated.profile)
        XCTAssertTrue(try PersistenceMigration.hasMigrated(in: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<SnapshotEntity>()).count, 1)
    }

    func testPopulatedLegacySnapshotPreservesImmutablePayloads() throws {
        let legacy = try makePopulatedLegacyState()
        let legacyData = try Persistence.encoder.encode(legacy)

        let context = try makeContext()
        try Persistence.save(legacy, to: context)

        let repository = AppStateRepository(context: context)
        let migrated = try repository.load()
        let migratedData = try Persistence.encoder.encode(migrated)

        XCTAssertTrue(try PersistenceMigration.hasMigrated(in: context))
        XCTAssertEqual(migrated.hasOnboarded, legacy.hasOnboarded)
        XCTAssertEqual(migrated.profile, legacy.profile)
        XCTAssertEqual(migrated.plan?.id, legacy.plan?.id)
        XCTAssertEqual(migrated.plan?.workouts.count, legacy.plan?.workouts.count)
        XCTAssertEqual(migrated.results.count, legacy.results.count)
        XCTAssertEqual(migrated.strengthSessions.count, legacy.strengthSessions.count)
        XCTAssertEqual(migrated.n100, legacy.n100)
        XCTAssertEqual(migrated.strengthPrefs, legacy.strengthPrefs)
        XCTAssertEqual(migrated.cuesEnabled, legacy.cuesEnabled)
        XCTAssertEqual(migrated.freezeMileage, legacy.freezeMileage)
        XCTAssertEqual(migrated.pendingVDOT, legacy.pendingVDOT)
        XCTAssertEqual(migrated.liveMetrics, legacy.liveMetrics)
        XCTAssertEqual(migrated.dataDensity, legacy.dataDensity)
        XCTAssertEqual(migrated.cueStyle, legacy.cueStyle)

        let restoredWorkout = try XCTUnwrap(migrated.plan?.workouts.first(where: { $0.status == .completed }))
        let originalWorkout = try XCTUnwrap(legacy.plan?.workouts.first(where: { $0.status == .completed }))
        XCTAssertEqual(restoredWorkout.id, originalWorkout.id)
        XCTAssertEqual(restoredWorkout.result, originalWorkout.result)
        XCTAssertEqual(restoredWorkout.result?.route, originalWorkout.result?.route)
        XCTAssertEqual(restoredWorkout.result?.splits, originalWorkout.result?.splits)

        XCTAssertNotEqual(legacyData, migratedData)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, legacy.results.count)
    }

    func testRelaunchAfterMigrationIsIdempotent() throws {
        let legacy = try makePopulatedLegacyState()
        let context = try makeContext()
        try Persistence.save(legacy, to: context)

        let first = AppStateRepository(context: context)
        let migratedOnce = try first.load()
        let workoutCount = try context.fetch(FetchDescriptor<ScheduledWorkoutEntity>()).count
        let resultCount = try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count

        let second = AppStateRepository(context: context)
        let migratedTwice = try second.load()

        XCTAssertEqual(migratedOnce.plan?.workouts, migratedTwice.plan?.workouts)
        XCTAssertEqual(migratedOnce.results, migratedTwice.results)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkoutEntity>()).count, workoutCount)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutResultEntity>()).count, resultCount)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MigrationMarkerEntity>()).count, 1)
    }

    func testVersionedSaveRoundTripAfterMigration() throws {
        let context = try makeContext()
        let repository = AppStateRepository(context: context)
        _ = try repository.load()

        var state = try makePopulatedLegacyState()
        state.pendingVDOT = 49
        state.pendingVDOTReason = "Strong tempo"
        try repository.save(state)

        let restored = try AppStateRepository(context: context).load()
        XCTAssertEqual(restored.pendingVDOT, 49)
        XCTAssertEqual(restored.pendingVDOTReason, "Strong tempo")
        XCTAssertEqual(restored.plan?.workouts.count, state.plan?.workouts.count)
    }

    func testFailureMidMigrationLeavesLegacyReadableWithoutMarker() throws {
        var legacy = try makePopulatedLegacyState()
        legacy.profile = nil
        legacy.hasOnboarded = true
        let context = try makeContext()
        try Persistence.save(legacy, to: context)

        XCTAssertThrowsError(try PersistenceMigration.migrate(legacy, into: context)) { error in
            XCTAssertTrue(error is PersistenceMigrationError)
        }

        XCTAssertFalse(try PersistenceMigration.hasMigrated(in: context))
        let legacyReloaded = try Persistence.loadLegacySnapshot(from: context)
        XCTAssertEqual(legacyReloaded.plan?.id, legacy.plan?.id)
        XCTAssertEqual(legacyReloaded.results.count, legacy.results.count)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(modelTypes),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makePopulatedLegacyState() throws -> PersistedState {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let profile = RunnerProfile(
            ability: .intermediate,
            weeklyMileageMeters: 40_000,
            longestRunMeters: 16_000,
            daysPerWeek: 4,
            longRunWeekday: .saturday,
            unit: .kilometers,
            recentRace: RaceResult(distanceMeters: 10_000, duration: 3_200),
            vdot: 48
        )
        let route = [
            RoutePoint(latitude: 40.0, longitude: -74.0, timestamp: today),
            RoutePoint(latitude: 40.01, longitude: -74.01, timestamp: today.addingTimeInterval(600)),
        ]
        let splits = [
            WorkoutSplit(index: 1, distanceMeters: 1_000, duration: 300, paceSecPerKm: 300),
            WorkoutSplit(index: 2, distanceMeters: 1_000, duration: 310, paceSecPerKm: 310),
        ]
        let completed = ScheduledWorkout(
            blueprint: WorkoutBlueprint(
                date: calendar.date(byAdding: .day, value: -2, to: today)!,
                kind: .tempo,
                title: "Tempo",
                steps: [WorkoutStep(name: "Tempo", target: .distance(meters: 8_000), intensity: .zone(.threshold))],
                plannedDistanceMeters: 8_000,
                usesPaceTargets: true
            ),
            status: .completed,
            result: WorkoutResult(
                workoutID: UUID(),
                startedAt: calendar.date(byAdding: .day, value: -2, to: today)!,
                duration: 2_400,
                distanceMeters: 8_100,
                averagePaceSecPerKm: 296,
                heartRateAverage: 158,
                location: .outdoor,
                healthKitUUID: UUID(),
                route: route,
                splits: splits
            )
        )
        let skipped = ScheduledWorkout(
            blueprint: WorkoutBlueprint(
                date: calendar.date(byAdding: .day, value: -1, to: today)!,
                kind: .intervals,
                title: "Intervals",
                steps: [WorkoutStep(name: "Intervals", target: .distance(meters: 6_000), intensity: .zone(.interval))],
                plannedDistanceMeters: 6_000,
                usesPaceTargets: true
            ),
            status: .skipped
        )
        let upcoming = ScheduledWorkout(
            blueprint: WorkoutBlueprint(
                date: calendar.date(byAdding: .day, value: 2, to: today)!,
                kind: .longRun,
                title: "Long Run",
                steps: [WorkoutStep(name: "Long", target: .distance(meters: 16_000), intensity: .zone(.easy))],
                plannedDistanceMeters: 16_000,
                usesPaceTargets: true
            )
        )
        let plan = TrainingPlan(
            goal: TrainingGoal(kind: .halfMarathon, weekCount: 12),
            profile: profile,
            workouts: [completed, skipped, upcoming]
        )
        let squat = StrengthExercise(
            id: "squat",
            name: "Squat",
            focus: [.legsCore],
            equipment: [.bodyweight],
            symbolName: "figure.strengthtraining.traditional",
            defaultReps: 10,
            cue: "Sit back."
        )
        let strength = StrengthSession(
            date: calendar.date(byAdding: .day, value: 1, to: today)!,
            focus: .legsCore,
            title: "Legs",
            sets: [StrengthSet(exercise: squat, sets: 3, reps: 10, restSeconds: 60)],
            durationMinutes: 30
        )
        let n100 = N100Adjustment(
            start: today,
            dayCount: 5,
            mode: .reducedDifficulty,
            returnPace: .balanced
        )
        return PersistedState(
            hasOnboarded: true,
            profile: profile,
            plan: plan,
            n100: n100,
            strengthPrefs: StrengthPreferences(sessionsPerWeek: 2),
            strengthSessions: [strength],
            cuesEnabled: true,
            freezeMileage: true,
            freezeMileageBaselineMeters: 35_000,
            pendingVDOT: 49,
            pendingVDOTReason: "Strong week",
            results: [try XCTUnwrap(completed.result)],
            liveMetrics: [.time, .distance, .heartRate],
            dataDensity: .detailed,
            cueStyle: .minimal
        )
    }
}
