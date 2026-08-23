import SwiftData
import XCTest
@testable import Wrathspeed
import WrathspeedCore

/// The Watch wait times out well after the call that armed it has returned. `AppStore` used
/// to read `watchLaunchPhase` synchronously right after `await`, where it is always
/// `.waitingForWatch`, so `showWatchLaunchTimeout` never became true and the watch-not-ready
/// sheet -- RETRY WATCH / START ON PHONE / CANCEL -- was unreachable. A phone paired with a
/// Watch that failed to launch was stranded on the live screen with no way out.
@MainActor
final class WatchLaunchTimeoutTests: XCTestCase {
    private let timeout = Duration.milliseconds(40)

    private func makeStore(
        coordinator: WorkoutSessionCoordinator
    ) throws -> AppStore {
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
        let store = AppStore(workoutCoordinator: coordinator)
        store.attach(context: ModelContext(container))
        return store
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

    /// Generous against the 40ms interval so a loaded CI machine does not flake; the assertion
    /// is about the transition happening at all, not about its latency.
    private func waitPastTimeout() async {
        try? await Task.sleep(for: .milliseconds(400))
    }

    func testTimeoutSurfacesTheWatchNotReadySheet() async throws {
        let coordinator = WorkoutSessionCoordinator(watchLaunchTimeout: timeout)
        let store = try makeStore(coordinator: coordinator)

        coordinator.testing_beginWatchLaunchWait()
        XCTAssertFalse(store.showWatchLaunchTimeout, "Sheet must not appear while the Watch is still being given its chance")

        await waitPastTimeout()

        XCTAssertEqual(coordinator.watchLaunchPhase, .timedOut)
        XCTAssertTrue(store.showWatchLaunchTimeout, "Watch launch timed out but the recovery sheet never surfaced")
    }

    func testCancellingTheLaunchClosesTheSheetAndStopsTheTimer() async throws {
        let coordinator = WorkoutSessionCoordinator(watchLaunchTimeout: timeout)
        let store = try makeStore(coordinator: coordinator)

        coordinator.testing_beginWatchLaunchWait()
        await waitPastTimeout()
        XCTAssertTrue(store.showWatchLaunchTimeout)

        store.cancelWatchLaunch()

        XCTAssertEqual(coordinator.watchLaunchPhase, .idle)
        XCTAssertFalse(store.showWatchLaunchTimeout)
        XCTAssertEqual(store.session.launchState, .idle, "Cancelling must clear the launch state so the live cover dismisses")
    }

    func testRetryReopensTheWaitAndCanTimeOutAgain() async throws {
        let coordinator = WorkoutSessionCoordinator(watchLaunchTimeout: timeout)
        let store = try makeStore(coordinator: coordinator)

        coordinator.testing_beginWatchLaunchWait()
        await waitPastTimeout()
        XCTAssertTrue(store.showWatchLaunchTimeout)

        // Re-arming directly: `retryWatchLaunch` needs a pending blueprint from a real
        // `start`, which cannot run without HealthKit here.
        coordinator.testing_beginWatchLaunchWait()
        XCTAssertFalse(store.showWatchLaunchTimeout, "Retrying must close the sheet while the second attempt runs")

        await waitPastTimeout()
        XCTAssertTrue(store.showWatchLaunchTimeout, "A second failed attempt must surface the sheet again")
    }

    /// The timer used to be armed before `session.start` was awaited, so it ran while the
    /// HealthKit permission sheet was up and displaced it -- stranding the authorization
    /// request, after which no workout could start at all. A start that never gets going must
    /// leave no timer behind.
    func testAStartThatNeverGetsGoingArmsNoTimer() async throws {
        let coordinator = WorkoutSessionCoordinator(watchLaunchTimeout: timeout)
        let store = try makeStore(coordinator: coordinator)

        // `.finishing` makes coordinator.start return at its opening guard, before any of the
        // launch sequence runs -- reachable without HealthKit or a paired Watch.
        coordinator.session.testing_prepareForEndTest(blueprint: makeBlueprint(), state: .finishing)
        try await coordinator.start(
            blueprint: makeBlueprint(),
            vdot: nil,
            zones: nil,
            cuesEnabled: false
        )

        await waitPastTimeout()

        XCTAssertNotEqual(coordinator.watchLaunchPhase, .timedOut)
        XCTAssertFalse(store.showWatchLaunchTimeout, "A start that never began must not raise the watch-not-ready actions")
    }

    func testARecordingSessionSuppressesTheTimeout() async throws {
        let coordinator = WorkoutSessionCoordinator(watchLaunchTimeout: timeout)
        let store = try makeStore(coordinator: coordinator)

        coordinator.testing_beginWatchLaunchWait()
        // Stands in for the mirrored Watch session attaching before the timer lands.
        coordinator.session.testing_prepareForEndTest(blueprint: makeBlueprint())

        await waitPastTimeout()

        XCTAssertEqual(coordinator.watchLaunchPhase, .waitingForWatch)
        XCTAssertFalse(store.showWatchLaunchTimeout, "A session that started must not raise the watch-not-ready sheet")
    }
}
