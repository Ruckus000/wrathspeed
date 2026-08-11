import Foundation
import HealthKit
import WrathspeedCore

#if os(iOS)
import ActivityKit
#endif

@MainActor
@Observable
final class WorkoutSessionController: NSObject {
    private(set) var metrics = LiveMetrics(elapsed: 0, distanceMeters: 0)
    private(set) var stepper: WorkoutStepper?
    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var blueprint: WorkoutBlueprint?
    private(set) var lastCues: [Cue] = []
    var cuesEnabled = true
    var zones: PaceZones?

    var onFinished: ((WorkoutResult) -> Void)?

    private let healthStore = HKHealthStore()
    private let speech = SpeechCuePlayer()
    private var cuePolicy = CuePolicy()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startedAt: Date?
    private var isPrimary = true
    private var applyingRemote = false

    #if os(iOS)
    nonisolated(unsafe) private var liveActivity: Activity<WorkoutActivityAttributes>?
    #endif

    func requestAuthorization() async throws {
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.runningSpeed),
            HKObjectType.workoutType(),
        ]
        let share: Set<HKSampleType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKObjectType.workoutType(),
        ]
        try await healthStore.requestAuthorization(toShare: share, read: read)
    }

    func start(blueprint: WorkoutBlueprint, zones: PaceZones?) async throws {
        if isRunning { return }
        self.blueprint = blueprint
        self.zones = zones
        stepper = WorkoutStepper(blueprint: blueprint)
        cuePolicy = CuePolicy()
        speech.isEnabled = cuesEnabled
        speech.activateSession()
        try await requestAuthorization()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = blueprint.location == .outdoor ? .outdoor : .indoor

        #if os(iOS)
        if WCSessionBridge.isWatchAppInstalled {
            try await startWatchApp(configuration)
            return
        }
        #endif

        try await startPrimary(configuration: configuration)
    }

    func attachMirrored(session: HKWorkoutSession) async {
        isPrimary = false
        self.session = session
        builder = session.associatedWorkoutBuilder()
        session.delegate = self
        builder?.delegate = self
        builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: session.workoutConfiguration)
        isRunning = true
        startedAt = Date()
        #if os(iOS)
        startLiveActivity()
        #endif
    }

    func pause() {
        session?.pause()
        isPaused = true
        if !applyingRemote { send(.pause) }
    }

    func resume() {
        session?.resume()
        isPaused = false
        if !applyingRemote { send(.resume) }
    }

    func skipStep() {
        guard var stepper else { return }
        let events = stepper.skipCurrent(metrics: metrics)
        self.stepper = stepper
        handle(events: events)
        if !applyingRemote { send(.skipStep) }
        if stepper.isComplete {
            Task { await end() }
        }
    }

    func end() async {
        session?.stopActivity(with: Date())
        session?.end()
        await finishIfNeeded()
        if !applyingRemote { send(.end) }
    }

    #if os(iOS)
    private func startWatchApp(_ configuration: HKWorkoutConfiguration) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.startWatchApp(with: configuration) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HKError(.errorHealthDataUnavailable))
                }
            }
        }
    }
    #endif

    private func startPrimary(configuration: HKWorkoutConfiguration) async throws {
        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        isPrimary = true
        let start = Date()
        startedAt = start
        #if os(watchOS)
        try await session.startMirroringToCompanionDevice()
        #endif
        session.startActivity(with: start)
        try await builder.beginCollection(at: start)
        isRunning = true
        if let first = blueprint?.steps.first {
            speech.speak(.stepStarted(first.name))
        }
        #if os(iOS)
        startLiveActivity()
        #endif
    }

    private func handle(events: [StepEvent]) {
        guard let step = stepper?.currentStep ?? blueprint?.steps.last else {
            lastCues = cuePolicy.evaluate(
                step: nil,
                usesPaceTargets: blueprint?.usesPaceTargets ?? false,
                zones: zones,
                metrics: metrics,
                events: events
            )
            lastCues.forEach(speech.speak)
            return
        }
        lastCues = cuePolicy.evaluate(
            step: step,
            usesPaceTargets: blueprint?.usesPaceTargets ?? false,
            zones: zones,
            metrics: metrics,
            events: events
        )
        lastCues.forEach(speech.speak)
    }

    private func send(_ kind: SessionSyncMessage.Kind) {
        let message = SessionSyncMessage(
            kind: kind,
            elapsed: metrics.elapsed,
            distanceMeters: metrics.distanceMeters,
            paceSecPerKm: metrics.currentPaceSecPerKm,
            stepIndex: stepper?.stepIndex ?? 0,
            stepName: stepper?.currentStep?.name ?? "",
            isPaused: isPaused
        )
        if let data = message.encoded() {
            Task {
                try? await session?.sendToRemoteWorkoutSession(data: data)
            }
        }
        #if os(iOS)
        updateLiveActivity()
        #endif
    }

    private func finishIfNeeded() async {
        guard isRunning else { return }
        isRunning = false
        let end = Date()
        try? await builder?.endCollection(at: end)
        _ = try? await builder?.finishWorkout()
        if let blueprint {
            let duration = end.timeIntervalSince(startedAt ?? end)
            let pace = metrics.distanceMeters > 0 ? (duration / metrics.distanceMeters) * 1_000 : nil
            let result = WorkoutResult(
                workoutID: blueprint.id,
                startedAt: startedAt ?? end,
                duration: duration,
                distanceMeters: metrics.distanceMeters,
                averagePaceSecPerKm: pace,
                location: blueprint.location
            )
            onFinished?(result)
        }
        #if os(iOS)
        await liveActivity?.end(nil, dismissalPolicy: .immediate)
        liveActivity = nil
        #endif
    }

    #if os(iOS)
    private func startLiveActivity() {
        let attributes = WorkoutActivityAttributes(workoutName: blueprint?.title ?? "Run")
        let state = activityState()
        liveActivity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    private func updateLiveActivity() {
        let state = activityState()
        Task { await liveActivity?.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func activityState() -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            title: blueprint?.title ?? "Run",
            stepName: stepper?.currentStep?.name ?? "",
            elapsed: metrics.elapsed,
            distanceMeters: metrics.distanceMeters,
            paceSecPerKm: metrics.currentPaceSecPerKm,
            isPaused: isPaused
        )
    }
    #endif
}

