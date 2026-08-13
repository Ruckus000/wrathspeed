import Foundation

public enum RouteSampler {
    public static let displayPointLimit = 500

    public static func displayRoute(
        from points: [RoutePoint],
        limit: Int = displayPointLimit
    ) -> [RoutePoint] {
        guard limit >= 2, points.count > limit else { return points }
        let lastIndex = points.count - 1
        return (0..<limit).map { outputIndex in
            let fraction = Double(outputIndex) / Double(limit - 1)
            let sourceIndex = Int((fraction * Double(lastIndex)).rounded())
            return points[sourceIndex]
        }
    }
}
