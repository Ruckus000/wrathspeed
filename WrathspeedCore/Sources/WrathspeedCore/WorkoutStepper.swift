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

    public init(blueprint: WorkoutBlueprint, manualTreadmill: Bool = false) {
        self.blueprint = blueprint
        self.stepIndex = 0
        self.stepStartElapsed = 0
        self.stepStartDistance = 0
        self.isComplete = blueprint.steps.isEmpty
        self.manualTreadmill = manualTreadmill
    }

    public var currentStep: WorkoutStep? {
        guard !isComplete, blueprint.steps.indices.contains(stepIndex) else { return nil }
        return blueprint.steps[stepIndex]
    }

    public mutating func skipCurrent(metrics: LiveMetrics) -> [StepEvent] {
        guard !isComplete, let step = currentStep else { return [] }
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
        if stepIndex == 0, stepStartElapsed == 0, stepStartDistance == 0, let first = currentStep, metrics.elapsed >= 0 {
            events.append(.started(index: 0, step: first))
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
