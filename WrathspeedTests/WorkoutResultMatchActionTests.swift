import SwiftData
import XCTest
@testable import Wrathspeed
import WrathspeedCore

@MainActor
final class WorkoutResultMatchActionTests: XCTestCase {
    private func makeStore() throws -> (AppStore, ModelContext) {
        let container = try ModelContainer(
            for: Schema([
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
            ]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)
        return (store, context)
    }

    private func twoWorkoutStore() throws -> (AppStore, ModelContext, ScheduledWorkout, ScheduledWorkout) {
        let pair = try makeStore()
        let first = ScheduledWorkout(
            blueprint: WorkoutBlueprint(
                date: Date(),
                kind: .easy,
                title: "Easy",
                steps: [],
                plannedDistanceMeters: 5_000,
                usesPaceTargets: true
            )
        )
        let second = ScheduledWorkout(
            blueprint: WorkoutBlueprint(
                date: Date().addingTimeInterval(86_400),
                kind: .tempo,
                title: "Tempo",
                steps: [],
                plannedDistanceMeters: 8_000,
                usesPaceTargets: true
            )
        )
        pair.0.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [first, second]
        )
        pair.0.profile = pair.0.plan?.profile
        pair.0.save()
        return (pair.0, pair.1, first, second)
    }

    private func healthResult(
        workoutID: UUID,
        startedAt: Date,
        healthKitUUID: UUID,
        matchInfo: WorkoutMatchInfo = WorkoutMatchInfo()
    ) -> WorkoutResult {
        WorkoutResult(
            workoutID: workoutID,
            startedAt: startedAt,
            duration: 1_800,
            distanceMeters: 5_000,
            averagePaceSecPerKm: 360,
            location: .outdoor,
            healthKitUUID: healthKitUUID,
            source: .appleHealth,
            matchInfo: matchInfo,
            healthSync: HealthSyncMetadata(state: .synced, healthKitUUID: healthKitUUID)
        )
    }

    private func relaunch(_ context: ModelContext) -> AppStore {
        let store = AppStore()
        store.attach(context: context)
        return store
    }

    private func result(_ store: AppStore, uuid: UUID) throws -> WorkoutResult {
        try XCTUnwrap(store.results.first { $0.healthKitUUID == uuid })
    }

    private func seedConflictingResults(
        _ store: AppStore,
        workoutID: UUID,
        startedAt: Date,
        firstUUID: UUID,
        secondUUID: UUID
    ) throws -> (WorkoutResult, WorkoutResult) {
        try store.record(healthResult(workoutID: workoutID, startedAt: startedAt, healthKitUUID: firstUUID))
        try store.record(healthResult(workoutID: workoutID, startedAt: startedAt, healthKitUUID: secondUUID))
        XCTAssertEqual(store.results.count, 2)
        XCTAssertEqual(Set(store.results.map(\.id)).count, 2)
        return (try result(store, uuid: firstUUID), try result(store, uuid: secondUUID))
    }

    func testConfirmingAMatchesOnlyA() throws {
        let (store, _, firstWorkout, _) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_000)
        let uuidA = UUID()
        let uuidB = UUID()
        let (resultA, _) = try seedConflictingResults(store, workoutID: importedID, startedAt: startedAt, firstUUID: uuidA, secondUUID: uuidB)

        store.confirmHealthMatch(resultA, scheduledWorkoutID: firstWorkout.id)

