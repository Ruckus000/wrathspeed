import Foundation

public enum Cue: Equatable, Sendable {
    case stepStarted(String)
    case stepCompleted(String)
    case speedUp
    case slowDown
    case split(index: Int, unit: DistanceUnit, paceSecPerKm: Double)
}

public struct CuePolicy: Equatable, Sendable {
    public var offTargetHold: TimeInterval
    public var silenceAfterCue: TimeInterval
    public var paceTolerance: Double

    private var lastPaceCueAt: TimeInterval?
    private var offTargetSince: TimeInterval?
    private var lastSplitIndex: Int
    private var lastMarkedDistance: Double

    public init(
        offTargetHold: TimeInterval = 20,
        silenceAfterCue: TimeInterval = 60,
        paceTolerance: Double = 0.05
    ) {
        self.offTargetHold = offTargetHold
        self.silenceAfterCue = silenceAfterCue
        self.paceTolerance = paceTolerance
        self.lastPaceCueAt = nil
        self.offTargetSince = nil
        self.lastSplitIndex = 0
        self.lastMarkedDistance = 0
    }

    public mutating func evaluate(
        step: WorkoutStep?,
        usesPaceTargets: Bool,
        zones: PaceZones?,
        metrics: LiveMetrics,
        events: [StepEvent],
        splitUnit: DistanceUnit = .kilometers
    ) -> [Cue] {
        var cues: [Cue] = []
        for event in events {
            switch event {
            case .started(_, let step):
                cues.append(.stepStarted(step.name))
            case .completed(_, let step):
                cues.append(.stepCompleted(step.name))
            case .finished:
                cues.append(.stepCompleted("Workout"))
            }
        }

        var splitIndex = lastSplitIndex
        var markedDistance = lastMarkedDistance
        while let segmentDistance = SplitBoundary.nextSegmentDistance(
            markedDistance: markedDistance,
            currentDistance: metrics.distanceMeters,
            unit: splitUnit
        ) {
            splitIndex += 1
            guard let pace = metrics.currentPaceSecPerKm else { break }
            cues.append(.split(index: splitIndex, unit: splitUnit, paceSecPerKm: pace))
            markedDistance += segmentDistance
            lastSplitIndex = splitIndex
            lastMarkedDistance = markedDistance
        }

        guard usesPaceTargets,
              let step,
              case .zone(let zone) = step.intensity,
              zone != .recovery,
              let target = zones?.secondsPerKilometer(for: zone),
              let current = metrics.currentPaceSecPerKm,
              current > 0
        else {
            offTargetSince = nil
            return cues
        }

        let fastLimit = target * (1 - paceTolerance)
        let slowLimit = target * (1 + paceTolerance)
        let tooFast = current < fastLimit
        let tooSlow = current > slowLimit

        if tooFast || tooSlow {
            if offTargetSince == nil {
                offTargetSince = metrics.elapsed
            }
            let held = metrics.elapsed - (offTargetSince ?? metrics.elapsed)
            let silenced = lastPaceCueAt.map { metrics.elapsed - $0 < silenceAfterCue } ?? false
            if held >= offTargetHold, !silenced {
                // Lower sec/km = faster than target → slow down.
                cues.append(tooFast ? .slowDown : .speedUp)
                lastPaceCueAt = metrics.elapsed
                offTargetSince = metrics.elapsed
            }
        } else {
            offTargetSince = nil
        }

        return cues
    }
}
