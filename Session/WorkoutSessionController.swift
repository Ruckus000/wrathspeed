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
    private var pendingPreflightTreadmillSpeed: Double?

    func preparePreflightTreadmill(blueprint: WorkoutBlueprint, speedMetersPerSecond: Double?) {
        pendingPreflightTreadmillSpeed = speedMetersPerSecond
    }

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
    private var startupAttemptID: String?
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

    func start(blueprint: WorkoutBlueprint, zones: PaceZones?, treadmillSpeedMetersPerSecond: Double? = nil) async throws {
        guard !isRunning, sessionState != .finishing else { return }
        #if DEBUG && os(iOS)
        if UITestingSupport.shouldSimulateLiveRecording {
            try await beginSimulatedLiveRecording(
                blueprint: blueprint,
                zones: zones,
                treadmillSpeedMetersPerSecond: treadmillSpeedMetersPerSecond
            )
            return
        }
        #endif
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
        configureTreadmillIfNeeded(for: blueprint, treadmillSpeed: treadmillSpeedMetersPerSecond)
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
        guard mayContinueStartup(startupID) else {
            try handleInactiveStartupBeforeCountdown(startupID: startupID)
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = blueprint.location == .outdoor ? .outdoor : .indoor

        #if os(iOS)
        if WCSessionBridge.isWatchAppInstalled {
            launchState = .waitingForWatch
            do {
                try await startWatchApp(configuration)
            } catch {
                guard mayContinueStartup(startupID) else {
                    try handleInactiveStartupBeforeCountdown(startupID: startupID)
                    return
                }
                launchState = .failed(error.localizedDescription)
                throw error
            }
            return
        }
        #endif

        try await beginCountdownThenStart(configuration: configuration, startupID: startupID)
    }

    #if DEBUG && os(iOS)
    private func beginSimulatedLiveRecording(
        blueprint: WorkoutBlueprint,
        zones: PaceZones?,
        treadmillSpeedMetersPerSecond: Double? = nil
    ) async throws {
        self.blueprint = blueprint
        self.zones = zones
        stepper = WorkoutStepper(blueprint: blueprint, manualTreadmill: blueprint.location == .treadmill)
        configureTreadmillIfNeeded(for: blueprint, treadmillSpeed: treadmillSpeedMetersPerSecond)
        cuePolicy = CuePolicy()
        speech.isEnabled = false
        pausedDuration = 0
        pauseStartedAt = nil
        recordedSplits = []
        splitMarkedDistance = 0
        splitMarkedElapsed = 0
        startedAt = Date()
        isRunning = true
        launchState = .recording
        sessionState = .recording
        isPaused = false
        publishSnapshot()
    }

    private func finishSimulatedLiveRecording(blueprint: WorkoutBlueprint) {
        let end = Date()
        let duration = activeElapsed(at: end)
        let distance = resolvedDistanceMeters()
        let pace = distance > 0 ? (duration / distance) * 1_000 : nil
        let result = WorkoutResult(
            workoutID: blueprint.id,
            startedAt: startedAt ?? end,
            duration: duration,
            distanceMeters: distance,
            averagePaceSecPerKm: pace,
            location: blueprint.location,
            source: resultSource,
            healthSync: HealthSyncMetadata(state: .notRequired)
        )
        isRunning = false
        sessionState = .saved
        launchState = .idle
        onFinished?(result)
        publishSnapshot(clear: true)
        self.blueprint = nil
        self.stepper = nil
        startedAt = nil
    }
    #endif

    func startOnPhoneOnly(
        blueprint: WorkoutBlueprint,
        zones: PaceZones?,
        treadmillSpeedMetersPerSecond: Double? = nil
    ) async throws {
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
        configureTreadmillIfNeeded(for: blueprint, treadmillSpeed: treadmillSpeedMetersPerSecond)
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
        guard mayContinueStartup(startupID) else {
            try handleInactiveStartupBeforeCountdown(startupID: startupID)
            return
        }
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
        emitTerminalStartupClearIfNeeded()
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

    private func ownsStartup(_ startupID: UInt?) -> Bool {
        guard let startupID else { return false }
        return activeStartupID == startupID
    }

    private func mayContinueStartup(_ startupID: UInt?) -> Bool {
        ownsStartup(startupID) && !Task.isCancelled
    }

    private func beginCountdownThenStart(configuration: HKWorkoutConfiguration, startupID: UInt?) async throws {
        guard mayContinueStartup(startupID) else {
            try handleInactiveStartupBeforeCountdown(startupID: startupID)
            return
        }
        try await runPostCountdownStartup(configuration: configuration, startupID: startupID)
    }

    private func handleInactiveStartupBeforeCountdown(startupID: UInt?) throws {
        guard ownsStartup(startupID) else { return }
        cleanupOwnedStartupFailure(startupID: startupID)
        try Task.checkCancellation()
    }

    private func newStartupAttemptID() -> String {
        UUID().uuidString
    }

    private func runPostCountdownStartup(configuration: HKWorkoutConfiguration, startupID: UInt?) async throws {
        guard mayContinueStartup(startupID) else {
            try handleInactiveStartupBeforeCountdown(startupID: startupID)
            return
        }
        startupAttemptID = newStartupAttemptID()
        sessionState = .countdown
        publishSnapshot()
        #if os(iOS)
        let skipCountdown = UIAccessibility.isReduceMotionEnabled
        #else
        let skipCountdown = false
        #endif
        #if DEBUG && os(iOS)
        // A separate launch argument rather than `UITestingSupport.isUITesting`: that is
        // also true for hosted unit tests, and `SessionRecoveryTests` cancels during a real
        // countdown.
        let shouldSleep = !skipCountdown && !testing_skipCountdownSleep && !UITestingSupport.shouldSkipCountdown
        #elseif DEBUG
        let shouldSleep = !skipCountdown && !testing_skipCountdownSleep
        #else
        let shouldSleep = !skipCountdown
        #endif
        do {
            if shouldSleep {
                try await Task.sleep(for: .seconds(3))
            }
            guard mayContinueStartup(startupID) else {
                try handleInactiveStartupAfterCountdown(startupID: startupID)
                return
            }
            try await startPrimary(configuration: configuration, startupID: startupID)
        } catch {
            try handleOwnedPostCountdownError(startupID: startupID, error: error)
        }
    }

    private func handleInactiveStartupAfterCountdown(startupID: UInt?) throws {
        guard ownsStartup(startupID) else { return }
        cleanupOwnedStartupFailure(startupID: startupID)
        try Task.checkCancellation()
    }

    private func handleOwnedPostCountdownError(startupID: UInt?, error: Error) throws {
        guard ownsStartup(startupID) else { return }
        cleanupOwnedStartupFailure(startupID: startupID)
        throw error
    }

    private func clearPendingLaunchState() {
        blueprint = nil
        stepper = nil
        launchState = .idle
        sessionState = .preparing
        startupAttemptID = nil
    }

    private func afterHealthKitStartupAwait(
        startupID: UInt?,
        session sessionCaptured: HKWorkoutSession,
        builder builderCaptured: HKLiveWorkoutBuilder
    ) throws {
        do {
            try Task.checkCancellation()
        } catch {
            discardMatchingPendingStartup(sessionCaptured, builder: builderCaptured)
            throw error
        }
        guard ownsStartup(startupID) else {
            discardMatchingPendingStartup(sessionCaptured, builder: builderCaptured)
            throw StartupSupersededError()
        }
    }

    private struct StartupSupersededError: Error {}

    private func cleanupOwnedStartupFailure(startupID: UInt?) {
        guard ownsStartup(startupID) else { return }
        guard session == nil, sessionState != .finishing else { return }
        discardPendingStartup()
        emitTerminalStartupClearIfNeeded()
        clearPendingLaunchState()
        if activeStartupID == startupID {
            activeStartupID = nil
        }
    }

    private func emitTerminalStartupClearIfNeeded() {
        guard blueprint != nil else { return }
        publishSnapshot(clear: true)
    }

    private func discardMatchingPendingStartup(
        _ sessionToDiscard: HKWorkoutSession,
        builder builderToDiscard: HKLiveWorkoutBuilder
    ) {
        guard pendingStartup?.session === sessionToDiscard else { return }
        pendingStartup = nil
        #if DEBUG
        testing_pendingStartupDiscardCount += 1
        #endif
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

    #if DEBUG
    private var testing_forcePendingStartup = false
    private var testing_forceCurrentSession = false
    private var testing_forcePrePendingStartupError: Error?
    private var testing_forceBeginCollectionError: Error?
    private var testing_skipCountdownSleep = false
    private var testing_forceFinishSessionAvailable = false
    private(set) var testing_pendingStartupDiscardCount = 0
    var testing_onPendingStartupCreated: (() -> Void)?
    #endif

    var canAcceptMirroredSession: Bool {
        #if DEBUG
        guard !isRunning,
              session == nil && !testing_forceCurrentSession,
              pendingStartup == nil && !testing_forcePendingStartup,
              sessionState != .finishing,
              sessionState != .countdown,
              sessionState != .recording else { return false }
        #else
        guard !isRunning,
              session == nil,
              pendingStartup == nil,
              sessionState != .finishing,
              sessionState != .countdown,
              sessionState != .recording else { return false }
        #endif
        if activeStartupID != nil && launchState != .waitingForWatch {
            return false
        }
        return true
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
        #if DEBUG && os(iOS)
        if UITestingSupport.shouldSimulateLiveRecording, session == nil, let finishingBlueprint = blueprint {
            finishSimulatedLiveRecording(blueprint: finishingBlueprint)
            return
        }
        #endif
        let sessionToEnd = session
        if !applyingRemote {
            await sendEndToRemote(through: sessionToEnd)
        }
        localStopEnd(sessionToEnd)
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
        #if DEBUG
        if let testing_forcePrePendingStartupError {
            throw testing_forcePrePendingStartupError
        }
        #endif
        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
        discardPendingStartup()
        pendingStartup = PendingStartup(session: session, builder: builder)
        #if DEBUG
        testing_onPendingStartupCreated?()
        #endif
        let start = Date()
        #if os(watchOS)
        do {
            try await session.startMirroringToCompanionDevice()
        } catch {
            discardMatchingPendingStartup(session, builder: builder)
            throw error
        }
        do {
            try afterHealthKitStartupAwait(startupID: startupID, session: session, builder: builder)
        } catch is StartupSupersededError {
            return
        }
        #endif
        session.startActivity(with: start)
        do {
            #if DEBUG
            if let testing_forceBeginCollectionError {
                throw testing_forceBeginCollectionError
            }
            #endif
            try await builder.beginCollection(at: start)
        } catch {
            discardMatchingPendingStartup(session, builder: builder)
            throw error
        }
        do {
            try afterHealthKitStartupAwait(startupID: startupID, session: session, builder: builder)
        } catch is StartupSupersededError {
            return
        }
        pendingStartup = nil
        self.session = session
        self.builder = builder
        startedAt = start
        startupAttemptID = nil
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

    private func endSyncMessageData() -> Data? {
        SessionSyncMessage(
            kind: .end,
            elapsed: metrics.elapsed,
            distanceMeters: metrics.distanceMeters,
            paceSecPerKm: metrics.currentPaceSecPerKm,
            heartRate: metrics.heartRate,
            stepIndex: stepper?.stepIndex ?? 0,
            stepName: stepper?.currentStep?.name ?? "",
            isPaused: isPaused
        ).encoded()
    }

    private func sendEndToRemote(through target: HKWorkoutSession?) async {
        guard let data = endSyncMessageData() else { return }
        #if DEBUG
        if target == nil && testing_remoteEndSendHandler == nil { return }
        testing_lifecyclePhases.append(.remoteEndSendStarted)
        if let handler = testing_remoteEndSendHandler {
            do {
                try await handler(data)
                testing_lifecyclePhases.append(.remoteEndSendCompleted)
            } catch {
                testing_lifecyclePhases.append(.remoteEndSendFailed)
            }
            return
        }
        #endif
        guard let target else { return }
        do {
            try await target.sendToRemoteWorkoutSession(data: data)
            #if DEBUG
            testing_lifecyclePhases.append(.remoteEndSendCompleted)
            #endif
        } catch {
            #if DEBUG
            testing_lifecyclePhases.append(.remoteEndSendFailed)
            #endif
        }
    }

    private func localStopEnd(_ sessionToEnd: HKWorkoutSession?) {
        #if DEBUG
        testing_lifecyclePhases.append(.localStopEnd)
        if testing_skipHealthKitStopEnd { return }
        #endif
        sessionToEnd?.stopActivity(with: Date())
        sessionToEnd?.end()
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

    @discardableResult
    private func beginFinishingIfNeeded() -> Bool {
        guard isRunning, sessionState != .finishing else { return false }
        #if DEBUG
        let hasFinishSession = session != nil || testing_forceFinishSessionAvailable
        let hasFinishBuilder = builder != nil || testing_forceFinishSessionAvailable
        guard hasFinishSession, hasFinishBuilder else { return false }
        #else
        guard session != nil, builder != nil else { return false }
        #endif
        isRunning = false
        sessionState = .finishing
        publishSnapshot()
        return true
    }

    private func finishIfNeeded() async {
        #if DEBUG
        if testing_skipFinishIfNeeded { return }
        #endif
        guard beginFinishingIfNeeded() else { return }
        guard let finishingSession = session, let finishingBuilder = builder else { return }
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
        return ActiveSessionSnapshot(
            workoutID: blueprint.id,
            blueprintData: data,
            source: resultSource,
            state: clear ? .saved : sessionState,
            startedAt: startedAt,
            startupAttemptID: (sessionState == .preparing || sessionState == .countdown || (clear && startupAttemptID != nil))
                ? startupAttemptID
                : nil,
            elapsedSeconds: metrics.elapsed,
            distanceMeters: resolvedDistanceMeters(),
            stepIndex: stepper?.stepIndex ?? 0,
            isPaused: isPaused,
            updatedAt: Date(),
            healthSync: localHealthSyncMetadata()
        )
    }

    private func localHealthSyncMetadata() -> HealthSyncMetadata {
        switch sessionState {
        case .healthSyncPending:
            return HealthSyncMetadata(state: .failed, lastAttemptAt: Date())
        case .saved, .finishing:
            return HealthSyncMetadata(state: .pending, lastAttemptAt: Date())
        default:
            return HealthSyncMetadata()
        }
    }

    #if DEBUG
    enum TestingLifecyclePhase: Equatable {
        case remoteEndSendStarted
        case remoteEndSendCompleted
        case remoteEndSendFailed
        case localStopEnd
    }

    var testing_lifecyclePhases: [TestingLifecyclePhase] = []
    var testing_remoteEndSendHandler: ((Data) async throws -> Void)?
    var testing_skipHealthKitStopEnd = false
    var testing_skipFinishIfNeeded = false

    func testing_finishIfNeeded() async {
        await finishIfNeeded()
    }

    @discardableResult
    func testing_beginFinishingIfNeeded() -> Bool {
        beginFinishingIfNeeded()
    }

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

    func testing_prepareForEndTest(blueprint: WorkoutBlueprint, state: ActiveSessionState = .recording) {
        self.blueprint = blueprint
        self.sessionState = state
        self.isRunning = true
        self.startedAt = Date()
    }

    func testing_configureMirroredAdmissionContext(
        launchState: LaunchState = .idle,
        sessionState: ActiveSessionState = .preparing,
        activeStartupID: UInt? = nil,
        pendingStartup: Bool = false,
        hasCurrentSession: Bool = false,
        isRunning: Bool = false
    ) {
        self.launchState = launchState
        self.sessionState = sessionState
        self.activeStartupID = activeStartupID
        testing_forcePendingStartup = pendingStartup
        testing_forceCurrentSession = hasCurrentSession
        self.pendingStartup = nil
        self.session = nil
        self.builder = nil
        self.isRunning = isRunning
    }

    func testing_mirroredAdmissionSnapshot() -> (
        launchState: LaunchState,
        sessionState: ActiveSessionState,
        isRunning: Bool,
        hasSession: Bool,
        hasPendingStartup: Bool
    ) {
        (
            launchState,
            sessionState,
            isRunning,
            session != nil || testing_forceCurrentSession,
            pendingStartup != nil || testing_forcePendingStartup
        )
    }

    @discardableResult
    func testing_beginOwnedStartup() -> UInt {
        let id = nextStartupID()
        activeStartupID = id
        return id
    }

    func testing_simulateCountdownOwnership(startupID: UInt, blueprint: WorkoutBlueprint) {
        activeStartupID = startupID
        self.blueprint = blueprint
        stepper = WorkoutStepper(blueprint: blueprint)
        startupAttemptID = newStartupAttemptID()
        sessionState = .countdown
        publishSnapshot()
    }

    func testing_publishTerminalStartupClear() {
        publishSnapshot(clear: true)
    }

    var testing_hasPendingStartup: Bool {
        pendingStartup != nil
    }

    func testing_prepareForPostCountdownStartup(startupID: UInt, blueprint: WorkoutBlueprint) {
        activeStartupID = startupID
        self.blueprint = blueprint
        stepper = WorkoutStepper(blueprint: blueprint)
        sessionState = .preparing
        testing_pendingStartupDiscardCount = 0
    }

    func testing_runPostCountdownStartup(configuration: HKWorkoutConfiguration, startupID: UInt) async throws {
        try await runPostCountdownStartup(configuration: configuration, startupID: startupID)
    }

    func testing_setForcePrePendingStartupError(_ error: Error?) {
        testing_forcePrePendingStartupError = error
    }

    func testing_setForceBeginCollectionError(_ error: Error?) {
        testing_forceBeginCollectionError = error
    }

    func testing_setSkipCountdownSleep(_ skip: Bool) {
        testing_skipCountdownSleep = skip
    }

    func testing_setForceFinishSessionAvailable(_ available: Bool) {
        testing_forceFinishSessionAvailable = available
    }

    func testing_setElapsedForTreadmillEstimation(_ elapsed: TimeInterval) {
        metrics.elapsed = elapsed
    }

    func testing_applyTreadmillConfiguration(for blueprint: WorkoutBlueprint, treadmillSpeed: Double? = nil) {
        configureTreadmillIfNeeded(for: blueprint, treadmillSpeed: treadmillSpeed)
    }

    func testing_simulateRemoteEnd() async {
        applyingRemote = true
        defer { applyingRemote = false }
        await end()
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

    private func configureTreadmillIfNeeded(for blueprint: WorkoutBlueprint, treadmillSpeed: Double? = nil) {
        usesManualTreadmillDistance = blueprint.location == .treadmill
        pendingActualTreadmillDistance = nil
        if usesManualTreadmillDistance {
            if let explicit = treadmillSpeed ?? pendingPreflightTreadmillSpeed,
               explicit.isFinite, explicit > 0 {
                treadmillTargetSpeedMetersPerSecond = explicit
            } else if let derived = WorkoutPaceTarget.treadmillSpeedMetersPerSecond(
                blueprint: blueprint,
                zones: zones
            ) {
                treadmillTargetSpeedMetersPerSecond = derived
            }
            // Else keep existing treadmillTargetSpeedMetersPerSecond (e.g. after watch timeout → start on phone).
        } else {
            treadmillTargetSpeedMetersPerSecond = nil
        }
        pendingPreflightTreadmillSpeed = nil
    }

    private func resolvedDistanceMeters() -> Double {
        if let actual = pendingActualTreadmillDistance { return actual }
        if usesManualTreadmillDistance { return estimatedTreadmillDistanceMeters() }
        return metrics.distanceMeters
    }
}
