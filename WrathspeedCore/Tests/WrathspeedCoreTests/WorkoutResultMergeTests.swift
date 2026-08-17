import Foundation
import Testing
@testable import WrathspeedCore

struct WorkoutResultMergeTests {
    private let workoutID = UUID()
    private let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let healthUUID = UUID()

    private func baseResult(
        healthState: HealthSyncState = .pending,
        healthKitUUID: UUID? = nil,
        distance: Double = 5_000,
        route: [RoutePoint]? = nil
    ) -> WorkoutResult {
        WorkoutResult(
            workoutID: workoutID,
            startedAt: startedAt,
            duration: 1_800,
            distanceMeters: distance,
            averagePaceSecPerKm: 360,
            location: .outdoor,
            healthKitUUID: healthKitUUID,
            route: route,
            source: .wrathspeedPhone,
            healthSync: HealthSyncMetadata(state: healthState, healthKitUUID: healthKitUUID)
        )
    }

    @Test func pendingFollowedBySyncedProducesOneResultWithMetadata() {
        let pending = baseResult(healthState: .pending)
        var synced = baseResult(
            healthState: .synced,
            healthKitUUID: healthUUID,
            route: [RoutePoint(latitude: 1, longitude: 2, timestamp: startedAt)]
        )
        synced.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: healthUUID)

