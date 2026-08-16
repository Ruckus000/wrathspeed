import WrathspeedCore

extension PaceBandStatus {
    var watchLabel: String {
        switch self {
        case .paused: "PAUSED"
        case .unavailable: "NO PACE"
        case .tooFast: "TOO FAST"
        case .inZone: "IN ZONE"
        case .tooSlow: "TOO SLOW"
        }
    }
}
