import Foundation
import WrathspeedCore

enum LiveMetric: String, Codable, CaseIterable, Sendable, Hashable {
    case time
    case distance
    case heartRate

    var chipLabel: String {
        switch self {
        case .time: "TIME"
        case .distance: "DIST"
        case .heartRate: "HR"
        }
    }

    var liveLabel: String {
        switch self {
        case .time: "TIME"
        case .distance: "DIST MI"
        case .heartRate: "HR BPM"
        }
    }

    func liveLabel(unit: DistanceUnit) -> String {
        switch self {
        case .time: "TIME"
        case .distance: "DIST \(unit == .miles ? "MI" : "KM")"
        case .heartRate: "HR BPM"
        }
    }
}

enum DataDensity: String, Codable, CaseIterable, Sendable {
    case simple
    case detailed

    var title: String {
        switch self {
        case .simple: "Simple"
        case .detailed: "Detailed"
        }
    }
}

struct CelebrationPayload: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var date: Date
    var distanceMeters: Double
    var duration: TimeInterval
    var averagePaceSecPerKm: Double?
    var prCopy: String?
    var streak: Int
    var weekCompletedMeters: Double
    var weekPlannedMeters: Double
    var previousVDOT: Double?
    var suggestion: VDOTSuggestion?
}

enum CoachingCopy {
    struct Chip {
        var text: String
        var kind: Kind
        enum Kind { case inZone, off, paused }
    }

    static func chip(
        currentPaceSecPerKm: Double?,
        targetSecPerKm: Double?,
        paused: Bool,
        style: CueStyle
    ) -> Chip {
        if paused {
            return Chip(text: style == .drill ? "HOLD." : "PAUSED", kind: .paused)
        }
        guard let current = currentPaceSecPerKm, let target = targetSecPerKm, current > 0, target > 0 else {
            return Chip(text: style == .minimal ? "IN ZONE" : (style == .drill ? "HOLD THE LINE." : "IN ZONE — HOLD IT"), kind: .inZone)
        }
        let fastLimit = target * 0.95
        let slowLimit = target * 1.05
        if current < fastLimit {
            switch style {
            case .minimal: return Chip(text: "HOT", kind: .off)
            case .standard: return Chip(text: "HOT — EASE OFF", kind: .off)
            case .drill: return Chip(text: "EASE OFF.", kind: .off)
            }
        }
        if current > slowLimit {
            let delta = WSFormat.signedPaceDelta(current - target)
            switch style {
            case .minimal: return Chip(text: "OFF", kind: .off)
            case .standard: return Chip(text: "\(delta) OFF — PUSH", kind: .off)
            case .drill: return Chip(text: "TOO SLOW. MOVE.", kind: .off)
            }
        }
        switch style {
        case .minimal: return Chip(text: "IN ZONE", kind: .inZone)
        case .standard: return Chip(text: "IN ZONE — HOLD IT", kind: .inZone)
        case .drill: return Chip(text: "HOLD THE LINE.", kind: .inZone)
        }
    }
}
