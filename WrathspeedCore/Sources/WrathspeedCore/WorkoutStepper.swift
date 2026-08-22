import Foundation

public struct LiveMetrics: Equatable, Sendable {
    public var elapsed: TimeInterval
    public var distanceMeters: Double
    public var currentPaceSecPerKm: Double?
    public var heartRate: Double?

    public init(
        elapsed: TimeInterval,
        distanceMeters: Double,
        currentPaceSecPerKm: Double? = nil,
        heartRate: Double? = nil
    ) {
        self.elapsed = elapsed
        self.distanceMeters = distanceMeters
        self.currentPaceSecPerKm = currentPaceSecPerKm
        self.heartRate = heartRate
    }
}

public enum StepEvent: Equatable, Sendable {
    case started(index: Int, step: WorkoutStep)
    case completed(index: Int, step: WorkoutStep)
    case finished
}

public struct WorkoutStepper: Equatable, Sendable {
    public var blueprint: WorkoutBlueprint
    public var stepIndex: Int
    public var stepStartElapsed: TimeInterval
    public var stepStartDistance: Double
    public var isComplete: Bool
    public var manualTreadmill: Bool

    /// Whether the opening step's `.started` event has already been emitted.
    ///
    /// `update` is driven by HealthKit's data callbacks, so it runs many times inside a single
    /// step. It used to infer "not begun yet" from `stepStartElapsed == 0 && stepStartDistance
    /// == 0`, which those callbacks never clear -- so it re-announced step 0 on every one of
    /// them, and the live session spoke the first step's name on a loop. On a treadmill, where
    /// a distance step never auto-advances, that loop had no end.
    public private(set) var hasBegun: Bool

    public init(blueprint: WorkoutBlueprint, manualTreadmill: Bool = false) {
        self.blueprint = blueprint
        self.stepIndex = 0
        self.stepStartElapsed = 0
        self.stepStartDistance = 0
        self.isComplete = blueprint.steps.isEmpty
        self.manualTreadmill = manualTreadmill
        self.hasBegun = false
    }

    public var currentStep: WorkoutStep? {
        guard !isComplete, blueprint.steps.indices.contains(stepIndex) else { return nil }
        return blueprint.steps[stepIndex]
    }

    public mutating func skipCurrent(metrics: LiveMetrics) -> [StepEvent] {
        guard !isComplete, let step = currentStep else { return [] }
        // Skipping is itself a start, so a later `update` must not announce step 0 after it.
        hasBegun = true
        var events: [StepEvent] = [.completed(index: stepIndex, step: step)]
        stepIndex += 1
        stepStartElapsed = metrics.elapsed
        stepStartDistance = metrics.distanceMeters
        if let next = currentStep {
            events.append(.started(index: stepIndex, step: next))
        } else {
            isComplete = true
            events.append(.finished)
        }
        return events
    }

    public mutating func update(metrics: LiveMetrics) -> [StepEvent] {
        guard !isComplete else { return [] }
        var events: [StepEvent] = []
        if !hasBegun, let first = currentStep {
            hasBegun = true
            events.append(.started(index: stepIndex, step: first))
        }

        while !isComplete, let step = currentStep, targetReached(step: step, metrics: metrics) {
            events.append(.completed(index: stepIndex, step: step))
            stepIndex += 1
            stepStartElapsed = metrics.elapsed
            stepStartDistance = metrics.distanceMeters
            if let next = currentStep {
                events.append(.started(index: stepIndex, step: next))
            } else {
                isComplete = true
                events.append(.finished)
            }
        }
        return events
    }

    private func targetReached(step: WorkoutStep, metrics: LiveMetrics) -> Bool {
        if manualTreadmill {
            switch step.target {
            case .duration: break
            case .distance: return false
            }
        }
        switch step.target {
        case .distance(let meters):
            return (metrics.distanceMeters - stepStartDistance) >= meters
        case .duration(let seconds):
            return (metrics.elapsed - stepStartElapsed) >= seconds
        }
    }

    public func remainingInStep(metrics: LiveMetrics) -> TimeInterval? {
        guard let step = currentStep else { return nil }
        switch step.target {
        case .duration(let seconds):
            return max(0, seconds - (metrics.elapsed - stepStartElapsed))
        case .distance(let meters):
            let done = metrics.distanceMeters - stepStartDistance
            let leftover = max(0, meters - done)
            guard let pace = metrics.currentPaceSecPerKm, pace > 0 else { return nil }
            return leftover / 1_000 * pace
        }
    }
}
