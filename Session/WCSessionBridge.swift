import Foundation
import WatchConnectivity
import WrathspeedCore

@MainActor
@Observable
final class WCSessionBridge: NSObject, WCSessionDelegate {
    static var isWatchAppInstalled: Bool {
        #if os(iOS)
        WCSession.isSupported() && WCSession.default.isWatchAppInstalled
        #else
        true
        #endif
    }

    var upcoming: UpcomingWorkoutsPayload?
    var pendingStartRequest: WatchStartRequest?
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

    func requestStart(_ blueprint: WorkoutBlueprint, vdot: Double?) {
        guard WCSession.isSupported() else { return }
        if let data = try? JSONEncoder().encode(WatchStartRequest(blueprint: blueprint, vdot: vdot)) {
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
        Task { @MainActor in self.publishPlanContextIfPossible() }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
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
