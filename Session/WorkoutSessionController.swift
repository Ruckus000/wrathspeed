import Foundation
import HealthKit
import UIKit
import WrathspeedCore

@MainActor
@Observable
final class WorkoutSessionController: NSObject {
    enum LaunchState: Equatable {
        case idle
        case waitingForWatch
        case recording
        case failed(String)
    }

    private(set) var metrics = LiveMetrics(elapsed: 0, distanceMeters: 0)
    private(set) var stepper: WorkoutStepper?
    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var blueprint: WorkoutBlueprint?
    private(set) var lastCues: [Cue] = []
    private(set) var launchState: LaunchState = .idle
    var cuesEnabled = true
    var zones: PaceZones?
    var splitUnit: DistanceUnit = .kilometers
    var cueStyle: CueStyle = .standard
    var resultSource: WorkoutSource = .wrathspeedPhone
    var treadmillTargetSpeedMetersPerSecond: Double?
    var usesManualTreadmillDistance = false
    var pendingActualTreadmillDistance: Double?

    private(set) var sessionState: ActiveSessionState = .preparing
    var onFinished: ((WorkoutResult) -> Void)?
    var onFailure: ((Error) -> Void)?
    var onSnapshot: ((ActiveSessionSnapshot) -> Void)?

    private let healthStore = HKHealthStore()
    private let speech = SpeechCuePlayer()
    private var cuePolicy = CuePolicy()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startedAt: Date?
    private var isPrimary = true
    private var applyingRemote = false
    private let routeRecorder: any WorkoutRouteRecording
    private var pauseStartedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var recordedSplits: [WorkoutSplit] = []
    private var splitMarkedDistance = 0.0
    private var splitMarkedElapsed: TimeInterval = 0

    #if os(iOS)
    private let liveActivityPresenter = WorkoutLiveActivityPresenter()
    #endif

    override init() {
        routeRecorder = WorkoutRouteRecorder(healthStore: healthStore)
        super.init()
    }

    init(routeRecorder: any WorkoutRouteRecording) {
        self.routeRecorder = routeRecorder
        super.init()
    }

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
        stepper = WorkoutStepper(blueprint: blueprint, manualTreadmill: blueprint.location == .treadmill)
        configureTreadmillIfNeeded(for: blueprint)
        cuePolicy = CuePolicy()
        speech.isEnabled = cuesEnabled
        speech.cueStyle = cueStyle
        speech.activateSession()
        pausedDuration = 0
        pauseStartedAt = nil
        recordedSplits = []
        splitMarkedDistance = 0
        splitMarkedElapsed = 0
        try await requestAuthorization()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = blueprint.location == .outdoor ? .outdoor : .indoor

        #if os(iOS)
        if WCSessionBridge.isWatchAppInstalled {
            launchState = .waitingForWatch
            do {
                try await startWatchApp(configuration)
            } catch {
                launchState = .failed(error.localizedDescription)
                throw error
            }
            return
        }
        #endif

