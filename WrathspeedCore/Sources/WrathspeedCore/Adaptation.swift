import Foundation

public struct VDOTSuggestion: Equatable, Sendable {
    public var newVDOT: Double
    public var reason: String

    public init(newVDOT: Double, reason: String) {
        self.newVDOT = newVDOT
        self.reason = reason
    }
}

public struct AdaptationDecision: Equatable, Sendable {
    public var freezeMileageIncrease: Bool
    public var vdotSuggestion: VDOTSuggestion?

    public init(freezeMileageIncrease: Bool, vdotSuggestion: VDOTSuggestion? = nil) {
        self.freezeMileageIncrease = freezeMileageIncrease
        self.vdotSuggestion = vdotSuggestion
    }
}

public enum AdaptationRules {
    public static let skipFreezeThreshold = 2
    public static let qualitySampleCount = 3
    public static let paceDeltaThreshold = 0.05
    public static let vdotNudge = 0.03

    public static func evaluate(
        skippedThisWeek: Int,
        qualitySessions: [QualitySession],
        currentVDOT: Double
    ) -> AdaptationDecision {
        let freeze = skippedThisWeek >= skipFreezeThreshold
        guard qualitySessions.count >= qualitySampleCount else {
            return AdaptationDecision(freezeMileageIncrease: freeze)
        }
        let recent = Array(qualitySessions.suffix(qualitySampleCount))
        let meanDelta = recent.map(\.paceDeltaFraction).reduce(0, +) / Double(recent.count)
        if meanDelta <= -paceDeltaThreshold {
            let nudged = currentVDOT * (1 + vdotNudge)
            return AdaptationDecision(
                freezeMileageIncrease: freeze,
                vdotSuggestion: VDOTSuggestion(newVDOT: nudged, reason: "Recent quality sessions were more than 5% faster than target.")
            )
        }
        if meanDelta >= paceDeltaThreshold {
            let nudged = currentVDOT * (1 - vdotNudge)
            return AdaptationDecision(
                freezeMileageIncrease: freeze,
                vdotSuggestion: VDOTSuggestion(newVDOT: nudged, reason: "Recent quality sessions were more than 5% slower than target.")
            )
        }
        return AdaptationDecision(freezeMileageIncrease: freeze)
    }

    public static func applySkip(
        _ workout: ScheduledWorkout,
        convertQualityToEasy: Bool = false
    ) -> ScheduledWorkout {
        var copy = workout
        if convertQualityToEasy, workout.blueprint.kind.isQuality {
            copy.status = .convertedToEasy
            copy.blueprint = WorkoutBuilder.easyRun(
                date: workout.date,
                meters: workout.blueprint.plannedDistanceMeters * 0.8,
                location: workout.blueprint.location
            )
        } else {
            copy.status = .skipped
        }
        return copy
    }

    public static func canMoveLongRun(from: Date, to: Date) -> Bool {
        abs(to.timeIntervalSince(from)) <= 48 * 3600
    }

    public static func wouldStackQuality(existing: [ScheduledWorkout], moving: ScheduledWorkout, to date: Date, calendar: Calendar) -> Bool {
        guard moving.blueprint.kind.isQuality else { return false }
        return existing.contains { other in
            other.id != moving.id
                && other.blueprint.kind.isQuality
                && other.status == .scheduled
                && calendar.isDate(other.date, inSameDayAs: date)
        }
    }
}

public enum N100Mode: String, Codable, CaseIterable, Sendable {
    case pause
    case reducedDifficulty
    case easyAndLongOnly
    case shortEasyOnly

    public var title: String {
        switch self {
        case .pause: "Pause running"
        case .reducedDifficulty: "Easier sessions"
        case .easyAndLongOnly: "Easy and long only"
        case .shortEasyOnly: "Short easy runs"
        }
    }
}

public enum N100Return: String, Codable, CaseIterable, Sendable {
    case slow
    case balanced
    case quick

    public var title: String {
        switch self {
        case .slow: "Slow"
        case .balanced: "Balanced"
        case .quick: "Quick"
        }
    }

    var extraEasyDays: Int {
        switch self {
        case .slow: 3
        case .balanced: 1
        case .quick: 0
        }
    }
}

public struct N100Adjustment: Codable, Equatable, Sendable {
    public var start: Date
    public var dayCount: Int
    public var mode: N100Mode
    public var returnPace: N100Return

    public init(start: Date, dayCount: Int, mode: N100Mode, returnPace: N100Return) {
        self.start = start
        self.dayCount = min(14, max(3, dayCount))
        self.mode = mode
        self.returnPace = returnPace
    }

    public func windowEnd(calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: dayCount, to: calendar.startOfDay(for: start)) ?? start
    }

    public func returnEnd(calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: returnPace.extraEasyDays, to: windowEnd(calendar: calendar)) ?? windowEnd(calendar: calendar)
    }
}

public enum NotFeeling100Rules {
    public static func isValidDayCount(_ count: Int) -> Bool {
        (3...14).contains(count)
    }

    public static func apply(
        workouts: [ScheduledWorkout],
        adjustment: N100Adjustment,
        calendar: Calendar
    ) -> [ScheduledWorkout] {
        let start = calendar.startOfDay(for: adjustment.start)
        let windowEnd = adjustment.windowEnd(calendar: calendar)
        let returnEnd = adjustment.returnEnd(calendar: calendar)

        return workouts.map { workout in
            guard workout.blueprint.kind.isRunning, workout.status == .scheduled else { return workout }
            let day = calendar.startOfDay(for: workout.date)
            if day >= start && day < windowEnd {
                return transformDuring(workout, mode: adjustment.mode)
            }
            if day >= windowEnd && day < returnEnd {
                return transformReturn(workout)
            }
            return workout
        }
    }

    private static func transformDuring(_ workout: ScheduledWorkout, mode: N100Mode) -> ScheduledWorkout {
        var copy = workout
        switch mode {
        case .pause:
            copy.status = .skipped
        case .reducedDifficulty:
            if workout.blueprint.kind.isQuality {
                copy.blueprint = WorkoutBuilder.easyRun(
                    date: workout.date,
                    meters: workout.blueprint.plannedDistanceMeters,
                    location: workout.blueprint.location
                )
                copy.blueprint.title = "Easy (reduced)"
            }
        case .easyAndLongOnly:
            if workout.blueprint.kind.isQuality {
                copy.status = .skipped
            } else if workout.blueprint.kind == .easy || workout.blueprint.kind == .longRun {
                copy.blueprint.usesPaceTargets = false
                copy.blueprint.steps = copy.blueprint.steps.map { step in
                    var step = step
                    step.intensity = .rpe(3)
                    return step
                }
            }
        case .shortEasyOnly:
            copy.blueprint = WorkoutBuilder.easyRun(
                date: workout.date,
                meters: min(4_000, workout.blueprint.plannedDistanceMeters),
                location: workout.blueprint.location
            )
            copy.blueprint.title = "Short easy"
        }
        return copy
    }

    private static func transformReturn(_ workout: ScheduledWorkout) -> ScheduledWorkout {
        var copy = workout
        if workout.blueprint.kind.isQuality {
            copy.blueprint = WorkoutBuilder.easyRun(
                date: workout.date,
                meters: workout.blueprint.plannedDistanceMeters * 0.7,
                location: workout.blueprint.location
            )
            copy.blueprint.title = "Easy (return)"
        }
        return copy
    }
}
