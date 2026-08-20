import Foundation

public enum SplitBuilder {
    public static func fromRoute(_ points: [RoutePoint], unit: DistanceUnit) -> [WorkoutSplit] {
        guard points.count >= 2 else { return [] }
        var splits: [WorkoutSplit] = []
        var cumulative = 0.0
        var markedDistance = 0.0
        var markedTime = points[0].timestamp
        var index = 0

        for i in 1..<points.count {
            let segmentStart = points[i - 1]
            let segmentEnd = points[i]
            let segmentMeters = meters(from: segmentStart, to: segmentEnd)
            let segmentStartDistance = cumulative
            let segmentDuration = segmentEnd.timestamp.timeIntervalSince(segmentStart.timestamp)
            cumulative += segmentMeters
            while let distance = SplitBoundary.nextSegmentDistance(
                markedDistance: markedDistance,
                currentDistance: cumulative,
                unit: unit
            ) {
                guard distance > 0, segmentMeters > 0 else { break }
                let splitEndDistance = markedDistance + distance
                let fraction = min(1, max(0, (splitEndDistance - segmentStartDistance) / segmentMeters))
                let splitTime = segmentStart.timestamp.addingTimeInterval(segmentDuration * fraction)
                let duration = splitTime.timeIntervalSince(markedTime)
                guard duration > 0 else { break }
                index += 1
                let pace = (duration / distance) * 1_000
                splits.append(
                    WorkoutSplit(index: index, distanceMeters: distance, duration: duration, paceSecPerKm: pace)
                )
                markedDistance += distance
                markedTime = splitTime
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
        var splits: [WorkoutSplit] = []
        var markedDistance = previousDistance
        var markedElapsed = previousElapsed
        var index = previousCount
        while let distance = SplitBoundary.nextSegmentDistance(
            markedDistance: markedDistance,
            currentDistance: currentDistance,
            unit: unit
        ) {
            index += 1
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