        try await beginCountdownThenStart(configuration: configuration)
    }

    func startOnPhoneOnly(blueprint: WorkoutBlueprint, zones: PaceZones?) async throws {
        if isRunning { return }
        self.blueprint = blueprint
        self.zones = zones
        stepper = WorkoutStepper(blueprint: blueprint, manualTreadmill: blueprint.location == .treadmill)
        configureTreadmillIfNeeded(for: blueprint)
        cuePolicy = CuePolicy()
        speech.isEnabled = cuesEnabled
        speech.cueStyle = cueStyle
        speech.activateSession()
        pausedDuration = 0
        pauseStartedAt = nil
        recordedSplits = []
        splitMarkedDistance = 0
        splitMarkedElapsed = 0
        try await requestAuthorization()
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = blueprint.location == .outdoor ? .outdoor : .indoor
        try await beginCountdownThenStart(configuration: configuration)
    }

    func cancelPendingLaunch() {
        guard !isRunning else { return }
        blueprint = nil
        stepper = nil
        launchState = .idle
        sessionState = .preparing
    }

    private func beginCountdownThenStart(configuration: HKWorkoutConfiguration) async throws {
        sessionState = .countdown
        publishSnapshot()
        #if os(iOS)
        let skipCountdown = UIAccessibility.isReduceMotionEnabled
        #else
        let skipCountdown = false
        #endif
        if !skipCountdown {
            try await Task.sleep(for: .seconds(3))
        }
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
        launchState = .recording
        startedAt = Date()
        #if os(iOS)
        startLiveActivity()
        #endif
    }

    func pause() {
        session?.pause()
        isPaused = true
        routeRecorder.setRecording(false)
        if !applyingRemote { send(.pause) }
    }

    func resume() {
        session?.resume()
        isPaused = false
        routeRecorder.setRecording(true)
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
        launchState = .recording
        sessionState = .recording
        publishSnapshot()
        routeRecorder.begin(for: blueprint?.location ?? .outdoor)
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
            heartRate: metrics.heartRate,
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
        sessionState = .finishing
        publishSnapshot()
        let end = Date()
        routeRecorder.stop()
        var localResult: WorkoutResult?
        if let blueprint {
            let duration = activeElapsed(at: end)
            let distance = resolvedDistanceMeters()
            let pace = distance > 0 ? (duration / distance) * 1_000 : nil
            localResult = WorkoutResult(
                workoutID: blueprint.id,
                startedAt: startedAt ?? end,
                duration: duration,
                distanceMeters: resolvedDistanceMeters(),
                averagePaceSecPerKm: pace,
                heartRateAverage: metrics.heartRate,
                location: blueprint.location,
                source: resultSource,
                healthSync: HealthSyncMetadata(state: .pending, lastAttemptAt: end)
            )
            onFinished?(localResult!)
            sessionState = .saved
        }
        do {
            try await builder?.endCollection(at: end)
            guard let workout = try await builder?.finishWorkout() else { throw HKError(.errorHealthDataUnavailable) }
            let fullRoute = (try? await routeRecorder.finish(for: workout)) ?? []
            let route = RouteSampler.displayRoute(from: fullRoute)
            if var result = localResult {
                var splits = recordedSplits
                if splits.isEmpty, !route.isEmpty {
                    splits = SplitBuilder.fromRoute(route, unit: splitUnit)
                }
                result.healthKitUUID = workout.uuid
                result.route = route.isEmpty ? nil : route
                result.splits = splits.isEmpty ? nil : splits
                result.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: workout.uuid)
                onFinished?(result)
            }
        } catch {
            sessionState = .healthSyncPending
            if var result = localResult {
                result.healthSync = HealthSyncMetadata(state: .failed, failureMessage: error.localizedDescription, lastAttemptAt: end)
                onFinished?(result)
            } else {
                onFailure?(error)
            }
        }
        publishSnapshot(clear: true)
        launchState = .idle
        sessionState = .saved
        #if os(iOS)
        await liveActivityPresenter.end()
        #endif
    }

    private func publishSnapshot(clear: Bool = false) {
        guard let blueprint, let data = try? JSONEncoder().encode(blueprint) else { return }
        if clear {
            onSnapshot?(ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: data,
                source: .wrathspeedPhone,
                state: sessionState,
                updatedAt: Date()
            ))
            return
        }
        onSnapshot?(ActiveSessionSnapshot(
            workoutID: blueprint.id,
            blueprintData: data,
            source: .wrathspeedPhone,
            state: sessionState,
            startedAt: startedAt,
            elapsedSeconds: metrics.elapsed,
            distanceMeters: metrics.distanceMeters,
            stepIndex: stepper?.stepIndex ?? 0,
            isPaused: isPaused
        ))
    }

    private func activeElapsed(at date: Date) -> TimeInterval {
        let pausedNow = pauseStartedAt.map { date.timeIntervalSince($0) } ?? 0
        return max(0, date.timeIntervalSince(startedAt ?? date) - pausedDuration - pausedNow)
    }

    #if os(iOS)
    private func startLiveActivity() {
        let attributes = WorkoutActivityAttributes(workoutName: blueprint?.title ?? "Run")
        let state = activityState()
        liveActivityPresenter.start(attributes: attributes, state: state)
    }

    private func updateLiveActivity() {
        let state = activityState()
        liveActivityPresenter.update(state: state)
    }

    private func activityState() -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            title: blueprint?.title ?? "Run",
            stepName: stepper?.currentStep?.name ?? "",
            elapsed: metrics.elapsed,
            distanceMeters: metrics.distanceMeters,
            paceSecPerKm: metrics.currentPaceSecPerKm,
            isPaused: isPaused,
            distanceUnitRaw: splitUnit.rawValue
        )
    }
    #endif
}

