import Foundation
import WatchConnectivity
import WrathspeedCore

@MainActor
@Observable
final class WCSessionBridge: NSObject, WCSessionDelegate {
    /// Whether a paired Watch has the app installed.
    ///
    /// Stored, not read through to `WCSession` on demand. `activate()` is asynchronous and
    /// `isWatchAppInstalled` is meaningless until it completes, so a synchronous read during
    /// launch answers `false` for a Watch that is sitting right there -- which is how preflight
    /// came to report NOT INSTALLED on one launch and AVAILABLE on the next, for the same
    /// install. WatchConnectivity says when the answer changes, and
    /// `sessionWatchStateDidChange` exists for exactly that, so record it from the delegate
    /// and let observers follow.
    #if os(iOS)
    private(set) var isWatchAppInstalled = false
    #else
    let isWatchAppInstalled = true
    #endif

    var upcoming: UpcomingWorkoutsPayload?
    var pendingStartRequest: WatchStartRequest?
    var pendingStart: WorkoutBlueprint? { pendingStartRequest?.blueprint }
    var latestResult: WorkoutResult?
    var onResult: ((WorkoutResult) -> Void)?
    private var lastPlanContext: [String: Any]?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func pushUpcoming(_ payload: UpcomingWorkoutsPayload) {
        if let data = try? JSONEncoder().encode(payload) {
            lastPlanContext = ["upcoming": data]
            publishPlanContextIfPossible()
        }
    }

    private func publishPlanContextIfPossible() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, let lastPlanContext else { return }
        try? WCSession.default.updateApplicationContext(lastPlanContext)
    }

    func requestStart(_ blueprint: WorkoutBlueprint, vdot: Double?, unit: DistanceUnit? = nil) {
        guard WCSession.isSupported() else { return }
        if let data = try? JSONEncoder().encode(WatchStartRequest(blueprint: blueprint, vdot: vdot, unit: unit)) {
            let payload = ["start": data]
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(payload, replyHandler: nil) { _ in
                    WCSession.default.transferUserInfo(payload)
                }
            } else {
                WCSession.default.transferUserInfo(payload)
            }
        }
    }

    func sendResult(_ result: WorkoutResult) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(result) else { return }
        WCSession.default.transferUserInfo(["result": data])
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.refreshWatchAppInstalled()
            self.publishPlanContextIfPossible()
        }
    }

    #if os(iOS)
    /// Pairing, unpairing and installing the Watch app all arrive here.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshWatchAppInstalled() }
    }

    private func refreshWatchAppInstalled() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        isWatchAppInstalled = WCSession.default.isWatchAppInstalled
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #else
    private func refreshWatchAppInstalled() {}
    #endif

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let upcomingData = applicationContext["upcoming"] as? Data
        let startData = applicationContext["start"] as? Data
        Task { @MainActor in
            if let upcomingData {
                upcoming = try? JSONDecoder().decode(UpcomingWorkoutsPayload.self, from: upcomingData)
            }
            if let startData {
                if let start = try? JSONDecoder().decode(WatchStartRequest.self, from: startData) {
                    pendingStartRequest = start
                }
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    nonisolated private func receive(_ payload: [String: Any]) {
        let startData = payload["start"] as? Data
        let resultData = payload["result"] as? Data
        Task { @MainActor in
            if let startData {
                if let start = try? JSONDecoder().decode(WatchStartRequest.self, from: startData) {
                    pendingStartRequest = start
                }
            }
            if let resultData {
                if let result = try? JSONDecoder().decode(WorkoutResult.self, from: resultData) {
                    latestResult = result
                    onResult?(result)
                }
            }
        }
    }
}
