import CoreLocation
import Foundation
import HealthKit
import SwiftData
import XCTest
@testable import Wrathspeed
@testable import WrathspeedCore

final class CoachingMVPHardeningTests: XCTestCase {
    func testCapabilitiesDeclareHealthKitAndBackgroundLocationCopy() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for relativePath in ["Wrathspeed/Wrathspeed.entitlements", "WrathspeedWatch/WrathspeedWatch.entitlements"] {
            let data = try Data(contentsOf: root.appending(path: relativePath))
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertEqual(plist["com.apple.developer.healthkit"] as? Bool, true)
        }
        let project = try String(contentsOf: root.appending(path: "project.yml"), encoding: .utf8)
        XCTAssertTrue(project.contains("INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription"))
    }

    func testRoutePolicyUsesNoLocationForTreadmillAndEscalatesOutdoorAuthorization() {
        XCTAssertEqual(
            RouteLocationPolicy.action(
                authorization: .authorizedAlways,
                isOutdoorWorkout: false,
                isRecording: true,
                requestedAlwaysAuthorization: false
            ),
            .stop
        )
        XCTAssertEqual(
            RouteLocationPolicy.action(
                authorization: .notDetermined,
                isOutdoorWorkout: true,
                isRecording: true,
                requestedAlwaysAuthorization: false
            ),
            .requestWhenInUse
        )
        XCTAssertEqual(
            RouteLocationPolicy.action(
                authorization: .authorizedWhenInUse,
                isOutdoorWorkout: true,
                isRecording: true,
                requestedAlwaysAuthorization: false
            ),
            .requestAlways
        )
        XCTAssertEqual(
            RouteLocationPolicy.action(
                authorization: .authorizedAlways,
                isOutdoorWorkout: true,
                isRecording: true,
                requestedAlwaysAuthorization: true
            ),
            .start(allowsBackground: true)
        )
        XCTAssertEqual(
            RouteLocationPolicy.action(
                authorization: .authorizedAlways,
                isOutdoorWorkout: true,
                isRecording: false,
                requestedAlwaysAuthorization: true
            ),
            .stop
        )
    }

    func testWatchStartResolverHandlesEitherArrivalOrderAndDuplicates() {
        let request = makeStartRequest()

        var blueprintFirst = WatchStartResolver()
        XCTAssertNil(blueprintFirst.receive(request))
        XCTAssertEqual(blueprintFirst.receiveLaunchRequest()?.id, request.id)
        XCTAssertNil(blueprintFirst.receive(request))
        XCTAssertNil(blueprintFirst.receiveLaunchRequest())

        var launchFirst = WatchStartResolver()
        XCTAssertNil(launchFirst.receiveLaunchRequest())
        XCTAssertEqual(launchFirst.receive(request)?.id, request.id)

        var missingBlueprint = WatchStartResolver()
        XCTAssertNil(missingBlueprint.receiveLaunchRequest())
        XCTAssertNil(missingBlueprint.receiveLaunchRequest())
    }

    func testWatchWorkoutContextUsesWatchResultSource() {
        let request = makeStartRequest()
        let context = WatchWorkoutContext.make(from: request, fallbackUnit: .kilometers)
        XCTAssertEqual(context.resultSource, .wrathspeedWatch)
        XCTAssertEqual(context.unit, .kilometers)
        XCTAssertEqual(context.blueprint.id, request.blueprint.id)
        XCTAssertNotNil(context.zones)
    }

    func testWatchWorkoutContextDoesNotUsePhoneSource() {
        let request = makeStartRequest()
        let context = WatchWorkoutContext.make(from: request, fallbackUnit: .miles)
        XCTAssertNotEqual(context.resultSource, .wrathspeedPhone)
        XCTAssertEqual(context.resultSource, .wrathspeedWatch)
    }

    @MainActor
    func testWatchStoreAppliesWatchContextBeforeStartup() {
        let store = WatchStore()
        let request = makeStartRequest()
        store.beginWorkout(request)
        XCTAssertEqual(store.session.resultSource, .wrathspeedWatch)
        XCTAssertEqual(store.session.splitUnit, .kilometers)
        XCTAssertFalse(store.canPauseOrLap)
    }

    @MainActor
    func testCancelStartupIfPendingWhileStarting() {
        let store = WatchStore()
        store.beginWorkout(makeStartRequest())
        XCTAssertTrue(store.isStartupPending)
        store.cancelStartupIfPending()
        XCTAssertFalse(store.isStartupPending)
        XCTAssertFalse(store.session.isRunning)
    }

    @MainActor
    func testStartDuringFinishingDoesNotRecord() async throws {
        let controller = WorkoutSessionController(routeRecorder: NoopRouteRecorder())
        let blueprint = makeStartRequest().blueprint
        controller.testing_configureSnapshot(blueprint: blueprint, source: .wrathspeedPhone, state: .finishing)
        try await controller.start(blueprint: blueprint, zones: nil)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.sessionState, .finishing)
        XCTAssertNotEqual(controller.launchState, .recording)
    }

    @MainActor
    func testWatchStoreDoesNotStartOrMarkRecordingWhileFinishing() {
        let store = WatchStore()
        let request = makeStartRequest()
        store.session.testing_configureSnapshot(
            blueprint: request.blueprint,
            source: .wrathspeedWatch,
            state: .finishing
        )
        store.beginWorkout(request)
        XCTAssertFalse(store.isStartupPending)
        XCTAssertFalse(store.canPauseOrLap)
        XCTAssertFalse(store.session.isRunning)
        XCTAssertEqual(store.session.sessionState, .finishing)
        XCTAssertNotEqual(store.session.launchState, .recording)
    }

    @MainActor
    func testMirroredAttachmentRejectedWhileFinishingOrRecording() {
        let controller = WorkoutSessionController(routeRecorder: NoopRouteRecorder())
        let blueprint = makeStartRequest().blueprint
        controller.testing_configureSnapshot(blueprint: blueprint, source: .wrathspeedPhone, state: .finishing)
        XCTAssertFalse(controller.canAcceptMirroredSession)

        controller.testing_configureSnapshot(blueprint: blueprint, source: .wrathspeedPhone, state: .recording)
        XCTAssertFalse(controller.canAcceptMirroredSession)

        controller.testing_configureSnapshot(blueprint: blueprint, source: .wrathspeedPhone, state: .countdown)
        XCTAssertFalse(controller.canAcceptMirroredSession)

        controller.testing_configureMirroredAdmissionContext(
            sessionState: .preparing,
            activeStartupID: nil
        )
        XCTAssertTrue(controller.canAcceptMirroredSession)
    }

    @MainActor
    func testMirroredAdmissionTable() {
        let controller = WorkoutSessionController(routeRecorder: NoopRouteRecorder())
        let blueprint = makeStartRequest().blueprint
        controller.testing_configureSnapshot(blueprint: blueprint, source: .wrathspeedPhone)

        struct Case {
            let label: String
            let launchState: WorkoutSessionController.LaunchState
            let sessionState: ActiveSessionState
            let activeStartupID: UInt?
            let pendingStartup: Bool
            let hasCurrentSession: Bool
            let isRunning: Bool
            let expected: Bool
        }

        let startupID: UInt = 7
        let cases: [Case] = [
            Case(label: "idle", launchState: .idle, sessionState: .preparing, activeStartupID: nil, pendingStartup: false, hasCurrentSession: false, isRunning: false, expected: true),
            Case(label: "local preparing startup", launchState: .idle, sessionState: .preparing, activeStartupID: startupID, pendingStartup: false, hasCurrentSession: false, isRunning: false, expected: false),
            Case(label: "waitingForWatch", launchState: .waitingForWatch, sessionState: .preparing, activeStartupID: startupID, pendingStartup: false, hasCurrentSession: false, isRunning: false, expected: true),
            Case(label: "current session", launchState: .idle, sessionState: .preparing, activeStartupID: nil, pendingStartup: false, hasCurrentSession: true, isRunning: false, expected: false),
            Case(label: "pending pair", launchState: .idle, sessionState: .preparing, activeStartupID: nil, pendingStartup: true, hasCurrentSession: false, isRunning: false, expected: false),
            Case(label: "countdown", launchState: .idle, sessionState: .countdown, activeStartupID: nil, pendingStartup: false, hasCurrentSession: false, isRunning: false, expected: false),
            Case(label: "recording", launchState: .recording, sessionState: .recording, activeStartupID: nil, pendingStartup: false, hasCurrentSession: false, isRunning: true, expected: false),
            Case(label: "finishing", launchState: .idle, sessionState: .finishing, activeStartupID: nil, pendingStartup: false, hasCurrentSession: false, isRunning: false, expected: false),
            Case(label: "running flag", launchState: .recording, sessionState: .recording, activeStartupID: nil, pendingStartup: false, hasCurrentSession: false, isRunning: true, expected: false),
        ]

        for testCase in cases {
            controller.testing_configureMirroredAdmissionContext(
                launchState: testCase.launchState,
                sessionState: testCase.sessionState,
                activeStartupID: testCase.activeStartupID,
                pendingStartup: testCase.pendingStartup,
                hasCurrentSession: testCase.hasCurrentSession,
                isRunning: testCase.isRunning
            )
            XCTAssertEqual(
                controller.canAcceptMirroredSession,
                testCase.expected,
                "mirrored admission for \(testCase.label)"
            )
        }
    }

    @MainActor
    func testMirroredRejectionLeavesControllerStateUnchanged() async {
        let controller = WorkoutSessionController(routeRecorder: NoopRouteRecorder())
        let blueprint = makeStartRequest().blueprint
        controller.testing_configureMirroredAdmissionContext(
            launchState: .idle,
            sessionState: .preparing,
            activeStartupID: 3,
            isRunning: false
        )
        let before = controller.testing_mirroredAdmissionSnapshot()
        XCTAssertFalse(controller.canAcceptMirroredSession)
        let after = controller.testing_mirroredAdmissionSnapshot()
        XCTAssertEqual(before.launchState, after.launchState)
        XCTAssertEqual(before.sessionState, after.sessionState)
        XCTAssertEqual(before.isRunning, after.isRunning)
        XCTAssertEqual(before.hasSession, after.hasSession)
        XCTAssertEqual(before.hasPendingStartup, after.hasPendingStartup)
    }

    @MainActor
    func testRemoteEndSendCompletesBeforeLocalStopEnd() async {
        let controller = WorkoutSessionController(routeRecorder: NoopRouteRecorder())
        let blueprint = makeStartRequest().blueprint
        controller.testing_prepareForEndTest(blueprint: blueprint, state: .recording)
        controller.testing_skipHealthKitStopEnd = true
        controller.testing_skipFinishIfNeeded = true
        var sendCompleted = false
        controller.testing_remoteEndSendHandler = { _ in
            XCTAssertFalse(sendCompleted)
            sendCompleted = true
        }
        await controller.end()
        XCTAssertTrue(sendCompleted)
        XCTAssertEqual(
            controller.testing_lifecyclePhases,
            [.remoteEndSendStarted, .remoteEndSendCompleted, .localStopEnd]
        )
    }

    @MainActor
    func testRemoteEndSendFailureStillStopsLocally() async {
        let controller = WorkoutSessionController(routeRecorder: NoopRouteRecorder())
        let blueprint = makeStartRequest().blueprint
        controller.testing_prepareForEndTest(blueprint: blueprint, state: .recording)
        controller.testing_skipHealthKitStopEnd = true
        controller.testing_skipFinishIfNeeded = true
        enum SendFailure: Error { case failed }
        controller.testing_remoteEndSendHandler = { _ in
            throw SendFailure.failed
        }
        await controller.end()
        XCTAssertEqual(
            controller.testing_lifecyclePhases,
            [.remoteEndSendStarted, .remoteEndSendFailed, .localStopEnd]
        )
    }

    @MainActor
    func testRemoteOriginatedEndDoesNotEcho() async {
        let controller = WorkoutSessionController(routeRecorder: NoopRouteRecorder())
        let blueprint = makeStartRequest().blueprint
        controller.testing_prepareForEndTest(blueprint: blueprint, state: .recording)
        controller.testing_skipHealthKitStopEnd = true
        controller.testing_skipFinishIfNeeded = true
        controller.testing_remoteEndSendHandler = { _ in
            XCTFail("remote end should not echo")
        }
        await controller.testing_simulateRemoteEnd()
        XCTAssertEqual(controller.testing_lifecyclePhases, [.localStopEnd])
    }

    @MainActor
    func testTreadmillEstimationUsesConfiguredSpeedNotHardcodedDefault() {
        let controller = WorkoutSessionController(routeRecorder: NoopRouteRecorder())
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .freeRun,
            title: "Free run",
            location: .treadmill,
            steps: [WorkoutStep(name: "Main", target: .duration(seconds: 600), intensity: .rpe(3))],
            plannedDistanceMeters: 0,
            usesPaceTargets: false
        )
        controller.preparePreflightTreadmill(blueprint: blueprint, speedMetersPerSecond: 4.0)
        controller.testing_applyTreadmillConfiguration(for: blueprint)
        controller.testing_applyTreadmillConfiguration(for: blueprint)
        controller.testing_setElapsedForTreadmillEstimation(100)
        XCTAssertEqual(controller.estimatedTreadmillDistanceMeters(), 400)
        XCTAssertNotEqual(controller.estimatedTreadmillDistanceMeters(), 277.7)
        XCTAssertEqual(controller.treadmillTargetSpeedMetersPerSecond, 4.0)
    }

    @MainActor
    func testOverlappingFinishPathsAreAtMostOnce() {
        let controller = WorkoutSessionController(routeRecorder: NoopRouteRecorder())
        let blueprint = makeStartRequest().blueprint
        controller.testing_prepareForEndTest(blueprint: blueprint, state: .recording)
        controller.testing_setForceFinishSessionAvailable(true)
        XCTAssertTrue(controller.testing_beginFinishingIfNeeded())
        XCTAssertFalse(controller.testing_beginFinishingIfNeeded())
        XCTAssertEqual(controller.sessionState, .finishing)
    }

    func testCoordinatorRecordingPhaseIsNotStarting() {
        var startup = WatchWorkoutStartupCoordinator()
        let generation = startup.beginStartup()
        startup.markRecording(expectedGeneration: generation)
        XCTAssertEqual(startup.phase, .recording)
        XCTAssertNotEqual(startup.phase, .starting)
    }

    @MainActor
    func testActiveSessionSnapshotUsesResultSource() {
        let controller = WorkoutSessionController(routeRecorder: NoopRouteRecorder())
        let blueprint = makeStartRequest().blueprint
        controller.testing_configureSnapshot(blueprint: blueprint, source: .wrathspeedWatch)
        let snapshotExpectation = expectation(description: "snapshot")
        var captured: ActiveSessionSnapshot?
        controller.onSnapshot = { snapshot in
            captured = snapshot
            snapshotExpectation.fulfill()
        }
        controller.testing_publishSnapshot()
        waitForExpectations(timeout: 1)
        XCTAssertEqual(captured?.source, .wrathspeedWatch)

        controller.resultSource = .wrathspeedPhone
        let phoneExpectation = expectation(description: "phone snapshot")
        controller.onSnapshot = { snapshot in
            captured = snapshot
            phoneExpectation.fulfill()
        }
        controller.testing_publishSnapshot(clear: true)
        waitForExpectations(timeout: 1)
        XCTAssertEqual(captured?.source, .wrathspeedPhone)
        XCTAssertEqual(captured?.state, .saved)
    }

    func testWatchStartupCoordinatorControlReadiness() {
        var startup = WatchWorkoutStartupCoordinator()
        XCTAssertFalse(startup.canPauseOrLap)

        let generation = startup.beginStartup()
        XCTAssertFalse(startup.canPauseOrLap)

        startup.markRecording(expectedGeneration: generation)
        XCTAssertTrue(startup.canPauseOrLap)

        startup.cancelStartup()
        XCTAssertFalse(startup.canPauseOrLap)
    }

    func testWatchStartupCancellationInvalidatesStaleGeneration() {
        var startup = WatchWorkoutStartupCoordinator()
        let first = startup.beginStartup()
        startup.cancelStartup()
        startup.markRecording(expectedGeneration: first)
        XCTAssertFalse(startup.canPauseOrLap)
        XCTAssertEqual(startup.phase, .idle)
    }

    func testWatchStartRequestDecodesLegacyPayloadWithoutUnit() throws {
        let request = makeStartRequest()
        let encoded = try JSONEncoder().encode(request)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "unit")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(WatchStartRequest.self, from: legacy)
        XCTAssertNil(decoded.unit)
        XCTAssertEqual(decoded.vdot, 45)
        XCTAssertEqual(decoded.blueprint.title, "Easy run")
    }

    func testRouteSamplingCapsPointsAndPreservesEndpoints() {
        let points = (0..<1_000).map {
            RoutePoint(latitude: Double($0), longitude: Double(-$0), timestamp: Date(timeIntervalSince1970: Double($0)))
        }
        let sampled = RouteSampler.displayRoute(from: points, limit: 100)
        XCTAssertEqual(sampled.count, 100)
        XCTAssertEqual(sampled.first, points.first)
        XCTAssertEqual(sampled.last, points.last)
    }

    @MainActor
    func testStrengthPreferenceUpdatePreservesPastAndRunningPlanAndPersists() throws {
        let catalog = try makeCatalog()
        let container = try ModelContainer(
            for: Schema([
                SnapshotEntity.self,
                MigrationMarkerEntity.self,
                AppSettingsEntity.self,
                TrainingPlanEntity.self,
                ScheduledWorkoutEntity.self,
                WorkoutResultEntity.self,
                StrengthSessionEntity.self,
            ]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = AppStore(strengthCatalogLoader: { catalog })
        store.attach(context: ModelContext(container))

        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let profile = RunnerProfile(
            ability: .intermediate,
            daysPerWeek: 4,
            longRunWeekday: .saturday,
            unit: .kilometers
        )
        let run = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: calendar.date(byAdding: .day, value: 28, to: today)!,
            kind: .easy,
            title: "Easy run",
            steps: [WorkoutStep(name: "Easy", target: .distance(meters: 5_000), intensity: .zone(.easy))],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        let plan = TrainingPlan(goal: TrainingGoal(kind: .fiveK, weekCount: 8), profile: profile, workouts: [run])
        store.profile = profile
        store.plan = plan

        let existing = StrengthPlanner.schedule(
            preferences: StrengthPreferences(),
            startDate: calendar.date(byAdding: .day, value: -14, to: today)!,
            weekCount: 4,
            calendar: calendar,
            catalog: catalog
        )
        store.strengthSessions = existing
        let pastIDs = Set(existing.filter { $0.date < today }.map(\.id))

        let updated = StrengthPreferences(
            ability: .advanced,
            goal: .allRound,
            durationMinutes: 60,
            sessionsPerWeek: 3,
            preferredDays: [.tuesday, .thursday, .saturday],
            equipment: [.bodyweight, .dumbbell]
        )
        store.updateStrengthPreferences(updated)

        XCTAssertEqual(store.strengthPrefs, updated)
        XCTAssertEqual(store.plan, plan)
        XCTAssertEqual(Set(store.strengthSessions.filter { $0.date < today }.map(\.id)), pastIDs)
        XCTAssertTrue(store.strengthSessions.filter { $0.date >= today }.allSatisfy { $0.durationMinutes == 60 })

        let restored = AppStore(strengthCatalogLoader: { catalog })
        restored.attach(context: ModelContext(container))
        XCTAssertEqual(restored.strengthPrefs, updated)
        XCTAssertEqual(restored.plan?.id, plan.id)
        XCTAssertEqual(restored.plan?.goal, plan.goal)
        XCTAssertEqual(restored.plan?.workouts, plan.workouts)
        XCTAssertEqual(restored.strengthSessions, store.strengthSessions)
    }

    @MainActor
    func testStrengthPreferenceUpdateIsAtomicWhenCatalogLoadingFails() {
        enum FixtureError: Error { case unavailable }
        let store = AppStore(strengthCatalogLoader: { throw FixtureError.unavailable })
        let original = store.strengthPrefs
        let profile = RunnerProfile(
            ability: .beginner,
            daysPerWeek: 3,
            longRunWeekday: .saturday,
            unit: .kilometers
        )
        let run = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: Date().addingTimeInterval(7 * 86_400),
            kind: .easy,
            title: "Easy run",
            steps: [WorkoutStep(name: "Easy", target: .distance(meters: 5_000), intensity: .zone(.easy))],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        store.plan = TrainingPlan(goal: TrainingGoal(kind: .fiveK), profile: profile, workouts: [run])

        var requested = original
        requested.durationMinutes = 60
        store.updateStrengthPreferences(requested)

        XCTAssertEqual(store.strengthPrefs, original)
        XCTAssertNotNil(store.errorMessage)
    }

    private func makeStartRequest(unit: DistanceUnit? = .kilometers) -> WatchStartRequest {
        WatchStartRequest(
            blueprint: WorkoutBlueprint(
                date: Date(),
                kind: .easy,
                title: "Easy run",
                steps: [WorkoutStep(name: "Easy", target: .distance(meters: 5_000), intensity: .zone(.easy))],
                plannedDistanceMeters: 5_000,
                usesPaceTargets: true
            ),
            vdot: 45,
            unit: unit
        )
    }

    private func makeCatalog() throws -> StrengthCatalog {
        let json = """
        {"exercises":[
          {"id":"squat","name":"Squat","focus":["legsCore","fullBody"],"equipment":["bodyweight","dumbbell"],"symbolName":"figure.strengthtraining.traditional","defaultReps":10,"cue":"Sit back."},
          {"id":"plank","name":"Plank","focus":["legsCore","fullBody"],"equipment":["bodyweight"],"symbolName":"figure.core.training","defaultReps":10,"cue":"Brace."},
          {"id":"pushup","name":"Push-up","focus":["upper","fullBody"],"equipment":["bodyweight"],"symbolName":"figure.strengthtraining.functional","defaultReps":10,"cue":"Stay tall."}
        ]}
        """
        return try JSONDecoder().decode(StrengthCatalog.self, from: Data(json.utf8))
    }
}

private final class NoopRouteRecorder: WorkoutRouteRecording {
    func begin(for location: RunLocation) {}
    func setRecording(_ isRecording: Bool) {}
    func stop() {}
    func finish(for workout: HKWorkout) async throws -> [RoutePoint] { [] }
}
