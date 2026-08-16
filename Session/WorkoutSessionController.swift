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
    private var activeStartupID: UInt?
    private var pendingStartup: PendingStartup?

    private struct PendingStartup {
        let session: HKWorkoutSession
        let builder: HKLiveWorkoutBuilder
    }

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
        guard !isRunning, sessionState != .finishing else { return }
        activeStartupID = nextStartupID()
        let startupID = activeStartupID
        defer {
            if activeStartupID == startupID {
                activeStartupID = nil
            }
        }
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
        guard isStartupActive(startupID) else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = blueprint.location == .outdoor ? .outdoor : .indoor

        #if os(iOS)
        if WCSessionBridge.isWatchAppInstalled {
            launchState = .waitingForWatch
            do {
                try await startWatchApp(configuration)
            } catch {
                guard isStartupActive(startupID) else { return }
                launchState = .failed(error.localizedDescription)
                throw error
            }
            return
        }
        #endif

        try await beginCountdownThenStart(configuration: configuration, startupID: startupID)
    }

    func startOnPhoneOnly(blueprint: WorkoutBlueprint, zones: PaceZones?) async throws {
        guard !isRunning, sessionState != .finishing else { return }
        activeStartupID = nextStartupID()
        let startupID = activeStartupID
        defer {
            if activeStartupID == startupID {
                activeStartupID = nil
            }
        }
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
        guard isStartupActive(startupID) else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = blueprint.location == .outdoor ? .outdoor : .indoor
        try await beginCountdownThenStart(configuration: configuration, startupID: startupID)
    }

    func cancelPendingLaunch() {
        invalidateStartup()
        guard !isRunning else { return }
        discardPendingStartup()
        guard sessionState != .finishing else { return }
        clearPendingLaunchState()
    }

    private var nextStartupToken: UInt = 0

    private func nextStartupID() -> UInt {
        nextStartupToken &+= 1
        return nextStartupToken
    }

    private func invalidateStartup() {
        nextStartupToken &+= 1
        activeStartupID = nil
    }

    private func isStartupActive(_ startupID: UInt?) -> Bool {
        guard let startupID else { return false }
        return activeStartupID == startupID && !Task.isCancelled
    }

    private func beginCountdownThenStart(configuration: HKWorkoutConfiguration, startupID: UInt?) async throws {
        guard isStartupActive(startupID) else { return }
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
        guard isStartupActive(startupID) else { return }
        try await startPrimary(configuration: configuration, startupID: startupID)
    }

    private func clearPendingLaunchState() {
        blueprint = nil
        stepper = nil
        launchState = .idle
        sessionState = .preparing
    }

    @discardableResult
    private func discardIfStartupInactive(
        _ startupID: UInt?,
        session sessionToDiscard: HKWorkoutSession,
        builder builderToDiscard: HKLiveWorkoutBuilder
    ) -> Bool {
        guard !isStartupActive(startupID) else { return false }
        discardMatchingPendingStartup(sessionToDiscard, builder: builderToDiscard)
        if pendingStartup == nil, activeStartupID == nil, !isRunning, sessionState != .finishing {
            clearPendingLaunchState()
        }
        return true
    }

    /// Discards this pair if it is still the pending startup. Returns true when startup was cancelled/stale.
    private func discardPendingStartupForFailure(
        _ startupID: UInt?,
        session sessionToDiscard: HKWorkoutSession,
        builder builderToDiscard: HKLiveWorkoutBuilder
    ) -> Bool {
        let cancelled = !isStartupActive(startupID)
        discardMatchingPendingStartup(sessionToDiscard, builder: builderToDiscard)
        if cancelled, pendingStartup == nil, activeStartupID == nil, !isRunning, sessionState != .finishing {
            clearPendingLaunchState()
        }
        return cancelled
    }

    private func discardMatchingPendingStartup(
        _ sessionToDiscard: HKWorkoutSession,
        builder builderToDiscard: HKLiveWorkoutBuilder
    ) {
        guard pendingStartup?.session === sessionToDiscard else { return }
        pendingStartup = nil
        discardPartialSession(sessionToDiscard, builder: builderToDiscard)
    }

    private func discardPendingStartup() {
        guard let pending = pendingStartup else { return }
        pendingStartup = nil
        discardPartialSession(pending.session, builder: pending.builder)
    }

    /// Discards a cancelled HealthKit startup. Does not save an `HKWorkout`.
    /// Normal completion uses `endCollection` + `finishWorkout` in `finishIfNeeded()`.
    private func discardPartialSession(
        _ sessionToDiscard: HKWorkoutSession,
        builder builderToDiscard: HKLiveWorkoutBuilder
    ) {
        switch sessionToDiscard.state {
        case .running, .paused:
            sessionToDiscard.stopActivity(with: Date())
        default:
            break
        }
        builderToDiscard.discardWorkout()
        if sessionToDiscard.state != .ended {
            sessionToDiscard.end()
        }
    }

    var canAcceptMirroredSession: Bool {
        !isRunning
            && session == nil
            && pendingStartup == nil
            && sessionState != .finishing
            && sessionState != .countdown
            && sessionState != .recording
    }

    @discardableResult
    func attachMirrored(session incoming: HKWorkoutSession) async -> Bool {
        guard canAcceptMirroredSession else { return false }
        isPrimary = false
        self.session = incoming
        builder = incoming.associatedWorkoutBuilder()
        incoming.delegate = self
        builder?.delegate = self
        builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: incoming.workoutConfiguration)
        isRunning = true
        launchState = .recording
        sessionState = .recording
        startedAt = Date()
        #if os(iOS)
        startLiveActivity()
        #endif
        return true
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
        let sessionToEnd = session
        if !applyingRemote {
            send(.end, through: sessionToEnd)
        }
        sessionToEnd?.stopActivity(with: Date())
        sessionToEnd?.end()
        await finishIfNeeded()
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

    private func startPrimary(configuration: HKWorkoutConfiguration, startupID: UInt?) async throws {
        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
        discardPendingStartup()
        pendingStartup = PendingStartup(session: session, builder: builder)
        let start = Date()
        #if os(watchOS)
        do {
            try await session.startMirroringToCompanionDevice()
        } catch {
            if discardPendingStartupForFailure(startupID, session: session, builder: builder) { return }
            throw error
        }
        if discardIfStartupInactive(startupID, session: session, builder: builder) { return }
        #endif
        session.startActivity(with: start)
        do {
            try await builder.beginCollection(at: start)
        } catch {
            if discardPendingStartupForFailure(startupID, session: session, builder: builder) { return }
            throw error
        }
        if discardIfStartupInactive(startupID, session: session, builder: builder) { return }
        pendingStartup = nil
        self.session = session
        self.builder = builder
        startedAt = start
        isPrimary = true
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
                events: events,
                splitUnit: splitUnit
            )
            lastCues.forEach(speech.speak)
            return
        }
        lastCues = cuePolicy.evaluate(
            step: step,
            usesPaceTargets: blueprint?.usesPaceTargets ?? false,
            zones: zones,
            metrics: metrics,
            events: events,
            splitUnit: splitUnit
        )
        lastCues.forEach(speech.speak)
    }

    private func send(_ kind: SessionSyncMessage.Kind, through target: HKWorkoutSession? = nil) {
        let destination = target ?? session
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
        if let data = message.encoded(), let destination {
            Task {
                try? await destination.sendToRemoteWorkoutSession(data: data)
            }
        }
        #if os(iOS)
        updateLiveActivity()
        #endif
    }

    private func finishIfNeeded() async {
        guard isRunning, sessionState != .finishing else { return }
        guard let finishingSession = session, let finishingBuilder = builder else { return }
        isRunning = false
        sessionState = .finishing
        publishSnapshot()
        let end = Date()
        routeRecorder.stop()
        let finishingBlueprint = blueprint
        let finishingStartedAt = startedAt
        let finishingSplits = recordedSplits
        let finishingSplitUnit = splitUnit
        let finishingSource = resultSource
        let finishingHeartRate = metrics.heartRate
        let duration = activeElapsed(at: end)
        let distance = resolvedDistanceMeters()
        var localResult: WorkoutResult?
        if let finishingBlueprint {
            let pace = distance > 0 ? (duration / distance) * 1_000 : nil
            localResult = WorkoutResult(
                workoutID: finishingBlueprint.id,
                startedAt: finishingStartedAt ?? end,
                duration: duration,
                distanceMeters: distance,
                averagePaceSecPerKm: pace,
                heartRateAverage: finishingHeartRate,
                location: finishingBlueprint.location,
                source: finishingSource,
                healthSync: HealthSyncMetadata(state: .pending, lastAttemptAt: end)
            )
            onFinished?(localResult!)
        }
        do {
            try await finishingBuilder.endCollection(at: end)
            guard let workout = try await finishingBuilder.finishWorkout() else { throw HKError(.errorHealthDataUnavailable) }
            let fullRoute = (try? await routeRecorder.finish(for: workout)) ?? []
            let route = RouteSampler.displayRoute(from: fullRoute)
            if var result = localResult {
                var splits = finishingSplits
                if splits.isEmpty, !route.isEmpty {
                    splits = SplitBuilder.fromRoute(route, unit: finishingSplitUnit)
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
        if session === finishingSession {
            session = nil
            startedAt = nil
        }
        if builder === finishingBuilder {
            builder = nil
        }
        publishSnapshot(clear: true)
        launchState = .idle
        sessionState = .saved
        #if os(iOS)
        await liveActivityPresenter.end()
        #endif
    }

    private func publishSnapshot(clear: Bool = false) {
        guard let snapshot = makeActiveSessionSnapshot(clear: clear) else { return }
        onSnapshot?(snapshot)
    }

    private func makeActiveSessionSnapshot(clear: Bool = false) -> ActiveSessionSnapshot? {
        guard let blueprint, let data = try? JSONEncoder().encode(blueprint) else { return nil }
        if clear {
            return ActiveSessionSnapshot(
                workoutID: blueprint.id,
                blueprintData: data,
                source: resultSource,
                state: sessionState,
                updatedAt: Date()
            )
        }
        return ActiveSessionSnapshot(
            workoutID: blueprint.id,
            blueprintData: data,
            source: resultSource,
            state: sessionState,
            startedAt: startedAt,
            elapsedSeconds: metrics.elapsed,
            distanceMeters: metrics.distanceMeters,
            stepIndex: stepper?.stepIndex ?? 0,
            isPaused: isPaused
        )
    }

    #if DEBUG
    func testing_publishSnapshot(clear: Bool = false) {
        publishSnapshot(clear: clear)
    }

    func testing_configureSnapshot(
        blueprint: WorkoutBlueprint,
        source: WorkoutSource,
        state: ActiveSessionState = .recording
    ) {
        self.blueprint = blueprint
        self.resultSource = source
        self.sessionState = state
    }
    #endif

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
            guard session === workoutSession else { return }
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
            guard session === workoutSession else { return }
            routeRecorder.stop()
            isRunning = false
            launchState = .failed(error.localizedDescription)
            onFailure?(error)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            guard session === workoutSession else { return }
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
            guard builder === workoutBuilder else { return }
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
