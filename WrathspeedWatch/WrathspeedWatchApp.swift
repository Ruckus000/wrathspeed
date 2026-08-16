import HealthKit
import SwiftUI
import WatchKit
import WrathspeedCore

@main
struct WrathspeedWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchDelegate.self) private var delegate
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchTodayView()
                .environment(store)
                .onAppear {
                    delegate.onWorkoutLaunch = { store.receiveLaunchRequest() }
                    store.session.onFinished = { result in
                        store.bridge.sendResult(result)
                    }
                    if delegate.consumePendingWorkoutLaunch() {
                        store.receiveLaunchRequest()
                    }
                    if let request = store.bridge.pendingStartRequest {
                        store.receive(request)
                    }
                }
        }
    }
}

@MainActor
final class WatchDelegate: NSObject, WKApplicationDelegate {
    var onWorkoutLaunch: (() -> Void)?
    private var hasPendingWorkoutLaunch = false

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        if let onWorkoutLaunch {
            onWorkoutLaunch()
        } else {
            hasPendingWorkoutLaunch = true
        }
    }

    func consumePendingWorkoutLaunch() -> Bool {
        defer { hasPendingWorkoutLaunch = false }
        return hasPendingWorkoutLaunch
    }
}
