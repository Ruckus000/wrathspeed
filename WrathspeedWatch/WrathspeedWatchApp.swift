import HealthKit
import SwiftUI
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
                    store.session.onFinished = { result in
                        store.bridge.sendResult(result)
                    }
                    if let pending = store.bridge.pendingStart {
                        store.pending = pending
                    }
                }
        }
    }
}

final class WatchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        NotificationCenter.default.post(name: .watchShouldStartWorkout, object: workoutConfiguration)
    }
}

extension Notification.Name {
    static let watchShouldStartWorkout = Notification.Name("watchShouldStartWorkout")
}

@MainActor
@Observable
final class WatchStore {
    let session = WorkoutSessionController()
    let bridge = WCSessionBridge()
    var pending: WorkoutBlueprint?

    var upcoming: [WorkoutBlueprint] {
        bridge.upcoming?.blueprints ?? []
    }
}
