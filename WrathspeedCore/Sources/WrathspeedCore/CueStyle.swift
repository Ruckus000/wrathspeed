import Foundation

public enum CueStyle: String, Codable, CaseIterable, Sendable {
    case minimal
    case standard
    case drill

    public var title: String {
        switch self {
        case .minimal: "Minimal"
        case .standard: "Standard"
        case .drill: "Drill Sergeant"
        }
    }

    public func phrase(for cue: Cue) -> String {
        switch cue {
        case .stepStarted(let name):
            return self == .drill ? "\(name). GO." : "\(name)."
        case .stepCompleted(let name):
            return self == .drill ? "\(name) DONE." : "\(name) complete."
        case .speedUp:
            return self == .drill ? "Too slow. Move." : "Speed up."
        case .slowDown:
            return self == .drill ? "Ease off." : (self == .minimal ? "Ease off." : "Slow down.")
        case .split(let km, _):
            return self == .drill ? "K \(km)." : "Kilometer \(km)."
        }
    }
}
