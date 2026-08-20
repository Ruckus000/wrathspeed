import Foundation
import WrathspeedCore

enum WSFormat {
    static let missingValue = "—"

    private static func localizedFormatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static let weekday: DateFormatter = localizedFormatter(template: "EEEMMMd")
    private static let monthDayFormatter: DateFormatter = localizedFormatter(template: "MMMd")
    private static let importTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func weekdayDate(_ date: Date) -> String {
        weekday.string(from: date).uppercased()
    }

    static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date).uppercased()
    }

    static func importTimestamp(_ date: Date) -> String {
        importTimestampFormatter.string(from: date).uppercased()
    }

    static func distance(_ meters: Double, unit: DistanceUnit, fraction: Int = 1) -> String {
        let value = Units.display(fromMeters: meters, unit: unit)
        let formatted = value.formatted(.number.precision(.fractionLength(fraction)).locale(.current))
        return "\(formatted) \(unitSuffix(unit))"
    }

    static func distanceValue(_ meters: Double, unit: DistanceUnit, fraction: Int = 2) -> String {
        Units.display(fromMeters: meters, unit: unit)
            .formatted(.number.precision(.fractionLength(0...fraction)).locale(.current))
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
        value.formatted(.number.precision(.fractionLength(1)).locale(.current))
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

    static func heartRate(bpm: Double?) -> String {
        guard let bpm else { return missingValue }
        return bpm.rounded().formatted(.number.precision(.fractionLength(0)).locale(.current))
    }

    static func activeEnergy(kilocalories: Double?) -> String {
        guard let kilocalories else { return missingValue }
        let rounded = kilocalories.rounded()
        return "\(rounded.formatted(.number.precision(.fractionLength(0)).locale(.current))) KCAL"
    }

    static func cadence(stepsPerMinute: Double?) -> String {
        guard let stepsPerMinute else { return missingValue }
        return "\(stepsPerMinute.rounded().formatted(.number.precision(.fractionLength(0)).locale(.current))) SPM"
    }

    static func strengthLoad(value: Double?, unit: String?) -> String {
        guard let value else { return missingValue }
        let formatted = value.formatted(.number.precision(.fractionLength(0...1)).locale(.current))
        if let unit, !unit.isEmpty {
            return "\(formatted) \(unit.uppercased())"
        }
        return formatted
    }

    static func healthSyncLabel(state: HealthSyncState, failureMessage: String?) -> String {
        switch state {
        case .failed:
            if let failureMessage, !failureMessage.isEmpty {
                return "FAILED — \(failureMessage.uppercased())"
            }
            return "FAILED"
        case .notRequired:
            return "NOT REQUIRED"
        case .pending:
            return "PENDING"
        case .synced:
            return "SYNCED"
        }
    }

    static func weeklyLoadLine(_ summary: WeeklyLoadSummary, unit: DistanceUnit) -> String {
        let planned = distance(summary.plannedMeters, unit: unit)
        let actual = distance(summary.actualMeters, unit: unit)
        return "\(summary.confirmedAdherenceCount)/\(summary.plannedRunCount) RUNS · \(actual) / \(planned)"
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

    var historyLabel: String {
        switch self {
        case .outdoor: "OUTDOOR"
        case .treadmill: "TREADMILL"
        }
    }
}

extension StrengthAbility {
    var title: String { rawValue.capitalized }
}
