import Foundation

public enum Units {
    public static let metersPerKilometer = 1_000.0
    public static let metersPerMile = 1_609.344

    public static func meters(fromDisplay value: Double, unit: DistanceUnit) -> Double {
        switch unit {
        case .kilometers: value * metersPerKilometer
        case .miles: value * metersPerMile
        }
    }

    public static func display(fromMeters meters: Double, unit: DistanceUnit) -> Double {
        switch unit {
        case .kilometers: meters / metersPerKilometer
        case .miles: meters / metersPerMile
        }
    }

    public static func formatDistance(_ meters: Double, unit: DistanceUnit) -> String {
        let value = display(fromMeters: meters, unit: unit)
        let formatted = value.formatted(.number.precision(.fractionLength(0...2)))
        switch unit {
        case .kilometers: return "\(formatted) km"
        case .miles: return "\(formatted) mi"
        }
    }

    public static func formatPace(secondsPerKilometer: TimeInterval, unit: DistanceUnit) -> String {
        let seconds: TimeInterval
        switch unit {
        case .kilometers: seconds = secondsPerKilometer
        case .miles: seconds = secondsPerKilometer * metersPerMile / metersPerKilometer
        }
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds.rounded()) % 60
        let suffix = unit == .kilometers ? "/km" : "/mi"
        return String(format: "%d:%02d %@", minutes, remainder, suffix)
    }

    public static func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
