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
    var pendingStart: WorkoutBlueprint?
    var latestResult: WorkoutResult?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func pushUpcoming(_ payload: UpcomingWorkoutsPayload) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        if let data = try? JSONEncoder().encode(payload) {
            try? WCSession.default.updateApplicationContext(["upcoming": data])
        }
    }

    func requestStart(_ blueprint: WorkoutBlueprint) {
        guard WCSession.isSupported() else { return }
        if let data = try? JSONEncoder().encode(WatchStartRequest(blueprint: blueprint)) {
            WCSession.default.transferUserInfo(["start": data])
            try? WCSession.default.updateApplicationContext(
                WCSession.default.receivedApplicationContext.merging(["start": data]) { _, new in new }
            )
        }
    }

    func sendResult(_ result: WorkoutResult) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(result) else { return }
        WCSession.default.transferUserInfo(["result": data])
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

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
                pendingStart = try? JSONDecoder().decode(WatchStartRequest.self, from: startData).blueprint
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let startData = userInfo["start"] as? Data
        let resultData = userInfo["result"] as? Data
        Task { @MainActor in
            if let startData {
                pendingStart = try? JSONDecoder().decode(WatchStartRequest.self, from: startData).blueprint
            }
            if let resultData {
                latestResult = try? JSONDecoder().decode(WorkoutResult.self, from: resultData)
            }
        }
    }
}