        let afterA = try result(store, uuid: uuidA)
        let afterB = try result(store, uuid: uuidB)
        XCTAssertEqual(afterA.matchInfo.state, .matched)
        XCTAssertEqual(afterA.matchInfo.scheduledWorkoutID, firstWorkout.id)
        XCTAssertEqual(afterB.matchInfo.state, .unmatched)
        XCTAssertNil(afterB.matchInfo.scheduledWorkoutID)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.status, .completed)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.result?.healthKitUUID, uuidA)
    }

    func testRejectingSuggestionForAChangesOnlyA() throws {
        let (store, _, firstWorkout, secondWorkout) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_010)
        let uuidA = UUID()
        let uuidB = UUID()
        _ = try seedConflictingResults(store, workoutID: importedID, startedAt: startedAt, firstUUID: uuidA, secondUUID: uuidB)

        var resultA = try result(store, uuid: uuidA)
        var resultB = try result(store, uuid: uuidB)
        resultA.matchInfo = WorkoutMatchInfo(state: .suggested, suggestedWorkoutID: firstWorkout.id)
        resultB.matchInfo = WorkoutMatchInfo(state: .suggested, suggestedWorkoutID: secondWorkout.id)
        store.results = [resultA, resultB]
        store.save()

        store.rejectHealthMatch(resultA, suggestedWorkoutID: firstWorkout.id)

        let afterA = try result(store, uuid: uuidA)
        let afterB = try result(store, uuid: uuidB)
        XCTAssertTrue(afterA.matchInfo.rejectedWorkoutIDs.contains(firstWorkout.id))
        XCTAssertTrue(WorkoutResultMerge.canonical(of: resultA, in: store.results).matchInfo.rejectedWorkoutIDs.contains(firstWorkout.id))
        XCTAssertFalse(afterB.matchInfo.rejectedWorkoutIDs.contains(firstWorkout.id))
        XCTAssertEqual(afterB.matchInfo.state, .suggested)
        XCTAssertEqual(afterB.matchInfo.suggestedWorkoutID, secondWorkout.id)
        XCTAssertEqual(afterB.healthKitUUID, uuidB)
    }

    func testKeepingAUnmatchedChangesOnlyA() throws {
        let (store, _, firstWorkout, _) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_020)
        let uuidA = UUID()
        let uuidB = UUID()
        _ = try seedConflictingResults(store, workoutID: importedID, startedAt: startedAt, firstUUID: uuidA, secondUUID: uuidB)

        var resultA = try result(store, uuid: uuidA)
        var resultB = try result(store, uuid: uuidB)
        resultA.matchInfo = WorkoutMatchInfo(state: .suggested, suggestedWorkoutID: firstWorkout.id)
        resultB.matchInfo = WorkoutMatchInfo(state: .suggested, suggestedWorkoutID: firstWorkout.id)
        store.results = [resultA, resultB]
        store.save()

        store.keepHealthUnmatched(resultA)

        let afterA = try result(store, uuid: uuidA)
        let afterB = try result(store, uuid: uuidB)
        XCTAssertEqual(afterA.matchInfo.state, .unmatched)
        XCTAssertEqual(WorkoutResultMerge.canonical(of: resultA, in: store.results).matchInfo.state, .unmatched)
        XCTAssertEqual(afterB.matchInfo.state, .suggested)
        XCTAssertEqual(afterB.matchInfo.suggestedWorkoutID, firstWorkout.id)
        XCTAssertEqual(afterB.healthKitUUID, uuidB)
    }

    func testUnmatchingAUnlinksOnlyEmbeddedA() throws {
        let (store, _, firstWorkout, secondWorkout) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_030)
        let uuidA = UUID()
        let uuidB = UUID()
        let (resultA, resultB) = try seedConflictingResults(
            store,
            workoutID: importedID,
            startedAt: startedAt,
            firstUUID: uuidA,
            secondUUID: uuidB
        )

        store.confirmHealthMatch(resultA, scheduledWorkoutID: firstWorkout.id)
        store.confirmHealthMatch(try result(store, uuid: uuidB), scheduledWorkoutID: secondWorkout.id)

        store.unmatchHealthResult(try result(store, uuid: uuidA))

        let afterA = try result(store, uuid: uuidA)
        let afterB = try result(store, uuid: uuidB)
        XCTAssertEqual(afterA.matchInfo.state, .unmatched)
        XCTAssertEqual(WorkoutResultMerge.canonical(of: resultA, in: store.results).matchInfo.state, .unmatched)
        XCTAssertNil(afterA.matchInfo.scheduledWorkoutID)
        XCTAssertEqual(afterB.matchInfo.state, .matched)
        XCTAssertEqual(afterB.matchInfo.scheduledWorkoutID, secondWorkout.id)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.status, .scheduled)
        XCTAssertNil(store.plan?.workouts.first { $0.id == firstWorkout.id }?.result)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == secondWorkout.id }?.status, .completed)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == secondWorkout.id }?.result?.healthKitUUID, uuidB)
        XCTAssertEqual(resultB.healthKitUUID, uuidB)
    }

    func testActionsOnBTargetBIndependently() throws {
        let (store, _, firstWorkout, secondWorkout) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_040)
        let uuidA = UUID()
        let uuidB = UUID()
        let (resultA, resultB) = try seedConflictingResults(
            store,
            workoutID: importedID,
            startedAt: startedAt,
            firstUUID: uuidA,
            secondUUID: uuidB
        )

        store.confirmHealthMatch(resultB, scheduledWorkoutID: secondWorkout.id)

        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.state, .unmatched)
        XCTAssertEqual(try result(store, uuid: uuidB).matchInfo.state, .matched)
        XCTAssertEqual(try result(store, uuid: uuidB).matchInfo.scheduledWorkoutID, secondWorkout.id)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == secondWorkout.id }?.result?.healthKitUUID, uuidB)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.status, .scheduled)

        store.unmatchHealthResult(try result(store, uuid: uuidB))
        XCTAssertEqual(try result(store, uuid: uuidB).matchInfo.state, .unmatched)
        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.state, .unmatched)
        XCTAssertEqual(resultA.healthKitUUID, uuidA)
    }

    func testSaveFailureRestoresSelectedResultAndSibling() throws {
        let (store, _, firstWorkout, _) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_050)
        let uuidA = UUID()
        let uuidB = UUID()
        let (resultA, _) = try seedConflictingResults(
            store,
            workoutID: importedID,
            startedAt: startedAt,
            firstUUID: uuidA,
            secondUUID: uuidB
        )

        store.setForceSaveFailureForTesting(true)
        store.confirmHealthMatch(resultA, scheduledWorkoutID: firstWorkout.id)

        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.state, .unmatched)
        XCTAssertNil(try result(store, uuid: uuidA).matchInfo.scheduledWorkoutID)
        XCTAssertEqual(try result(store, uuid: uuidB).matchInfo.state, .unmatched)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.status, .scheduled)
        XCTAssertNil(store.plan?.workouts.first { $0.id == firstWorkout.id }?.result)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.toastMessage)

        store.setForceSaveFailureAfterMutationForTesting(true)
        store.setForceSaveFailureForTesting(false)
        store.keepHealthUnmatched(try result(store, uuid: uuidA))
        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.state, .unmatched)
        XCTAssertEqual(try result(store, uuid: uuidB).matchInfo.state, .unmatched)
        XCTAssertNil(store.toastMessage)
    }

    func testConfirmAndRelaunchPreservesSelectedMutation() throws {
        let (store, context, firstWorkout, _) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_060)
        let uuidA = UUID()
        let uuidB = UUID()
        let (resultA, _) = try seedConflictingResults(
            store,
            workoutID: importedID,
            startedAt: startedAt,
            firstUUID: uuidA,
            secondUUID: uuidB
        )

        store.confirmHealthMatch(resultA, scheduledWorkoutID: firstWorkout.id)

        let restored = relaunch(context)
        XCTAssertEqual(try result(restored, uuid: uuidA).matchInfo.state, .matched)
        XCTAssertEqual(try result(restored, uuid: uuidA).matchInfo.scheduledWorkoutID, firstWorkout.id)
        XCTAssertEqual(try result(restored, uuid: uuidA).id, "hk:\(uuidA.uuidString)")
        XCTAssertEqual(try result(restored, uuid: uuidB).matchInfo.state, .unmatched)
        XCTAssertEqual(try result(restored, uuid: uuidB).id, "hk:\(uuidB.uuidString)")
        XCTAssertEqual(restored.plan?.workouts.first { $0.id == firstWorkout.id }?.result?.healthKitUUID, uuidA)
        XCTAssertEqual(Set(restored.results.map(\.id)).count, 2)
    }

    func testSuccessfulUnmatchPublishesWatchOnce() throws {
        let (store, _, firstWorkout, _) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_070)
        let uuidA = UUID()
        let uuidB = UUID()
        let (resultA, _) = try seedConflictingResults(
            store,
            workoutID: importedID,
            startedAt: startedAt,
            firstUUID: uuidA,
            secondUUID: uuidB
        )
        store.confirmHealthMatch(resultA, scheduledWorkoutID: firstWorkout.id)
        let before = store.watchPublicationCountForTesting

        store.unmatchHealthResult(try result(store, uuid: uuidA))

        XCTAssertEqual(store.watchPublicationCountForTesting, before + 1)
        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.state, .unmatched)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.status, .scheduled)
        XCTAssertEqual(try result(store, uuid: uuidB).matchInfo.state, .unmatched)
    }

    func testFailedUnmatchDoesNotPublishWatch() throws {
        let (store, _, firstWorkout, _) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_080)
        let uuidA = UUID()
        let uuidB = UUID()
        let (resultA, _) = try seedConflictingResults(
            store,
            workoutID: importedID,
            startedAt: startedAt,
            firstUUID: uuidA,
            secondUUID: uuidB
        )
        store.confirmHealthMatch(resultA, scheduledWorkoutID: firstWorkout.id)
        store.toastMessage = nil
        let before = store.watchPublicationCountForTesting

        store.setForceSaveFailureAfterMutationForTesting(true)
        store.unmatchHealthResult(try result(store, uuid: uuidA))

        XCTAssertEqual(store.watchPublicationCountForTesting, before)
        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.state, .matched)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.status, .completed)
        XCTAssertEqual(try result(store, uuid: uuidB).healthKitUUID, uuidB)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.toastMessage)
    }

    func testUnmatchRetryPublishesWatchOnce() throws {
        let (store, _, firstWorkout, _) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_090)
        let uuidA = UUID()
        let uuidB = UUID()
        let (resultA, _) = try seedConflictingResults(
            store,
            workoutID: importedID,
            startedAt: startedAt,
            firstUUID: uuidA,
            secondUUID: uuidB
        )
        store.confirmHealthMatch(resultA, scheduledWorkoutID: firstWorkout.id)
        store.setForceSaveFailureAfterMutationForTesting(true)
        store.unmatchHealthResult(try result(store, uuid: uuidA))
        let beforeRetry = store.watchPublicationCountForTesting

        store.setForceSaveFailureAfterMutationForTesting(false)
        store.unmatchHealthResult(try result(store, uuid: uuidA))

        XCTAssertEqual(store.watchPublicationCountForTesting, beforeRetry + 1)
        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.state, .unmatched)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.status, .scheduled)
    }

    func testConfirmMatchPublishesWatchOnlyAfterSuccess() throws {
        let (store, _, firstWorkout, _) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_100)
        let uuidA = UUID()
        let uuidB = UUID()
        let (resultA, _) = try seedConflictingResults(
            store,
            workoutID: importedID,
            startedAt: startedAt,
            firstUUID: uuidA,
            secondUUID: uuidB
        )
        let beforeFailure = store.watchPublicationCountForTesting
        store.setForceSaveFailureForTesting(true)
        store.confirmHealthMatch(resultA, scheduledWorkoutID: firstWorkout.id)
        XCTAssertEqual(store.watchPublicationCountForTesting, beforeFailure)
        XCTAssertNil(store.toastMessage)

        store.setForceSaveFailureForTesting(false)
        store.confirmHealthMatch(try result(store, uuid: uuidA), scheduledWorkoutID: firstWorkout.id)
        XCTAssertEqual(store.watchPublicationCountForTesting, beforeFailure + 1)
        XCTAssertEqual(store.toastMessage, "RUN LINKED TO PLAN")
        XCTAssertEqual(try result(store, uuid: uuidB).matchInfo.state, .unmatched)
    }

    func testRejectAndKeepPersistFailureRestoreSelectedAndSkipWatch() throws {
        let (store, _, firstWorkout, secondWorkout) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_110)
        let uuidA = UUID()
        let uuidB = UUID()
        _ = try seedConflictingResults(
            store,
            workoutID: importedID,
            startedAt: startedAt,
            firstUUID: uuidA,
            secondUUID: uuidB
        )
        var resultA = try result(store, uuid: uuidA)
        var resultB = try result(store, uuid: uuidB)
        resultA.matchInfo = WorkoutMatchInfo(state: .suggested, suggestedWorkoutID: firstWorkout.id)
        resultB.matchInfo = WorkoutMatchInfo(state: .suggested, suggestedWorkoutID: secondWorkout.id)
        store.results = [resultA, resultB]
        store.save()
        store.toastMessage = nil
        let beforeReject = store.watchPublicationCountForTesting

        store.setForceSaveFailureAfterMutationForTesting(true)
        store.rejectHealthMatch(resultA, suggestedWorkoutID: firstWorkout.id)
        XCTAssertEqual(store.watchPublicationCountForTesting, beforeReject)
        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.state, .suggested)
        XCTAssertFalse(try result(store, uuid: uuidA).matchInfo.rejectedWorkoutIDs.contains(firstWorkout.id))
        XCTAssertEqual(try result(store, uuid: uuidB).matchInfo.state, .suggested)
        XCTAssertNil(store.toastMessage)

        store.keepHealthUnmatched(try result(store, uuid: uuidA))
        XCTAssertEqual(store.watchPublicationCountForTesting, beforeReject)
        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.state, .suggested)
        XCTAssertEqual(try result(store, uuid: uuidB).matchInfo.suggestedWorkoutID, secondWorkout.id)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.toastMessage)
    }

    func testSharedSuggestionConfirmClaimsWorkoutAndRejectsStaleConfirm() throws {
        let (store, _, firstWorkout, _) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_120)
        let uuidA = UUID()
        let uuidB = UUID()
        _ = try seedConflictingResults(store, workoutID: importedID, startedAt: startedAt, firstUUID: uuidA, secondUUID: uuidB)

        var resultA = try result(store, uuid: uuidA)
        var resultB = try result(store, uuid: uuidB)
        resultA.matchInfo = WorkoutMatchInfo(state: .suggested, suggestedWorkoutID: firstWorkout.id)
        resultB.matchInfo = WorkoutMatchInfo(state: .suggested, suggestedWorkoutID: firstWorkout.id)
        store.results = [resultA, resultB]
        store.save()
        store.toastMessage = nil

        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.suggestedWorkoutID, firstWorkout.id)
        XCTAssertEqual(try result(store, uuid: uuidB).matchInfo.suggestedWorkoutID, firstWorkout.id)
        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.state, .suggested)
        XCTAssertEqual(try result(store, uuid: uuidB).matchInfo.state, .suggested)

        let staleA = resultA
        store.confirmHealthMatch(resultA, scheduledWorkoutID: firstWorkout.id)

        let afterA = try result(store, uuid: uuidA)
        let afterB = try result(store, uuid: uuidB)
        XCTAssertEqual(afterA.matchInfo.state, .matched)
        XCTAssertEqual(afterA.matchInfo.scheduledWorkoutID, firstWorkout.id)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.status, .completed)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.result?.healthKitUUID, uuidA)
        XCTAssertNotEqual(afterB.matchInfo.suggestedWorkoutID, firstWorkout.id)
        XCTAssertNotEqual(afterB.matchInfo.state, .matched)
        XCTAssertNil(afterB.matchInfo.scheduledWorkoutID)
        XCTAssertEqual(WorkoutResultMerge.canonical(of: staleA, in: store.results).matchInfo.state, .matched)

        store.toastMessage = nil
        let beforeStale = store.watchPublicationCountForTesting
        let planAfterA = store.plan
        let resultsAfterA = store.results
        let celebrationAfterA = store.celebration
        let suggestionAfterA = store.pendingSuggestion

        store.confirmHealthMatch(afterB, scheduledWorkoutID: firstWorkout.id)

        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.state, .matched)
        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.scheduledWorkoutID, firstWorkout.id)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.result?.healthKitUUID, uuidA)
        XCTAssertNotEqual(try result(store, uuid: uuidB).matchInfo.state, .matched)
        XCTAssertNil(try result(store, uuid: uuidB).matchInfo.scheduledWorkoutID)
        XCTAssertEqual(store.watchPublicationCountForTesting, beforeStale)
        XCTAssertNil(store.toastMessage)
        XCTAssertEqual(store.plan, planAfterA)
        XCTAssertEqual(store.results, resultsAfterA)
        XCTAssertEqual(store.celebration, celebrationAfterA)
        XCTAssertEqual(store.pendingSuggestion, suggestionAfterA)
    }

    func testConfirmSaveFailureAfterRefreshingSiblingsRestoresAllState() throws {
        let (store, _, firstWorkout, _) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_130)
        let uuidA = UUID()
        let uuidB = UUID()
        _ = try seedConflictingResults(store, workoutID: importedID, startedAt: startedAt, firstUUID: uuidA, secondUUID: uuidB)

        var resultA = try result(store, uuid: uuidA)
        var resultB = try result(store, uuid: uuidB)
        resultA.matchInfo = WorkoutMatchInfo(state: .suggested, suggestedWorkoutID: firstWorkout.id)
        resultB.matchInfo = WorkoutMatchInfo(state: .suggested, suggestedWorkoutID: firstWorkout.id)
        store.results = [resultA, resultB]
        store.save()
        store.toastMessage = nil

        let previousResults = store.results
        let previousPlan = store.plan
        let previousProfile = store.profile
        let previousCelebration = store.celebration
        let previousSuggestion = store.pendingSuggestion
        let previousFreeze = store.freezeMileage
        let previousFreezeBaseline = store.freezeMileageBaselineMeters
        let previousToast = store.toastMessage
        let previousWatch = store.watchPublicationCountForTesting

        store.setForceSaveFailureAfterMutationForTesting(true)
        store.confirmHealthMatch(resultA, scheduledWorkoutID: firstWorkout.id)

        XCTAssertEqual(store.results, previousResults)
        XCTAssertEqual(store.plan, previousPlan)
        XCTAssertEqual(store.profile, previousProfile)
        XCTAssertEqual(store.celebration, previousCelebration)
        XCTAssertEqual(store.pendingSuggestion, previousSuggestion)
        XCTAssertEqual(store.freezeMileage, previousFreeze)
        XCTAssertEqual(store.freezeMileageBaselineMeters, previousFreezeBaseline)
        XCTAssertEqual(store.toastMessage, previousToast)
        XCTAssertEqual(store.watchPublicationCountForTesting, previousWatch)
        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.state, .suggested)
        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.suggestedWorkoutID, firstWorkout.id)
        XCTAssertEqual(try result(store, uuid: uuidB).matchInfo.state, .suggested)
        XCTAssertEqual(try result(store, uuid: uuidB).matchInfo.suggestedWorkoutID, firstWorkout.id)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.status, .scheduled)
        XCTAssertNil(store.plan?.workouts.first { $0.id == firstWorkout.id }?.result)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.toastMessage)
    }

    func testAlreadyMatchedResultCannotClaimSecondWorkout() throws {
        let (store, _, firstWorkout, secondWorkout) = try twoWorkoutStore()
        let importedID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_720_000_140)
        let uuidA = UUID()
        let uuidB = UUID()
        let (resultA, _) = try seedConflictingResults(
            store,
            workoutID: importedID,
            startedAt: startedAt,
            firstUUID: uuidA,
            secondUUID: uuidB
        )

        store.confirmHealthMatch(resultA, scheduledWorkoutID: firstWorkout.id)

        let matchedA = try result(store, uuid: uuidA)
        XCTAssertEqual(matchedA.matchInfo.state, .matched)
        XCTAssertEqual(matchedA.matchInfo.scheduledWorkoutID, firstWorkout.id)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.status, .completed)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.result?.healthKitUUID, uuidA)

        let watchAfterFirst = store.watchPublicationCountForTesting
        let toastAfterFirst = store.toastMessage
        let celebrationAfterFirst = store.celebration
        let suggestionAfterFirst = store.pendingSuggestion
        let freezeAfterFirst = store.freezeMileage
        let freezeBaselineAfterFirst = store.freezeMileageBaselineMeters
        let resultsAfterFirst = store.results
        let planAfterFirst = store.plan

        store.confirmHealthMatch(matchedA, scheduledWorkoutID: secondWorkout.id)

        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.state, .matched)
        XCTAssertEqual(try result(store, uuid: uuidA).matchInfo.scheduledWorkoutID, firstWorkout.id)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.status, .completed)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == firstWorkout.id }?.result?.healthKitUUID, uuidA)
        XCTAssertEqual(store.plan?.workouts.first { $0.id == secondWorkout.id }?.status, .scheduled)
        XCTAssertNil(store.plan?.workouts.first { $0.id == secondWorkout.id }?.result)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchAfterFirst)
        XCTAssertEqual(store.toastMessage, toastAfterFirst)
        XCTAssertEqual(store.celebration, celebrationAfterFirst)
        XCTAssertEqual(store.pendingSuggestion, suggestionAfterFirst)
        XCTAssertEqual(store.freezeMileage, freezeAfterFirst)
        XCTAssertEqual(store.freezeMileageBaselineMeters, freezeBaselineAfterFirst)
        XCTAssertEqual(store.results, resultsAfterFirst)
        XCTAssertEqual(store.plan, planAfterFirst)
        XCTAssertEqual(try result(store, uuid: uuidB).matchInfo.state, .unmatched)
    }
}