        let first = WorkoutResultMerge.planRecord(existing: [], incoming: pending)
        #expect(first.outcome == .insert)
        let second = WorkoutResultMerge.planRecord(existing: [first.mergedResult], incoming: synced)
        #expect(second.outcome == .update)
        #expect(second.mergedResult.healthSync.state == .synced)
        #expect(second.mergedResult.healthKitUUID == healthUUID)
        #expect(second.mergedResult.route?.count == 1)
        #expect(second.mergedResult.workoutID == workoutID)
        #expect(second.mergedResult.startedAt == startedAt)
    }

    @Test func pendingFollowedByFailedProducesOneFailedResult() {
        let pending = baseResult(healthState: .pending)
        var failed = baseResult(healthState: .failed)
        failed.healthSync = HealthSyncMetadata(state: .failed, failureMessage: "offline", lastAttemptAt: startedAt)

        let first = WorkoutResultMerge.planRecord(existing: [], incoming: pending)
        let second = WorkoutResultMerge.planRecord(existing: [first.mergedResult], incoming: failed)
        #expect(second.outcome == .update)
        #expect(second.mergedResult.healthSync.state == .failed)
        #expect(second.mergedResult.healthSync.failureMessage == "offline")
    }

    @Test func failedFollowedBySyncedUpdatesSameResult() {
        var failed = baseResult(healthState: .failed)
        failed.healthSync = HealthSyncMetadata(state: .failed, failureMessage: "offline")
        var synced = baseResult(healthState: .synced, healthKitUUID: healthUUID)
        synced.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: healthUUID)

        let first = WorkoutResultMerge.planRecord(existing: [], incoming: failed)
        let second = WorkoutResultMerge.planRecord(existing: [first.mergedResult], incoming: synced)
        #expect(second.outcome == .update)
        #expect(second.mergedResult.healthSync.state == .synced)
        #expect(second.mergedResult.healthKitUUID == healthUUID)
    }

    @Test func syncedFollowedByPendingDoesNotDowngrade() {
        var synced = baseResult(healthState: .synced, healthKitUUID: healthUUID)
        synced.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: healthUUID)
        let pending = baseResult(healthState: .pending)

        let first = WorkoutResultMerge.planRecord(existing: [], incoming: synced)
        let second = WorkoutResultMerge.planRecord(existing: [first.mergedResult], incoming: pending)
        #expect(second.outcome == .update)
        #expect(second.mergedResult.healthSync.state == .synced)
    }

    @Test func sameHealthKitUUIDDoesNotDuplicate() {
        var first = baseResult(healthState: .synced, healthKitUUID: healthUUID)
        first.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: healthUUID)
        var second = baseResult(healthState: .synced, healthKitUUID: healthUUID)
        second.workoutID = UUID()
        second.startedAt = startedAt.addingTimeInterval(60)
        second.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: healthUUID)

        let plan = WorkoutResultMerge.planRecord(existing: [first], incoming: second)
        #expect(plan.outcome == .update)
        #expect(plan.mergedResult.workoutID == first.workoutID)
    }

    @Test func differentStartedAtRemainsSeparateWorkout() {
        let first = baseResult()
        var second = baseResult()
        second.startedAt = startedAt.addingTimeInterval(3_600)

        let plan = WorkoutResultMerge.planRecord(existing: [first], incoming: second)
        #expect(plan.outcome == .insert)
    }

    @Test func identityKeyPrefersHealthKitUUID() {
        var result = baseResult(healthKitUUID: healthUUID)
        result.healthSync = HealthSyncMetadata(state: .pending)
        #expect(WorkoutResultMerge.identityKey(for: result) == "hk:\(healthUUID.uuidString)")
        #expect(result.id == WorkoutResultMerge.identityKey(for: result))
    }

    @Test func conflictingHealthKitUUIDsHaveDistinctPresentationIDs() {
        let firstUUID = UUID()
        let secondUUID = UUID()
        var first = baseResult(healthState: .synced, healthKitUUID: firstUUID)
        first.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: firstUUID)
        var second = baseResult(healthState: .synced, healthKitUUID: secondUUID)
        second.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: secondUUID)

        #expect(first.id != second.id)
        #expect(first.id == "hk:\(firstUUID.uuidString)")
        #expect(second.id == "hk:\(secondUUID.uuidString)")
        #expect(Set([first, second].map(\.id)).count == 2)
    }

    @Test func conflictingHealthKitUUIDsHaveDistinctHistoryRowIdentities() {
        let firstUUID = UUID()
        let secondUUID = UUID()
        var first = baseResult(healthState: .synced, healthKitUUID: firstUUID)
        first.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: firstUUID)
        var second = baseResult(healthState: .synced, healthKitUUID: secondUUID)
        second.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: secondUUID)

        let results = [first, second]
        let firstRowID = WorkoutResultMerge.historyRowIdentity(for: first, in: results)
        let secondRowID = WorkoutResultMerge.historyRowIdentity(for: second, in: results)
        #expect(firstRowID != secondRowID)
        #expect(firstRowID == "hk:\(firstUUID.uuidString)")
        #expect(secondRowID == "hk:\(secondUUID.uuidString)")
    }

    @Test func canonicalResolutionUsesCurrentMatchState() {
        var suggested = baseResult(healthState: .synced, healthKitUUID: healthUUID)
        suggested.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: healthUUID)
        suggested.matchInfo = WorkoutMatchInfo(state: .suggested, suggestedWorkoutID: UUID())
        var matched = suggested
        matched.matchInfo = WorkoutMatchInfo(state: .matched, scheduledWorkoutID: UUID())
        let stale = suggested

        let current = WorkoutResultMerge.canonical(of: stale, in: [matched])
        #expect(current.matchInfo.state == .matched)
        #expect(current.matchInfo.scheduledWorkoutID == matched.matchInfo.scheduledWorkoutID)
        #expect(stale.matchInfo.state == .suggested)
    }

    @Test func canonicalResolutionKeepsConflictingHealthKitUUIDsDistinct() {
        let firstUUID = UUID()
        let secondUUID = UUID()
        var first = baseResult(healthState: .synced, healthKitUUID: firstUUID)
        first.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: firstUUID)
        first.matchInfo = WorkoutMatchInfo(state: .matched, scheduledWorkoutID: UUID())
        var second = baseResult(healthState: .synced, healthKitUUID: secondUUID)
        second.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: secondUUID)
        second.matchInfo = WorkoutMatchInfo(state: .suggested, suggestedWorkoutID: UUID())

        let results = [first, second]
        #expect(WorkoutResultMerge.canonical(of: first, in: results).healthKitUUID == firstUUID)
        #expect(WorkoutResultMerge.canonical(of: second, in: results).healthKitUUID == secondUUID)
        #expect(WorkoutResultMerge.canonical(of: first, in: results).matchInfo.state == .matched)
        #expect(WorkoutResultMerge.canonical(of: second, in: results).matchInfo.state == .suggested)
    }

    @Test func pendingThenSyncedSharesOnePresentationIdentity() {
        let pending = baseResult(healthState: .pending)
        var synced = baseResult(healthState: .synced, healthKitUUID: healthUUID)
        synced.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: healthUUID)

        var results: [WorkoutResult] = []
        WorkoutResultMerge.ingest(pending, into: &results)
        let identityBefore = WorkoutResultMerge.historyRowIdentity(for: results[0], in: results)
        let domainIDBefore = results[0].id

        WorkoutResultMerge.ingest(synced, into: &results)
        let identityAfter = WorkoutResultMerge.historyRowIdentity(for: results[0], in: results)

        #expect(results.count == 1)
        #expect(identityBefore == identityAfter)
        #expect(identityBefore == "local:\(workoutID.uuidString):\(startedAt.timeIntervalSince1970)")
        #expect(domainIDBefore == "local:\(workoutID.uuidString):\(startedAt.timeIntervalSince1970)")
        #expect(results[0].id == "hk:\(healthUUID.uuidString)")
        #expect(results[0].id == WorkoutResultMerge.identityKey(for: results[0]))
        #expect(identityAfter != results[0].id)
    }

    @Test func conflictingHealthKitUUIDsDoNotMerge() {
        let firstUUID = UUID()
        let secondUUID = UUID()
        var first = baseResult(healthState: .synced, healthKitUUID: firstUUID)
        first.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: firstUUID)
        var second = baseResult(healthState: .synced, healthKitUUID: secondUUID)
        second.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: secondUUID)

        #expect(!WorkoutResultMerge.matches(first, second))
        let plan = WorkoutResultMerge.planRecord(existing: [first], incoming: second)
        #expect(plan.outcome == .insert)
        #expect(plan.mergedResult.healthKitUUID == secondUUID)
        #expect(first.healthKitUUID == firstUUID)
    }

    @Test func finishingStateIsRecoverable() {
        #expect(ActiveSessionState.finishing.isRecoverableUnfinishedSession)
        #expect(!ActiveSessionState.saved.isRecoverableUnfinishedSession)
        #expect(!ActiveSessionState.healthSyncPending.isRecoverableUnfinishedSession)
    }

    @Test func canonicalizeMergesStalePlanPendingIntoSyncedCanonical() {
        var synced = baseResult(healthState: .synced, healthKitUUID: healthUUID)
        synced.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: healthUUID)
        synced.route = [RoutePoint(latitude: 1, longitude: 2, timestamp: startedAt)]
        synced.splits = [WorkoutSplit(index: 1, distanceMeters: 1_000, duration: 360, paceSecPerKm: 360)]
        let pending = baseResult(healthState: .pending)
        let workout = ScheduledWorkout(
            blueprint: WorkoutBlueprint(
                date: startedAt,
                kind: .easy,
                title: "Easy",
                steps: [],
                plannedDistanceMeters: 5_000,
                usesPaceTargets: true
            ),
            status: .completed,
            result: pending
        )
        let plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [workout]
        )

        let canonical = WorkoutResultMerge.canonicalize(results: [synced], plan: plan)
        #expect(canonical.results.count == 1)
        #expect(canonical.results[0].healthSync.state == .synced)
        #expect(canonical.results[0].healthKitUUID == healthUUID)
        #expect(canonical.results[0].route?.count == 1)
        #expect(canonical.results[0].splits?.count == 1)
        #expect(canonical.results[0].source == .wrathspeedPhone)
        #expect(canonical.plan?.workouts.first?.result?.healthSync.state == .synced)
        #expect(canonical.plan?.workouts.first?.result?.healthKitUUID == healthUUID)
    }

    @Test func canonicalizeKeepsConflictingHealthKitUUIDsDistinct() {
        let firstUUID = UUID()
        let secondUUID = UUID()
        var first = baseResult(healthState: .synced, healthKitUUID: firstUUID)
        first.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: firstUUID)
        var second = baseResult(healthState: .synced, healthKitUUID: secondUUID)
        second.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: secondUUID)

        let canonical = WorkoutResultMerge.canonicalize(results: [first, second], plan: nil)
        #expect(canonical.results.count == 2)
        let uuids = Set(canonical.results.compactMap(\.healthKitUUID))
        #expect(uuids == [firstUUID, secondUUID])
    }

    @Test func ingestUsesPlanRecordMerge() {
        var results: [WorkoutResult] = []
        WorkoutResultMerge.ingest(baseResult(healthState: .pending), into: &results)
        var synced = baseResult(healthState: .synced, healthKitUUID: healthUUID)
        synced.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: healthUUID)
        WorkoutResultMerge.ingest(synced, into: &results)
        #expect(results.count == 1)
        #expect(results[0].healthSync.state == .synced)
        #expect(results[0].healthKitUUID == healthUUID)
    }

    @Test func guidedResultsMatchByPrimaryID() {
        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = StrengthSessionResult(
            id: UUID(),
            sessionID: sessionID,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            setLogs: []
        )
        var corrected = original
        corrected.startedAt = startedAt.addingTimeInterval(30)
        #expect(StrengthSessionResult.matches(original, corrected))

        let mobility = MobilitySessionResult(
            id: original.id,
            sessionID: sessionID,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            completedMovementIDs: []
        )
        var mobilityCorrected = mobility
        mobilityCorrected.startedAt = startedAt.addingTimeInterval(30)
        #expect(MobilitySessionResult.matches(mobility, mobilityCorrected))
    }

    @Test func startupTerminalClearRequiresMatchingAttemptIdentity() {
        let workoutID = UUID()
        let attemptA = UUID().uuidString
        let attemptB = UUID().uuidString
        let stored = ActiveSessionSnapshot(
            workoutID: workoutID,
            blueprintData: Data(),
            source: .wrathspeedPhone,
            state: .countdown,
            startupAttemptID: attemptB
        )
        let staleTerminal = ActiveSessionSnapshot(
            workoutID: workoutID,
            blueprintData: Data(),
            source: .wrathspeedPhone,
            state: .saved,
            startupAttemptID: attemptA
        )
        let matchingTerminal = ActiveSessionSnapshot(
            workoutID: workoutID,
            blueprintData: Data(),
            source: .wrathspeedPhone,
            state: .saved,
            startupAttemptID: attemptB
        )
        #expect(!stored.matchesStartupTerminalClear(from: staleTerminal))
        #expect(stored.matchesStartupTerminalClear(from: matchingTerminal))
    }

    @Test func equalAttemptIDsMatch() {
        let workoutID = UUID()
        let attemptID = UUID().uuidString
        let stored = ActiveSessionSnapshot(
            workoutID: workoutID,
            blueprintData: Data(),
            source: .wrathspeedPhone,
            state: .countdown,
            startupAttemptID: attemptID
        )
        let terminal = ActiveSessionSnapshot(
            workoutID: workoutID,
            blueprintData: Data(),
            source: .wrathspeedPhone,
            state: .saved,
            startupAttemptID: attemptID
        )
        #expect(stored.matchesStartupTerminalClear(from: terminal))
    }

    @Test func legacySnapshotsWithoutAttemptFieldStillMatchEachOther() {
        let workoutID = UUID()
        let stored = ActiveSessionSnapshot(
            workoutID: workoutID,
            blueprintData: Data(),
            source: .wrathspeedPhone,
            state: .preparing
        )
        let terminal = ActiveSessionSnapshot(
            workoutID: workoutID,
            blueprintData: Data(),
            source: .wrathspeedPhone,
            state: .saved
        )
        #expect(stored.matchesStartupTerminalClear(from: terminal))
    }

    @Test func legacyAmbiguityDoesNotClearKnownAttempt() throws {
        let workoutID = UUID()
        let attemptB = UUID().uuidString
        let stored = ActiveSessionSnapshot(
            workoutID: workoutID,
            blueprintData: Data(),
            source: .wrathspeedPhone,
            state: .countdown,
            startupAttemptID: attemptB
        )
        let legacyTerminal = ActiveSessionSnapshot(
            workoutID: workoutID,
            blueprintData: Data(),
            source: .wrathspeedPhone,
            state: .saved
        )
        #expect(!stored.matchesStartupTerminalClear(from: legacyTerminal))

        let legacyJSON = """
        {"workoutID":"\(workoutID.uuidString)","blueprintData":"","source":"wrathspeedPhone","state":"countdown"}
        """
        let decoded = try JSONDecoder().decode(ActiveSessionSnapshot.self, from: Data(legacyJSON.utf8))
        #expect(decoded.startupAttemptID == nil)
    }

    @Test func legacyStartupAttemptMsDecodesToNamespacedID() throws {
        let workoutID = UUID()
        let attemptMs: Int64 = 1_700_002_000_000
        let legacyJSON = """
        {"workoutID":"\(workoutID.uuidString)","blueprintData":"","source":"wrathspeedPhone","state":"countdown","startupAttemptMs":\(attemptMs)}
        """
        let decoded = try JSONDecoder().decode(ActiveSessionSnapshot.self, from: Data(legacyJSON.utf8))
        #expect(decoded.startupAttemptID == "legacy-ms:\(attemptMs)")
    }

    @Test func nilNonNilAttemptAmbiguityDoesNotClear() {
        let workoutID = UUID()
        let stored = ActiveSessionSnapshot(
            workoutID: workoutID,
            blueprintData: Data(),
            source: .wrathspeedPhone,
            state: .countdown,
            startupAttemptID: UUID().uuidString
        )
        let legacyTerminal = ActiveSessionSnapshot(
            workoutID: workoutID,
            blueprintData: Data(),
            source: .wrathspeedPhone,
            state: .saved
        )
        #expect(!stored.matchesStartupTerminalClear(from: legacyTerminal))
        #expect(!legacyTerminal.matchesStartupTerminalClear(from: stored))
    }

    @Test func independentlyGeneratedAttemptIDsAreDistinct() {
        let first = UUID().uuidString
        let second = UUID().uuidString
        #expect(first != second)
    }
}
