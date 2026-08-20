import SwiftData
import XCTest
@testable import Wrathspeed
import WrathspeedCore

@MainActor
final class GuidedSessionPersistenceTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([
                SnapshotEntity.self,
                MigrationMarkerEntity.self,
                AppSettingsEntity.self,
                StrengthSessionResultEntity.self,
                MobilitySessionResultEntity.self,
            ]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func testStrengthResultPersistsAndReloads() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)

        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_100_000)
        let result = StrengthSessionResult(
            sessionID: sessionID,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            setLogs: [StrengthSetLog(exerciseID: "squat", completed: true, reps: 10)]
        )
        try store.recordStrengthResult(result)
        XCTAssertEqual(store.strengthResults.count, 1)

        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.strengthResults.count, 1)
        XCTAssertEqual(restored.strengthResults.first?.sessionID, sessionID)
        XCTAssertEqual(restored.strengthResults.first?.setLogs.count, 1)
    }

    func testRepeatedStrengthSessionsCreateDistinctRows() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)

        let sessionID = UUID()
        let firstStart = Date(timeIntervalSince1970: 1_700_200_000)
        let secondStart = Date(timeIntervalSince1970: 1_700_300_000)
        try store.recordStrengthResult(StrengthSessionResult(
            sessionID: sessionID,
            startedAt: firstStart,
            endedAt: firstStart.addingTimeInterval(1_200),
            setLogs: []
        ))
        try store.recordStrengthResult(StrengthSessionResult(
            sessionID: sessionID,
            startedAt: secondStart,
            endedAt: secondStart.addingTimeInterval(1_500),
            setLogs: []
        ))

        XCTAssertEqual(store.strengthResults.count, 2)
        let entities = try context.fetch(FetchDescriptor<StrengthSessionResultEntity>())
        XCTAssertEqual(entities.count, 2)
    }

    func testStrengthResultUpdateDoesNotDuplicateRows() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)

        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_400_000)
        var result = StrengthSessionResult(
            sessionID: sessionID,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(900),
            setLogs: [StrengthSetLog(exerciseID: "squat", completed: false, reps: 8)]
        )
        try store.recordStrengthResult(result)
        result.setLogs = [StrengthSetLog(exerciseID: "squat", completed: true, reps: 10)]
        try store.recordStrengthResult(result)

        XCTAssertEqual(store.strengthResults.count, 1)
        XCTAssertTrue(store.strengthResults.first?.setLogs.first?.completed == true)
        let entities = try context.fetch(FetchDescriptor<StrengthSessionResultEntity>())
        XCTAssertEqual(entities.count, 1)
    }

    func testSameStrengthIDWithCorrectedStartedAtRemainsOneResult() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)

        let id = UUID()
        let sessionID = UUID()
        let firstStart = Date(timeIntervalSince1970: 1_700_450_000)
        try store.recordStrengthResult(StrengthSessionResult(
            id: id,
            sessionID: sessionID,
            startedAt: firstStart,
            endedAt: firstStart.addingTimeInterval(60),
            setLogs: []
        ))
        try store.recordStrengthResult(StrengthSessionResult(
            id: id,
            sessionID: sessionID,
            startedAt: firstStart.addingTimeInterval(30),
            endedAt: firstStart.addingTimeInterval(90),
            setLogs: [StrengthSetLog(exerciseID: "press", completed: true, reps: 5)]
        ))

        XCTAssertEqual(store.strengthResults.count, 1)
        XCTAssertEqual(store.strengthResults.first?.id, id)
        XCTAssertEqual(store.strengthResults.first?.startedAt, firstStart.addingTimeInterval(30))
        XCTAssertEqual(try context.fetch(FetchDescriptor<StrengthSessionResultEntity>()).count, 1)
    }

    func testStrengthResultsLoadNewestFirst() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)
        let older = Date(timeIntervalSince1970: 1_700_460_000)
        let newer = Date(timeIntervalSince1970: 1_700_470_000)
        try store.recordStrengthResult(StrengthSessionResult(
            sessionID: UUID(),
            startedAt: older,
            endedAt: older.addingTimeInterval(60),
            setLogs: []
        ))
        try store.recordStrengthResult(StrengthSessionResult(
            sessionID: UUID(),
            startedAt: newer,
            endedAt: newer.addingTimeInterval(60),
            setLogs: []
        ))
        XCTAssertEqual(store.strengthResults.first?.startedAt, newer)

        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.strengthResults.first?.startedAt, newer)
    }

    func testMobilityResultPersistsAndReloads() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)

        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_500_000)
        try store.recordMobilityResult(MobilitySessionResult(
            sessionID: sessionID,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            completedMovementIDs: ["stretch"]
        ))

        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.mobilityResults.count, 1)
        XCTAssertEqual(restored.mobilityResults.first?.completedMovementIDs, ["stretch"])
    }

    func testRepeatedMobilitySessionsCreateDistinctRows() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)
        let sessionID = UUID()
        try store.recordMobilityResult(MobilitySessionResult(
            sessionID: sessionID,
            startedAt: Date(timeIntervalSince1970: 1_700_510_000),
            endedAt: Date(timeIntervalSince1970: 1_700_510_600),
            completedMovementIDs: ["a"]
        ))
        try store.recordMobilityResult(MobilitySessionResult(
            sessionID: sessionID,
            startedAt: Date(timeIntervalSince1970: 1_700_520_000),
            endedAt: Date(timeIntervalSince1970: 1_700_520_600),
            completedMovementIDs: ["b"]
        ))
        XCTAssertEqual(store.mobilityResults.count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MobilitySessionResultEntity>()).count, 2)
    }

    func testMobilityResultUpdateDoesNotDuplicateRows() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)
        var result = MobilitySessionResult(
            sessionID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_530_000),
            endedAt: Date(timeIntervalSince1970: 1_700_530_300),
            completedMovementIDs: ["a"]
        )
        try store.recordMobilityResult(result)
        result.completedMovementIDs = ["a", "b"]
        try store.recordMobilityResult(result)
        XCTAssertEqual(store.mobilityResults.count, 1)
        XCTAssertEqual(store.mobilityResults.first?.completedMovementIDs, ["a", "b"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<MobilitySessionResultEntity>()).count, 1)
    }

    func testSameMobilityIDWithCorrectedStartedAtRemainsOneResult() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)
        let id = UUID()
        let sessionID = UUID()
        try store.recordMobilityResult(MobilitySessionResult(
            id: id,
            sessionID: sessionID,
            startedAt: Date(timeIntervalSince1970: 1_700_540_000),
            endedAt: Date(timeIntervalSince1970: 1_700_540_060),
            completedMovementIDs: ["a"]
        ))
        try store.recordMobilityResult(MobilitySessionResult(
            id: id,
            sessionID: sessionID,
            startedAt: Date(timeIntervalSince1970: 1_700_540_030),
            endedAt: Date(timeIntervalSince1970: 1_700_540_090),
            completedMovementIDs: ["a", "b"]
        ))
        XCTAssertEqual(store.mobilityResults.count, 1)
        XCTAssertEqual(store.mobilityResults.first?.startedAt, Date(timeIntervalSince1970: 1_700_540_030))
        XCTAssertEqual(try context.fetch(FetchDescriptor<MobilitySessionResultEntity>()).count, 1)
    }

    func testMobilityResultsLoadNewestFirst() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)
        let older = Date(timeIntervalSince1970: 1_700_550_000)
        let newer = Date(timeIntervalSince1970: 1_700_560_000)
        try store.recordMobilityResult(MobilitySessionResult(
            sessionID: UUID(),
            startedAt: older,
            endedAt: older.addingTimeInterval(30),
            completedMovementIDs: ["old"]
        ))
        try store.recordMobilityResult(MobilitySessionResult(
            sessionID: UUID(),
            startedAt: newer,
            endedAt: newer.addingTimeInterval(30),
            completedMovementIDs: ["new"]
        ))
        XCTAssertEqual(store.mobilityResults.first?.startedAt, newer)
        let restored = AppStore()
        restored.attach(context: context)
        XCTAssertEqual(restored.mobilityResults.first?.startedAt, newer)
    }

    func testStrengthPersistenceFailureLeavesHistoryUnchangedAndThrows() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)
        store.setForceGuidedResultSaveFailureForTesting(true)

        let result = StrengthSessionResult(
            sessionID: UUID(),
            startedAt: Date(),
            endedAt: Date(),
            setLogs: []
        )
        XCTAssertThrowsError(try store.recordStrengthResult(result))
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.errorMessage?.contains("Couldn't save strength session") == true)
        XCTAssertEqual(store.strengthResults.count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StrengthSessionResultEntity>()).count, 0)
    }

    func testMobilityPersistenceFailureLeavesHistoryUnchangedAndThrows() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)
        store.setForceGuidedResultSaveFailureForTesting(true)

        XCTAssertThrowsError(try store.recordMobilityResult(MobilitySessionResult(
            sessionID: UUID(),
            startedAt: Date(),
            endedAt: Date(),
            completedMovementIDs: ["stretch"]
        )))
        XCTAssertEqual(store.mobilityResults.count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MobilitySessionResultEntity>()).count, 0)
        XCTAssertNotNil(store.errorMessage)
    }

    func testLegacyStrengthResultDecodesAsCompleted() throws {
        let id = UUID()
        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_570_000)
        let endedAt = startedAt.addingTimeInterval(900)
        let json = """
        {"id":"\(id.uuidString)","sessionID":"\(sessionID.uuidString)","startedAt":"\(ISO8601DateFormatter().string(from: startedAt))","endedAt":"\(ISO8601DateFormatter().string(from: endedAt))","setLogs":[{"id":"\(UUID().uuidString)","exerciseID":"squat","completed":true,"skipped":false}]}
        """
        let result = try VersionedPayload.decode(StrengthSessionResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.lifecycle, .completed)
        XCTAssertNil(result.progress)
    }

    func testStrengthPartialResumeAndComplete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)

        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_600_000)
        let partialID = UUID()
        let partial = StrengthSessionResult(
            id: partialID,
            sessionID: sessionID,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(300),
            setLogs: [StrengthSetLog(exerciseID: "squat", completed: true, reps: 10, loadValue: 40, loadUnit: "lb")],
            lifecycle: .inProgress,
            progress: StrengthSessionProgress(
                exerciseIndex: 1,
                setIndex: 0,
                restRemainingSeconds: 30,
                currentLoadValue: 42.5,
                currentLoadUnit: "lb"
            )
        )
        try store.recordStrengthResult(partial)

        let restored = AppStore()
        restored.attach(context: context)
        let resumed = GuidedSessionPolicy.inProgressStrength(sessionID: sessionID, in: restored.guidedStrengthResults)
        XCTAssertEqual(resumed?.id, partialID)
        XCTAssertEqual(resumed?.progress?.exerciseIndex, 1)
        XCTAssertEqual(resumed?.progress?.currentLoadUnit, "lb")
        XCTAssertEqual(resumed?.setLogs.first?.loadUnit, "lb")

        var completed = partial
        completed.lifecycle = .completed
        completed.progress = nil
        completed.difficultyRPE = 8
        completed.endedAt = startedAt.addingTimeInterval(1_800)
        try store.recordStrengthResult(completed)

        XCTAssertNil(GuidedSessionPolicy.inProgressStrength(sessionID: sessionID, in: store.guidedStrengthResults))
        XCTAssertEqual(store.strengthResults.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StrengthSessionResultEntity>()).count, 1)
    }

    func testMobilityPartialResumeAndComplete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)

        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_610_000)
        let partialID = UUID()
        let partial = MobilitySessionResult(
            id: partialID,
            sessionID: sessionID,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(120),
            completedMovementIDs: ["leg_swings"],
            routineID: "pre_run",
            lifecycle: .inProgress,
            progress: MobilitySessionProgress(movementIndex: 1, remainingSeconds: 20)
        )
        try store.recordMobilityResult(partial)

        let restored = AppStore()
        restored.attach(context: context)
        let resumed = GuidedSessionPolicy.inProgressMobility(routineID: "pre_run", in: restored.guidedMobilityResults)
        XCTAssertEqual(resumed?.id, partialID)
        XCTAssertEqual(resumed?.progress?.movementIndex, 1)

        var completed = partial
        completed.lifecycle = .completed
        completed.progress = nil
        completed.completedMovementIDs = ["leg_swings", "ankle_circles", "hip_openers"]
        completed.endedAt = startedAt.addingTimeInterval(360)
        try store.recordMobilityResult(completed)

        XCTAssertNil(GuidedSessionPolicy.inProgressMobility(routineID: "pre_run", in: store.guidedMobilityResults))
        XCTAssertEqual(store.mobilityResults.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MobilitySessionResultEntity>()).count, 1)
    }

    func testStrengthHealthFailurePreservesCompletedLocalResult() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)

        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_620_000)
        let resultID = UUID()
        var result = StrengthSessionResult(
            id: resultID,
            sessionID: sessionID,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_200),
            setLogs: [StrengthSetLog(exerciseID: "squat", completed: true, reps: 8)],
            difficultyRPE: 7,
            healthSync: HealthSyncMetadata(state: .failed, failureMessage: "Denied", lastAttemptAt: startedAt.addingTimeInterval(1_200)),
            lifecycle: .completed
        )
        try store.recordStrengthResult(result)

        result.healthSync = HealthSyncMetadata(state: .synced, lastAttemptAt: startedAt.addingTimeInterval(1_500), healthKitUUID: UUID())
        try store.recordStrengthResult(result)

        XCTAssertEqual(store.strengthResults.count, 1)
        XCTAssertEqual(store.strengthResults.first?.lifecycle, .completed)
        XCTAssertEqual(store.strengthResults.first?.healthSync.state, .synced)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StrengthSessionResultEntity>()).count, 1)
    }

    func testMobilityCatalogLoaderBuildsStableSessionsForAllRoutineIDs() throws {
        let date = Date(timeIntervalSince1970: 1_700_630_000)
        let routines = [
            MobilityRoutineTemplate(id: "pre_run", category: .preRun, title: "Pre-Run Primer", durationMinutes: 6, movements: []),
            MobilityRoutineTemplate(id: "post_run", category: .postRun, title: "Post-Run Reset", durationMinutes: 8, movements: []),
            MobilityRoutineTemplate(id: "recovery", category: .recovery, title: "Recovery Flow", durationMinutes: 15, movements: []),
        ]
        let sessions = routines.map { MobilityCatalogLoader.makeSession(from: $0, date: date) }
        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(Set(sessions.map(\.routineID)), Set(["pre_run", "post_run", "recovery"]))
        let preRunAgain = MobilityCatalogLoader.makeSession(from: routines[0], date: date)
        XCTAssertEqual(preRunAgain.id, sessions.first(where: { $0.routineID == "pre_run" })?.id)
    }
}
