import Foundation

public enum PaceBandStatus: Equatable, Sendable {
    case paused
    case unavailable
    case tooFast
    case inZone
    case tooSlow

    public static let defaultTolerance = 0.05

    /// Lower seconds-per-distance is faster. A value below `target * (1 - tolerance)` is too fast.
    public static func evaluate(
        currentPaceSecPerKm: Double?,
        targetSecPerKm: Double?,
        paused: Bool,
        tolerance: Double = defaultTolerance
    ) -> PaceBandStatus {
        if paused { return .paused }
        guard let current = currentPaceSecPerKm, let target = targetSecPerKm, current > 0, target > 0 else {
            return .unavailable
        }
        let fastLimit = target * (1 - tolerance)
        let slowLimit = target * (1 + tolerance)
        if current < fastLimit { return .tooFast }
        if current > slowLimit { return .tooSlow }
        return .inZone
    }
}
