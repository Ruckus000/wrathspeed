import Foundation

public enum SplitBuilder {
    public static func fromRoute(_ points: [RoutePoint], unit: DistanceUnit) -> [WorkoutSplit] {
        guard points.count >= 2 else { return [] }
        let unitMeters = Units.splitDistance(for: unit)
        var splits: [WorkoutSplit] = []
        var cumulative = 0.0
        var markedDistance = 0.0
        var markedTime = points[0].timestamp
        var index = 0

        for i in 1..<points.count {
            cumulative += meters(from: points[i - 1], to: points[i])
            while cumulative - markedDistance >= unitMeters * 0.95 {
                index += 1
                let duration = points[i].timestamp.timeIntervalSince(markedTime)
                let distance = min(unitMeters, cumulative - markedDistance)
                guard distance > 0, duration > 0 else { break }
                let pace = (duration / distance) * 1_000
                splits.append(
                    WorkoutSplit(index: index, distanceMeters: distance, duration: duration, paceSecPerKm: pace)
                )
                markedDistance += distance
                markedTime = points[i].timestamp
            }
        }
        return splits
    }

    public static func nextSplits(
        previousCount: Int,
        previousDistance: Double,
        previousElapsed: TimeInterval,
        currentDistance: Double,
        currentElapsed: TimeInterval,
        unit: DistanceUnit
    ) -> (splits: [WorkoutSplit], distance: Double, elapsed: TimeInterval) {
        let unitMeters = Units.splitDistance(for: unit)
        var splits: [WorkoutSplit] = []
        var markedDistance = previousDistance
        var markedElapsed = previousElapsed
        var index = previousCount
        while currentDistance - markedDistance >= unitMeters * 0.95 {
            index += 1
            let distance = min(unitMeters, currentDistance - markedDistance)
            let fraction = distance / max(currentDistance - markedDistance, 1)
            let duration = max(1, (currentElapsed - markedElapsed) * fraction)
            let pace = (duration / distance) * 1_000
            splits.append(
                WorkoutSplit(index: index, distanceMeters: distance, duration: duration, paceSecPerKm: pace)
            )
            markedDistance += distance
            markedElapsed += duration
        }
        return (splits, markedDistance, markedElapsed)
    }

    private static func meters(from a: RoutePoint, to b: RoutePoint) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * 6_371_000 * asin(min(1, sqrt(h)))
    }
}
