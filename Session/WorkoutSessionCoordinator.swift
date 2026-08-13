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
    private var watchTimeoutTask: Task<Void, Never>?
    private(set) var watchLaunchPhase: WatchLaunchPhase = .idle
    private var pendingBlueprint: WorkoutBlueprint?
    private var pendingVDOT: Double?
    private var pendingZones: PaceZones?
    private var pendingCuesEnabled = true
    private var pendingSource: WorkoutSource = .wrathspeedPhone

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
                self?.watchTimeoutTask?.cancel()
                self?.watchLaunchPhase = .recording
                await self?.session.attachMirrored(session: mirrored)
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
        source: WorkoutSource = .wrathspeedPhone
    ) async throws {
        pendingBlueprint = blueprint
        pendingVDOT = vdot
        pendingZones = zones
        pendingCuesEnabled = cuesEnabled
        pendingSource = source
        session.resultSource = source
        session.zones = zones
        session.cuesEnabled = cuesEnabled

        if WCSessionBridge.isWatchAppInstalled {
            watchLaunchPhase = .waitingForWatch
            bridge.requestStart(blueprint, vdot: vdot)
            watchTimeoutTask?.cancel()
            watchTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard let self, !Task.isCancelled else { return }
                if self.watchLaunchPhase == .waitingForWatch, !self.session.isRunning {
                    self.watchLaunchPhase = .timedOut
                }
            }
            try await session.start(blueprint: blueprint, zones: zones)
            if session.isRunning {
                watchTimeoutTask?.cancel()
                watchLaunchPhase = .recording
            }
            return
        }

        try await session.start(blueprint: blueprint, zones: zones)
        watchLaunchPhase = session.isRunning ? .recording : .idle
    }

    func retryWatchLaunch() async {
        guard let blueprint = pendingBlueprint else { return }
        watchLaunchPhase = .waitingForWatch
        bridge.requestStart(blueprint, vdot: pendingVDOT)
        watchTimeoutTask?.cancel()
        watchTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, !Task.isCancelled else { return }
            if self.watchLaunchPhase == .waitingForWatch, !self.session.isRunning {
                self.watchLaunchPhase = .timedOut
            }
        }
    }

    func startOnPhoneAfterWatchTimeout() async {
        guard let blueprint = pendingBlueprint else { return }
        watchTimeoutTask?.cancel()
        do {
            try await session.startOnPhoneOnly(blueprint: blueprint, zones: pendingZones)
            watchLaunchPhase = .recording
        } catch {
            watchLaunchPhase = .failed(error.localizedDescription)
        }
    }

    func cancelWatchLaunch() {
        watchTimeoutTask?.cancel()
        watchLaunchPhase = .idle
        pendingBlueprint = nil
        session.cancelPendingLaunch()
    }
}
