import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var stepName: String
        var elapsed: TimeInterval
        var distanceMeters: Double
        var paceSecPerKm: Double?
        var isPaused: Bool
    }

    var workoutName: String
}