extension WorkoutSessionController: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            isPaused = toState == .paused
            if toState == .ended {
                await finishIfNeeded()
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            applyingRemote = true
            defer { applyingRemote = false }
            for packet in data {
                guard let message = SessionSyncMessage.decode(packet) else { continue }
                switch message.kind {
                case .pause: pause()
                case .resume: resume()
                case .end: await end()
                case .skipStep: skipStep()
                case .metrics:
                    metrics = LiveMetrics(
                        elapsed: message.elapsed,
                        distanceMeters: message.distanceMeters,
                        currentPaceSecPerKm: message.paceSecPerKm
                    )
                }
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            let distance = workoutBuilder.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meter()) ?? metrics.distanceMeters
            let start = workoutBuilder.startDate ?? startedAt ?? Date()
            let elapsed = Date().timeIntervalSince(start)
            let pace: Double? = {
                if let speed = workoutBuilder.statistics(for: HKQuantityType(.runningSpeed))?
                    .mostRecentQuantity()?.doubleValue(for: HKUnit.meter().unitDivided(by: .second())),
                   speed > 0 {
                    return 1_000 / speed
                }
                if distance > 0, elapsed > 0 { return (elapsed / distance) * 1_000 }
                return nil
            }()
            metrics = LiveMetrics(elapsed: elapsed, distanceMeters: distance, currentPaceSecPerKm: pace)
            if var stepper {
                let events = stepper.update(metrics: metrics)
                self.stepper = stepper
                handle(events: events)
            }
            send(.metrics)
            if stepper?.isComplete == true {
                await end()
            }
        }
    }
}

