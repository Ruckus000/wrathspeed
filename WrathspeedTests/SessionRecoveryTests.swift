import HealthKit
import SwiftData
import XCTest
@testable import Wrathspeed
import WrathspeedCore

private enum StartupSentinelError: Error, Equatable {
    case prePending
    case beginCollection
}

@MainActor
final class SessionRecoveryTests: XCTestCase {
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
                MobilitySessionResultEntity.self,
                ActiveSessionSnapshotEntity.self,
            ]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)
        return (store, context)
    }

    private func makeBlueprint() -> WorkoutBlueprint {
        WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
    }

    private func makeConfiguration() -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        return configuration
    }

    func testPartialRecoveryCreatesResultWithoutCompletingPlannedWorkout() throws {
        let (store, _) = try makeStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let planWorkout = ScheduledWorkout(blueprint: blueprint)
        store.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK, raceDate: Date().addingTimeInterval(86_400 * 30)),
            profile: RunnerProfile(
                ability: .intermediate,
                daysPerWeek: 4,
                longRunWeekday: .sunday,
                unit: .kilometers,
                vdot: 40,
                availableWeekdays: [.tuesday, .thursday, .saturday, .sunday]
            ),
            workouts: [planWorkout]
        )
        let snapshot = ActiveSessionSnapshot(
            workoutID: blueprint.id,
            blueprintData: try JSONEncoder().encode(blueprint),
            source: .instant,
            state: .recording,
            startedAt: Date().addingTimeInterval(-1_200),
            elapsedSeconds: 1_200,
            distanceMeters: 2_500
        )
        store.savePartialRecovery(from: snapshot)
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.source, .instant)
        XCTAssertEqual(store.plan?.workouts.first?.status, .scheduled)
        XCTAssertNil(store.pendingRecoverySnapshot)
        XCTAssertNil(store.errorMessage)
    }

    func testDiscardRecoveryClearsPendingSnapshot() {
        let store = AppStore()
        store.pendingRecoverySnapshot = ActiveSessionSnapshot(
            workoutID: UUID(),
            blueprintData: Data(),
            source: .wrathspeedPhone,
            state: .paused
        )
        store.discardRecovery()
        XCTAssertNil(store.pendingRecoverySnapshot)
    }

    func testMatchingCancellationClearsCountdownRecovery() throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let startupID = store.session.testing_beginOwnedStartup()
        store.session.testing_simulateCountdownOwnership(startupID: startupID, blueprint: blueprint)
        XCTAssertEqual(store.session.sessionState, .countdown)
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .countdown)

        store.session.cancelPendingLaunch()
        XCTAssertEqual(store.session.sessionState, .preparing)
        XCTAssertNil(store.session.blueprint)
        XCTAssertNil(try ActiveSessionStore.load(from: context))
        XCTAssertNil(store.pendingRecoverySnapshot)
    }

    func testCurrentStartupFailureClearsCountdownAndRethrows() async throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let startupID = store.session.testing_beginOwnedStartup()
        store.session.testing_prepareForPostCountdownStartup(startupID: startupID, blueprint: blueprint)

        store.session.testing_setSkipCountdownSleep(true)
        store.session.testing_setForcePrePendingStartupError(StartupSentinelError.prePending)
        do {
            try await store.session.testing_runPostCountdownStartup(
                configuration: makeConfiguration(),
                startupID: startupID
            )
            XCTFail("expected startup failure")
        } catch let error as StartupSentinelError {
            XCTAssertEqual(error, .prePending)
        }

        XCTAssertEqual(store.session.sessionState, .preparing)
        XCTAssertNil(try ActiveSessionStore.load(from: context))
        XCTAssertNil(store.pendingRecoverySnapshot)

        let staleID = startupID
        let newID = store.session.testing_beginOwnedStartup()
        store.session.testing_simulateCountdownOwnership(startupID: newID, blueprint: blueprint)
        store.session.testing_setForcePrePendingStartupError(StartupSentinelError.prePending)
        try await store.session.testing_runPostCountdownStartup(
            configuration: makeConfiguration(),
            startupID: staleID
        )
        XCTAssertEqual(store.session.sessionState, .countdown)
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .countdown)
    }

    func testCancellationDuringOwnedCountdownClearsRecovery() async throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let startupID = store.session.testing_beginOwnedStartup()
        store.session.testing_prepareForPostCountdownStartup(startupID: startupID, blueprint: blueprint)

        store.session.testing_setSkipCountdownSleep(false)
        let task = Task { @MainActor in
            try await store.session.testing_runPostCountdownStartup(
                configuration: makeConfiguration(),
                startupID: startupID
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
        }

        XCTAssertEqual(store.session.sessionState, .preparing)
        XCTAssertNil(store.session.blueprint)
        XCTAssertNil(try ActiveSessionStore.load(from: context))
        XCTAssertNil(store.pendingRecoverySnapshot)
    }

    func testOwnedThrowBeforePendingPairClearsRecoveryAndRethrows() async throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let startupID = store.session.testing_beginOwnedStartup()
        store.session.testing_prepareForPostCountdownStartup(startupID: startupID, blueprint: blueprint)
        store.session.testing_setSkipCountdownSleep(true)
        store.session.testing_setForcePrePendingStartupError(StartupSentinelError.prePending)

        do {
            try await store.session.testing_runPostCountdownStartup(
                configuration: makeConfiguration(),
                startupID: startupID
            )
            XCTFail("expected sentinel error")
        } catch let error as StartupSentinelError {
            XCTAssertEqual(error, .prePending)
        }

        XCTAssertEqual(store.session.sessionState, .preparing)
        XCTAssertNil(try ActiveSessionStore.load(from: context))
    }

    func testCurrentPendingStartFailureCleansUpAndRethrowsOriginalError() async throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let startupID = store.session.testing_beginOwnedStartup()
        store.session.testing_prepareForPostCountdownStartup(startupID: startupID, blueprint: blueprint)
        store.session.testing_setSkipCountdownSleep(true)
        store.session.testing_setForceBeginCollectionError(StartupSentinelError.beginCollection)

        do {
            try await store.session.testing_runPostCountdownStartup(
                configuration: makeConfiguration(),
                startupID: startupID
            )
            XCTFail("expected beginCollection failure")
        } catch let error as StartupSentinelError {
            XCTAssertEqual(error, .beginCollection)
        }

        XCTAssertEqual(store.session.sessionState, .preparing)
        XCTAssertNil(try ActiveSessionStore.load(from: context))
        XCTAssertFalse(store.session.testing_hasPendingStartup)
    }

    func testCancellationDuringBeginCollectionClearsRecoveryAndPropagates() async throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let startupID = store.session.testing_beginOwnedStartup()
        store.session.testing_prepareForPostCountdownStartup(startupID: startupID, blueprint: blueprint)
        store.session.testing_setSkipCountdownSleep(true)
        store.session.testing_setForceBeginCollectionError(CancellationError())

        do {
            try await store.session.testing_runPostCountdownStartup(
                configuration: makeConfiguration(),
                startupID: startupID
            )
            XCTFail("expected cancellation")
        } catch is CancellationError {
        }

        XCTAssertEqual(store.session.sessionState, .preparing)
        XCTAssertNil(try ActiveSessionStore.load(from: context))
        XCTAssertFalse(store.session.testing_hasPendingStartup)
    }

    func testSupersededBeginCollectionFailureIsSilentAndPreservesNewerAttempt() async throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let staleID = store.session.testing_beginOwnedStartup()
        store.session.testing_prepareForPostCountdownStartup(startupID: staleID, blueprint: blueprint)
        var preservedAttemptID: String?
        store.session.testing_onPendingStartupCreated = {
            let newID = store.session.testing_beginOwnedStartup()
            store.session.testing_simulateCountdownOwnership(startupID: newID, blueprint: blueprint)
            preservedAttemptID = try? ActiveSessionStore.load(from: context)?.startupAttemptID
        }
        store.session.testing_setSkipCountdownSleep(true)
        store.session.testing_setForceBeginCollectionError(StartupSentinelError.beginCollection)

        try await store.session.testing_runPostCountdownStartup(
            configuration: makeConfiguration(),
            startupID: staleID
        )

        XCTAssertEqual(store.session.sessionState, .countdown)
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .countdown)
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.startupAttemptID, preservedAttemptID)
        store.session.testing_onPendingStartupCreated = nil
    }

    func testMatchingPendingPairDiscardedAtMostOnce() async throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let startupID = store.session.testing_beginOwnedStartup()
        store.session.testing_prepareForPostCountdownStartup(startupID: startupID, blueprint: blueprint)
        store.session.testing_setSkipCountdownSleep(true)
        store.session.testing_setForceBeginCollectionError(StartupSentinelError.beginCollection)

        try? await store.session.testing_runPostCountdownStartup(
            configuration: makeConfiguration(),
            startupID: startupID
        )
        XCTAssertFalse(store.session.testing_hasPendingStartup)
        XCTAssertEqual(store.session.testing_pendingStartupDiscardCount, 1)

        store.session.cancelPendingLaunch()
        XCTAssertEqual(store.session.testing_pendingStartupDiscardCount, 1)
        XCTAssertEqual(store.session.sessionState, .preparing)
        XCTAssertNil(try ActiveSessionStore.load(from: context))
    }

    func testSupersededStartupThrowIsSilentAndPreservesNewerCountdown() async throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let staleID = store.session.testing_beginOwnedStartup()
        store.session.testing_simulateCountdownOwnership(startupID: staleID, blueprint: blueprint)

        let newID = store.session.testing_beginOwnedStartup()
        store.session.testing_simulateCountdownOwnership(startupID: newID, blueprint: blueprint)
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .countdown)

        store.session.testing_setSkipCountdownSleep(true)
        store.session.testing_setForcePrePendingStartupError(StartupSentinelError.prePending)
        try await store.session.testing_runPostCountdownStartup(
            configuration: makeConfiguration(),
            startupID: staleID
        )

        XCTAssertEqual(store.session.sessionState, .countdown)
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .countdown)
    }

    func testRepeatedStartupCleanupIsNoOp() async throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let startupID = store.session.testing_beginOwnedStartup()
        store.session.testing_prepareForPostCountdownStartup(startupID: startupID, blueprint: blueprint)
        store.session.testing_setSkipCountdownSleep(true)
        store.session.testing_setForcePrePendingStartupError(StartupSentinelError.prePending)

        try? await store.session.testing_runPostCountdownStartup(
            configuration: makeConfiguration(),
            startupID: startupID
        )
        XCTAssertEqual(store.session.sessionState, .preparing)
        XCTAssertNil(try ActiveSessionStore.load(from: context))

        store.session.cancelPendingLaunch()
        store.session.cancelPendingLaunch()
        XCTAssertEqual(store.session.sessionState, .preparing)
        XCTAssertNil(try ActiveSessionStore.load(from: context))
    }

    func testMatchingTerminalSavedClearsCountdownRecovery() throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let attemptID = UUID().uuidString
        try ActiveSessionStore.save(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .countdown,
                startupAttemptID: attemptID
            ),
            to: context
        )
        store.session.onSnapshot?(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .saved,
                startupAttemptID: attemptID
            )
        )
        XCTAssertNil(try ActiveSessionStore.load(from: context))
        XCTAssertNil(store.pendingRecoverySnapshot)
    }

    func testStaleTerminalDoesNotClearNewerAttemptSameWorkout() throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let attemptB = UUID().uuidString
        let attemptA = UUID().uuidString
        try ActiveSessionStore.save(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .countdown,
                startupAttemptID: attemptB
            ),
            to: context
        )
        store.session.onSnapshot?(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .saved,
                startupAttemptID: attemptA
            )
        )
        let loaded = try ActiveSessionStore.load(from: context)
        XCTAssertEqual(loaded?.state, .countdown)
        XCTAssertEqual(loaded?.startupAttemptID, attemptB)
    }

    func testTerminalSavedClearsMatchingStartupRecoveryOnly() throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let otherBlueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Other",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let attemptID = UUID().uuidString
        try ActiveSessionStore.save(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .countdown,
                startupAttemptID: attemptID
            ),
            to: context
        )
        store.session.onSnapshot?(
            ActiveSessionSnapshot(
                workoutID: otherBlueprint.id,
                blueprintData: try JSONEncoder().encode(otherBlueprint),
                source: .wrathspeedPhone,
                state: .saved,
                startupAttemptID: attemptID
            )
        )
        let loaded = try ActiveSessionStore.load(from: context)
        XCTAssertEqual(loaded?.workoutID, blueprint.id)
        XCTAssertEqual(loaded?.state, .countdown)
    }

    func testDifferentSourceDoesNotClearStartupRecovery() throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let attemptID = UUID().uuidString
        try ActiveSessionStore.save(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .countdown,
                startupAttemptID: attemptID
            ),
            to: context
        )
        store.session.onSnapshot?(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedWatch,
                state: .saved,
                startupAttemptID: attemptID
            )
        )
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .countdown)
    }

    func testTerminalSavedDoesNotClearRecordingPausedOrFinishing() throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let attemptID = UUID().uuidString
        let startedAt = Date(timeIntervalSince1970: 1_700_001_000)
        for state in [ActiveSessionState.recording, .paused, .finishing] {
            try ActiveSessionStore.clear(from: context)
            try ActiveSessionStore.save(
                ActiveSessionSnapshot(
                    workoutID: blueprint.id,
                    blueprintData: try JSONEncoder().encode(blueprint),
                    source: .wrathspeedPhone,
                    state: state,
                    startedAt: startedAt,
                    startupAttemptID: attemptID
                ),
                to: context
            )
            store.session.onSnapshot?(
                ActiveSessionSnapshot(
                    workoutID: blueprint.id,
                    blueprintData: try JSONEncoder().encode(blueprint),
                    source: .wrathspeedPhone,
                    state: .saved,
                    startedAt: startedAt,
                    startupAttemptID: attemptID
                )
            )
            XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, state)
        }
    }

    func testInMemoryFinishingDoesNotBlockPersistedCountdownClear() throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let attemptID = UUID().uuidString
        let startedAt = Date(timeIntervalSince1970: 1_700_001_800)
        store.pendingRecoverySnapshot = ActiveSessionSnapshot(
            workoutID: blueprint.id,
            blueprintData: try JSONEncoder().encode(blueprint),
            source: .wrathspeedPhone,
            state: .finishing,
            startedAt: startedAt
        )
        try ActiveSessionStore.save(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .countdown,
                startupAttemptID: attemptID
            ),
            to: context
        )
        store.session.onSnapshot?(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .saved,
                startupAttemptID: attemptID
            )
        )
        XCTAssertEqual(store.pendingRecoverySnapshot?.state, .finishing)
        XCTAssertNil(try ActiveSessionStore.load(from: context))
    }

    func testCountdownAndTerminalClearCarrySameAttemptID() throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let startupID = store.session.testing_beginOwnedStartup()
        var terminalSnapshot: ActiveSessionSnapshot?
        let originalOnSnapshot = store.session.onSnapshot
        store.session.onSnapshot = { snapshot in
            if snapshot.state == .saved {
                terminalSnapshot = snapshot
            }
            originalOnSnapshot?(snapshot)
        }
        store.session.testing_simulateCountdownOwnership(startupID: startupID, blueprint: blueprint)
        let countdownAttemptID = try XCTUnwrap(try ActiveSessionStore.load(from: context)?.startupAttemptID)

        store.session.testing_publishTerminalStartupClear()
        XCTAssertEqual(terminalSnapshot?.startupAttemptID, countdownAttemptID)
    }

    func testRecordingSnapshotOmitsStartupAttemptID() throws {
        let store = AppStore()
        let blueprint = makeBlueprint()
        store.session.testing_configureSnapshot(blueprint: blueprint, source: .wrathspeedPhone, state: .recording)
        var captured: ActiveSessionSnapshot?
        store.session.onSnapshot = { captured = $0 }
        store.session.testing_publishSnapshot()
        XCTAssertNil(captured?.startupAttemptID)
    }

    func testSuccessfulResultPersistenceClearsFinishingRecovery() throws {
        let (store, context) = try makeStore()
        let blueprint = makeBlueprint()
        let startedAt = Date(timeIntervalSince1970: 1_700_001_700)
        try ActiveSessionStore.save(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .finishing,
                startedAt: startedAt
            ),
            to: context
        )
        try store.record(
            WorkoutResult(
                workoutID: blueprint.id,
                startedAt: startedAt,
                duration: 1_800,
                distanceMeters: 5_000,
                averagePaceSecPerKm: 360,
                location: .outdoor,
                source: .wrathspeedPhone,
                healthSync: HealthSyncMetadata(state: .pending)
            )
        )
        XCTAssertNil(try ActiveSessionStore.load(from: context))
        XCTAssertNil(store.pendingRecoverySnapshot)
    }

    func testTerminalSavedDoesNotClearStoredFinishingWithoutPersistedResult() throws {
        let (store, context) = try makeStore()
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let startedAt = Date(timeIntervalSince1970: 1_700_001_100)
        try ActiveSessionStore.save(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .finishing,
                startedAt: startedAt
            ),
            to: context
        )
        store.session.onSnapshot?(
            ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: try JSONEncoder().encode(blueprint),
                source: .wrathspeedPhone,
                state: .saved,
                startedAt: startedAt
            )
        )
        XCTAssertEqual(try ActiveSessionStore.load(from: context)?.state, .finishing)
        XCTAssertNil(store.pendingRecoverySnapshot)
    }
}
