import Foundation
import WrathspeedCore

@MainActor
@Observable
final class WatchStore {
    let session = WorkoutSessionController()
    let bridge = WCSessionBridge()
    var resolvedStart: WatchStartRequest?
    private var startResolver = WatchStartResolver()
    private var startup = WatchWorkoutStartupCoordinator()
    private var startupTask: Task<Void, Never>?

    var upcoming: [WorkoutBlueprint] {
        bridge.upcoming?.blueprints ?? []
    }

    var distanceUnit: DistanceUnit {
        bridge.upcoming?.unit ?? .default()
    }

    var canPauseOrLap: Bool {
        startup.canPauseOrLap && session.isRunning
    }

    var isStartupPending: Bool {
        startup.phase == .starting
    }

    func receiveLaunchRequest() {
        if let request = startResolver.receiveLaunchRequest() {
            resolvedStart = request
        }
    }

    func receive(_ request: WatchStartRequest) {
        if let request = startResolver.receive(request) {
            resolvedStart = request
        }
    }

    func beginWorkout(_ request: WatchStartRequest) {
        guard session.sessionState != .finishing else { return }
        startupTask?.cancel()
        let generation = startup.beginStartup()
        let context = WatchWorkoutContext.make(from: request, fallbackUnit: distanceUnit)
        context.apply(to: session)

        startupTask = Task {
            do {
                try await session.start(blueprint: context.blueprint, zones: context.zones)
                guard !Task.isCancelled, startup.isGenerationCurrent(generation) else { return }
                guard session.isRunning else {
                    startup.reset()
                    return
                }
                startup.markRecording(expectedGeneration: generation)
            } catch is CancellationError {
                guard startup.isGenerationCurrent(generation) else { return }
                session.cancelPendingLaunch()
                startup.cancelStartup()
            } catch {
                guard startup.isGenerationCurrent(generation) else { return }
                session.cancelPendingLaunch()
                startup.reset()
            }
        }
    }

    func cancelStartupIfPending() {
        guard startup.phase == .starting else { return }
        startupTask?.cancel()
        startup.cancelStartup()
        session.cancelPendingLaunch()
    }

    func endWorkout() async {
        startupTask?.cancel()
        startup.cancelStartup()
        if session.isRunning {
            await session.end()
        } else {
            session.cancelPendingLaunch()
        }
        startup.reset()
    }
}
