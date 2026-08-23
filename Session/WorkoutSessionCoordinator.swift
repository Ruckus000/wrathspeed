import HealthKit
import WrathspeedCore

@MainActor
final class WorkoutSessionCoordinator {
    enum WatchLaunchPhase: Equatable {
        case idle
        case waitingForWatch
        case timedOut
        case recording
        case failed(String)
    }

    let session = WorkoutSessionController()
    private let bridge = WCSessionBridge()

    /// Whether a paired Watch can take this workout. Observable through `bridge`, so a view
    /// reading it updates when WatchConnectivity finishes activating.
    var isWatchAppAvailable: Bool { bridge.isWatchAppInstalled }
    private let watchLaunchTimeout: Duration
    private var watchTimeoutTask: Task<Void, Never>?
    private(set) var watchLaunchPhase: WatchLaunchPhase = .idle

    /// Fired on every `watchLaunchPhase` transition.
    ///
    /// The phase keeps moving long after the call that armed it has returned -- the timeout
    /// lands `watchLaunchTimeout` later -- so reading `watchLaunchPhase` straight after
    /// `start()` or `retryWatchLaunch()` only ever sees `.waitingForWatch`. That is exactly
    /// how the watch-not-ready sheet came to be unreachable. Anything that has to react to
    /// `.timedOut` must go through this.
    var onWatchLaunchPhaseChange: ((WatchLaunchPhase) -> Void)?

    private var pendingBlueprint: WorkoutBlueprint?
    private var pendingVDOT: Double?
    private var pendingUnit: DistanceUnit?
    private var pendingZones: PaceZones?
    private var pendingCuesEnabled = true
    private var pendingSource: WorkoutSource = .wrathspeedPhone
    private var pendingTreadmillSpeed: Double?

    init(watchLaunchTimeout: Duration = .seconds(12)) {
        self.watchLaunchTimeout = watchLaunchTimeout
    }

    func configure(
        cuesEnabled: Bool,
        zones: PaceZones?,
        onResult: @escaping (WorkoutResult) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        session.cuesEnabled = cuesEnabled
        session.zones = zones
        session.onFinished = onResult
        session.onFailure = onFailure
        bridge.onResult = onResult
    }

    func installMirroringHandler() {
        HKHealthStore().workoutSessionMirroringStartHandler = { [weak self] mirrored in
            Task { @MainActor in
                guard let self else { return }
                let attached = await self.session.attachMirrored(session: mirrored)
                guard attached else { return }
                self.watchTimeoutTask?.cancel()
                self.setWatchLaunchPhase(.recording)
            }
        }
    }

    func pushUpcoming(_ payload: UpcomingWorkoutsPayload) {
        bridge.pushUpcoming(payload)
    }

    func consumeLatestResult() -> WorkoutResult? {
        defer { bridge.latestResult = nil }
        return bridge.latestResult
    }

    func start(
        blueprint: WorkoutBlueprint,
        vdot: Double?,
        zones: PaceZones?,
        cuesEnabled: Bool,
        source: WorkoutSource = .wrathspeedPhone,
        unit: DistanceUnit? = nil,
        treadmillSpeedMetersPerSecond: Double? = nil
    ) async throws {
        guard session.sessionState != .finishing else { return }
        pendingBlueprint = blueprint
        pendingVDOT = vdot
        pendingUnit = unit
        pendingZones = zones
        pendingCuesEnabled = cuesEnabled
        pendingSource = source
        pendingTreadmillSpeed = treadmillSpeedMetersPerSecond
        session.resultSource = source
        session.zones = zones
        session.cuesEnabled = cuesEnabled
        // One snapshot for both decisions. The controller used to re-read the global itself,
        // so a state change mid-start could have it take the phone path while this branch had
        // already told the Watch to start.
        let watchAvailable = bridge.isWatchAppInstalled
        session.watchAppIsInstalled = watchAvailable

        if watchAvailable {
            setWatchLaunchPhase(.waitingForWatch)
            bridge.requestStart(blueprint, vdot: vdot, unit: unit)
            // Cancelled here but armed below. The twelve seconds must measure how long the
            // Watch has had to mirror back, not how long the user spent on the HealthKit
            // permission sheet that `session.start` raises -- a first run spent longer than
            // that on the toggle list, the timeout sheet displaced the system prompt, and the
            // authorization request was left queued forever, after which no workout could
            // start at all. `session.start` returns as soon as `startWatchApp` succeeds while
            // the Watch is still being waited on, so arming after it is the honest moment.
            watchTimeoutTask?.cancel()
            try await session.start(
                blueprint: blueprint,
                zones: zones,
                treadmillSpeedMetersPerSecond: treadmillSpeedMetersPerSecond
            )
            if session.isRunning {
                setWatchLaunchPhase(.recording)
            } else {
                armWatchTimeout()
            }
            return
        }

        try await session.start(
            blueprint: blueprint,
            zones: zones,
            treadmillSpeedMetersPerSecond: treadmillSpeedMetersPerSecond
        )
        setWatchLaunchPhase(session.isRunning ? .recording : .idle)
    }

    func retryWatchLaunch() async {
        guard let blueprint = pendingBlueprint else { return }
        setWatchLaunchPhase(.waitingForWatch)
        bridge.requestStart(blueprint, vdot: pendingVDOT, unit: pendingUnit)
        armWatchTimeout()
    }

    func startOnPhoneAfterWatchTimeout() async {
        guard let blueprint = pendingBlueprint else { return }
        watchTimeoutTask?.cancel()
        do {
            try await session.startOnPhoneOnly(
                blueprint: blueprint,
                zones: pendingZones,
                treadmillSpeedMetersPerSecond: pendingTreadmillSpeed
            )
            setWatchLaunchPhase(session.isRunning ? .recording : .idle)
        } catch {
            setWatchLaunchPhase(.failed(error.localizedDescription))
        }
    }

    func cancelWatchLaunch() {
        watchTimeoutTask?.cancel()
        setWatchLaunchPhase(.idle)
        pendingBlueprint = nil
        session.cancelPendingLaunch()
    }

    private func setWatchLaunchPhase(_ phase: WatchLaunchPhase) {
        guard watchLaunchPhase != phase else { return }
        watchLaunchPhase = phase
        onWatchLaunchPhaseChange?(phase)
    }

    /// Re-arms the wait for the Watch. Cancelling first matters: a retry must not leave the
    /// previous attempt's timer running to fire against the new one.
    private func armWatchTimeout() {
        watchTimeoutTask?.cancel()
        let timeout = watchLaunchTimeout
        watchTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, !Task.isCancelled else { return }
            if self.watchLaunchPhase == .waitingForWatch, !self.session.isRunning {
                self.setWatchLaunchPhase(.timedOut)
            }
        }
    }

    #if DEBUG
    /// Arms the Watch wait without HealthKit. The real entry point runs through
    /// `session.start`, which needs a workout session the simulator cannot provide.
    func testing_beginWatchLaunchWait() {
        setWatchLaunchPhase(.waitingForWatch)
        armWatchTimeout()
    }
    #endif
}