extension WorkoutSessionController: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            isPaused = toState == .paused
            routeRecorder.setRecording(toState == .running)
            if toState == .paused { pauseStartedAt = date }
            if toState == .running, let pauseStartedAt {
                pausedDuration += date.timeIntervalSince(pauseStartedAt)
                self.pauseStartedAt = nil
            }
            if toState == .ended {
                await finishIfNeeded()
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            routeRecorder.stop()
            isRunning = false
            launchState = .failed(error.localizedDescription)
            onFailure?(error)
        }
    }

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
                        currentPaceSecPerKm: message.paceSecPerKm,
                        heartRate: message.heartRate
                    )
                    captureSplitsIfNeeded()
                }
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            let distance = workoutBuilder.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meter()) ?? metrics.distanceMeters
            let elapsed = activeElapsed(at: Date())
            let pace: Double? = {
                if let speed = workoutBuilder.statistics(for: HKQuantityType(.runningSpeed))?
                    .mostRecentQuantity()?.doubleValue(for: HKUnit.meter().unitDivided(by: .second())),
                   speed > 0 {
                    return 1_000 / speed
                }
                if distance > 0, elapsed > 0 { return (elapsed / distance) * 1_000 }
                return nil
            }()
            let heartRate = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?
                .mostRecentQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
            metrics = LiveMetrics(
                elapsed: elapsed,
                distanceMeters: distance,
                currentPaceSecPerKm: pace,
                heartRate: heartRate ?? metrics.heartRate
            )
            captureSplitsIfNeeded()
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

    private func captureSplitsIfNeeded() {
        let captured = SplitBuilder.nextSplits(
            previousCount: recordedSplits.count,
            previousDistance: splitMarkedDistance,
            previousElapsed: splitMarkedElapsed,
            currentDistance: metrics.distanceMeters,
            currentElapsed: metrics.elapsed,
            unit: splitUnit
        )
        recordedSplits.append(contentsOf: captured.splits)
        splitMarkedDistance = captured.distance
        splitMarkedElapsed = captured.elapsed
    }

    func setTreadmillTargetSpeed(metersPerSecond: Double) {
        treadmillTargetSpeedMetersPerSecond = metersPerSecond
    }

    func applyActualTreadmillDistance(_ meters: Double) {
        pendingActualTreadmillDistance = meters
    }

    func estimatedTreadmillDistanceMeters() -> Double {
        guard usesManualTreadmillDistance, let speed = treadmillTargetSpeedMetersPerSecond else {
            return metrics.distanceMeters
        }
        return speed * metrics.elapsed
    }

    private func configureTreadmillIfNeeded(for blueprint: WorkoutBlueprint) {
        usesManualTreadmillDistance = blueprint.location == .treadmill
        pendingActualTreadmillDistance = nil
        if usesManualTreadmillDistance {
            treadmillTargetSpeedMetersPerSecond = 2.777
        }
    }

    private func resolvedDistanceMeters() -> Double {
        if let actual = pendingActualTreadmillDistance { return actual }
        if usesManualTreadmillDistance { return estimatedTreadmillDistanceMeters() }
        return metrics.distanceMeters
    }
}
