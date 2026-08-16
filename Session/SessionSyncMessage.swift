import Foundation
import WrathspeedCore

struct SessionSyncMessage: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case metrics
        case pause
        case resume
        case end
        case skipStep
    }

    var kind: Kind
    var elapsed: TimeInterval
    var distanceMeters: Double
    var paceSecPerKm: Double?
    var heartRate: Double?
    var stepIndex: Int
    var stepName: String
    var isPaused: Bool

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) -> SessionSyncMessage? {
        try? JSONDecoder().decode(SessionSyncMessage.self, from: data)
    }
}

struct WatchStartRequest: Codable, Sendable, Identifiable, Hashable {
    var blueprint: WorkoutBlueprint
    var vdot: Double?
    var unit: DistanceUnit?

    var id: UUID { blueprint.id }

    init(blueprint: WorkoutBlueprint, vdot: Double? = nil, unit: DistanceUnit? = nil) {
        self.blueprint = blueprint
        self.vdot = vdot
        self.unit = unit
    }
}
