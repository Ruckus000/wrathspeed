import Foundation

/// Shared split-boundary rule for live cues and recorded splits.
public enum SplitBoundary {
    public static let tolerance = 0.95

    public static func nextSegmentDistance(
        markedDistance: Double,
        currentDistance: Double,
        unit: DistanceUnit
    ) -> Double? {
        let unitMeters = Units.splitDistance(for: unit)
        guard currentDistance - markedDistance >= unitMeters * tolerance else { return nil }
        return min(unitMeters, currentDistance - markedDistance)
    }
}
