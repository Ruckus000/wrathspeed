import Foundation
import WrathspeedCore

enum WSFormat {
    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static func weekdayDate(_ date: Date) -> String {
        weekday.string(from: date).uppercased()
    }

    static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date).uppercased()
    }

    static func distance(_ meters: Double, unit: DistanceUnit, fraction: Int = 1) -> String {
        let value = Units.display(fromMeters: meters, unit: unit)
        let formatted = value.formatted(.number.precision(.fractionLength(fraction)))
        return "\(formatted) \(unitSuffix(unit))"
    }

    static func distanceValue(_ meters: Double, unit: DistanceUnit, fraction: Int = 2) -> String {
        Units.display(fromMeters: meters, unit: unit)
            .formatted(.number.precision(.fractionLength(0...fraction)))
    }

    static func paceClock(_ secondsPerKilometer: TimeInterval, unit: DistanceUnit) -> String {
        let seconds = unit == .miles
            ? secondsPerKilometer * Units.metersPerMile / Units.metersPerKilometer
            : secondsPerKilometer
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func pace(_ secondsPerKilometer: TimeInterval, unit: DistanceUnit) -> String {
        "\(paceClock(secondsPerKilometer, unit: unit)) /\(unitSuffix(unit))"
    }

    static func duration(_ duration: TimeInterval) -> String {
        Units.formatDuration(duration)
    }

    static func vdot(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    static func unitSuffix(_ unit: DistanceUnit) -> String {
        unit == .miles ? "MI" : "KM"
    }

    static func unitLabel(_ unit: DistanceUnit) -> String {
        unit == .miles ? "MILE" : "KM"
    }

    static func signedPaceDelta(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let sign = total > 0 ? "+" : (total < 0 ? "−" : "")
        let absValue = abs(total)
        return String(format: "%@%d:%02d", sign, absValue / 60, absValue % 60)
    }
}

extension Weekday {
    var shortLabel: String {
        switch self {
        case .sunday: "SUN"
        case .monday: "MON"
        case .tuesday: "TUE"
        case .wednesday: "WED"
        case .thursday: "THU"
        case .friday: "FRI"
        case .saturday: "SAT"
        }
    }

    var chipLabel: String {
        switch self {
        case .sunday: "SUN"
        case .monday: "MON"
        case .tuesday: "TUE"
        case .wednesday: "WED"
        case .thursday: "THU"
        case .friday: "FRI"
        case .saturday: "SAT"
        }
    }
}

extension Ability {
    var title: String { rawValue.capitalized }
}

extension WorkoutKind {
    var title: String {
        switch self {
        case .easy: "Easy Run"
        case .intervals: "Intervals"
        case .tempo: "Tempo Run"
        case .longRun: "Long Run"
        case .race: "Race"
        case .walkRun: "Walk-run"
        case .freeRun: "Free run"
        case .strength: "Strength"
        }
    }

    var instantLabel: String {
        switch self {
        case .easy: "Easy"
        case .intervals: "Intervals"
        case .tempo: "Tempo"
        case .longRun: "Long"
        case .walkRun: "Walk-run"
        case .freeRun: "Free run"
        case .race: "Race"
        case .strength: "Strength"
        }
    }
}

extension RunLocation {
    var title: String {
        switch self {
        case .outdoor: "Outdoor"
        case .treadmill: "Treadmill"
        }
    }
}

extension StrengthAbility {
    var title: String { rawValue.capitalized }
}
