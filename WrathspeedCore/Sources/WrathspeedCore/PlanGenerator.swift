import Foundation

public enum PlanGenerator {
    public static let maxWeeks = 26
    public static let weeklyIncreaseCap = 0.10
    public static let recoveryWeekFactor = 0.80

    public static func generate(_ request: PlanRequest) -> TrainingPlan {
        if request.goal.kind.isBeginner {
            return BeginnerPlanGenerator.generate(request)
        }
        return generateRacePlan(request)
    }

    public static func generateValidated(_ request: PlanRequest) throws -> TrainingPlan {
        try request.validate()
        return generate(request)
    }

    public static func weekCount(for goal: TrainingGoal, startDate: Date, calendar: Calendar) -> Int {
        if let raceDate = goal.raceDate {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: calendar.startOfDay(for: raceDate)).day ?? 0
            let weeks = Int(ceil(Double(max(days, 1)) / 7.0))
            return min(maxWeeks, max(goal.kind.minimumWeeks, weeks))
        }
        return goal.weekCount
    }

    static func runWeekdays(daysPerWeek: Int, longRun: Weekday) -> [Weekday] {
        let offsets: [Int]
        switch daysPerWeek {
        case 3: offsets = [-4, -2, 0]
        case 4: offsets = [-5, -3, -1, 0]
        case 5: offsets = [-5, -4, -2, -1, 0]
        default: offsets = [-6, -5, -4, -2, -1, 0]
        }
        return offsets.map { offset in
            var raw = longRun.rawValue + offset
            while raw < 1 { raw += 7 }
            while raw > 7 { raw -= 7 }
            return Weekday(rawValue: raw) ?? longRun
        }
    }

    private static func generateRacePlan(_ request: PlanRequest) -> TrainingPlan {
        var calendar = request.calendar
        calendar.firstWeekday = 1
        let start = calendar.startOfDay(for: request.startDate)
        let weeks = weekCount(for: request.goal, startDate: start, calendar: calendar)
        let weekdays = request.profile.resolvedRunWeekdays()
        let zones = PaceCalculator.zones(vdot: request.profile.vdot)
        let raceDistance = request.goal.kind.distanceMeters ?? 5_000

        var workouts: [ScheduledWorkout] = []
        var weeklyTarget = request.profile.weeklyMileageMeters
        var longTarget = request.profile.longestRunMeters
        let longCap = longRunCap(for: request.goal.kind)

        for weekIndex in 0..<weeks {
            let phase = phase(week: weekIndex, total: weeks)
            let isRecovery = weekIndex > 0 && (weekIndex + 1) % 4 == 0 && phase != .taper
            let isTaper = phase == .taper
            let isRaceWeek = weekIndex == weeks - 1

            if isRecovery {
                weeklyTarget *= recoveryWeekFactor
            } else if weekIndex > 0, !isTaper {
                weeklyTarget *= (1 + weeklyIncreaseCap)
            } else if isTaper {
                let taperWeeks = max(1, weeks - weekIndex)
                let remaining = weeks - weekIndex
                weeklyTarget *= remaining == 1 ? 0.55 : 0.75
                _ = taperWeeks
            }

            if !isRecovery && !isTaper && weekIndex > 0 {
                longTarget = min(longCap, longTarget * 1.10)
            }
            longTarget = min(longTarget, weeklyTarget * 0.40, longCap)

            let roles = dayRoles(
                weekdays: weekdays,
                longRun: request.profile.longRunWeekday,
                phase: phase,
                weekIndex: weekIndex,
                isRaceWeek: isRaceWeek
            ).map { day, role -> (Weekday, DayRole) in
                if isRaceWeek, role == .quality || role == .tempo { return (day, .easy) }
                return (day, role)
            }

            let weekStart = calendar.date(byAdding: .day, value: weekIndex * 7, to: start) ?? start
            var remaining = weeklyTarget
            var built: [(Weekday, DayRole, WorkoutBlueprint)] = []

            for (day, role) in roles where role != .rest {
                let date = dateOnWeekday(day, weekStart: weekStart, calendar: calendar)
                if isRaceWeek, day == request.profile.longRunWeekday || (request.goal.raceDate != nil && calendar.isDate(date, inSameDayAs: request.goal.raceDate!)) {
                    continue
                }
                let blueprint: WorkoutBlueprint
                switch role {
                case .long:
                    let distance = min(longTarget, remaining)
                    blueprint = WorkoutBuilder.longRun(
                        date: date,
                        meters: distance,
                        location: request.location,
                        usesPace: true
                    )
                    remaining -= distance
                case .quality:
                    blueprint = WorkoutBuilder.intervals(
                        date: date,
                        kind: request.goal.kind,
                        phase: phase,
                        location: request.location
                    )
                    remaining -= blueprint.plannedDistanceMeters
                case .tempo:
                    blueprint = WorkoutBuilder.tempo(
                        date: date,
                        phase: phase,
                        location: request.location
                    )
                    remaining -= blueprint.plannedDistanceMeters
                case .easy:
                    blueprint = WorkoutBlueprint(
                        date: date,
                        kind: .easy,
                        title: "Easy run",
                        location: request.location,
                        steps: [],
                        plannedDistanceMeters: 0,
                        usesPaceTargets: true
                    )
                case .rest:
                    continue
                }
                built.append((day, role, blueprint))
            }

            let easySlots = built.filter { $0.1 == .easy }.count
            let easyEach = easySlots > 0 ? max(2_000, remaining / Double(easySlots)) : 0
            for item in built {
                var blueprint = item.2
                if item.1 == .easy {
                    blueprint = WorkoutBuilder.easyRun(date: blueprint.date, meters: easyEach, location: request.location)
                }
                if let raceDate = request.goal.raceDate, calendar.isDate(blueprint.date, inSameDayAs: raceDate) {
                    continue
                }
                workouts.append(ScheduledWorkout(blueprint: blueprint))
            }

            if isRaceWeek, let raceDate = request.goal.raceDate ?? calendar.date(byAdding: .day, value: weeks * 7 - 1, to: start) {
                let raceDay = calendar.startOfDay(for: raceDate)
                workouts.append(
                    ScheduledWorkout(
                        blueprint: WorkoutBuilder.race(
                            date: raceDay,
                            meters: raceDistance,
                            kind: request.goal.kind,
                            location: request.location
                        )
                    )
                )
            }
        }

        workouts.sort { $0.date < $1.date }
        _ = zones
        return TrainingPlan(goal: request.goal, profile: request.profile, workouts: workouts)
    }

    public enum Phase: Sendable {
        case base, build, peak, taper
    }

    enum DayRole {
        case easy, quality, tempo, long, rest
    }

    public static func phase(week: Int, total: Int) -> Phase {
        let t = Double(week) / Double(max(total - 1, 1))
        if t >= 0.88 { return .taper }
        if t >= 0.70 { return .peak }
        if t >= 0.35 { return .build }
        return .base
    }

    public static func isRecoveryWeek(weekIndex: Int, totalWeeks: Int) -> Bool {
        weekIndex > 0 && (weekIndex + 1) % 4 == 0 && phase(week: weekIndex, total: totalWeeks) != .taper
    }

    public static func weekEyebrow(weekIndex: Int, totalWeeks: Int) -> String {
        if weekIndex == totalWeeks - 1 { return "TAPER · RACE WEEK" }
        if isRecoveryWeek(weekIndex: weekIndex, totalWeeks: totalWeeks) { return "RECOVERY WEEK" }
        switch phase(week: weekIndex, total: totalWeeks) {
        case .taper: return "TAPER · RACE WEEK"
        case .peak: return "PEAK PHASE"
        case .build: return "BUILD PHASE"
        case .base: return "BASE PHASE"
        }
    }

    public static func progressionRule(weekIndex: Int, totalWeeks: Int, kind: GoalKind) -> String {
        if weekIndex == totalWeeks - 1 {
            return "Race week. Quality sessions convert to easy. Taper volume is 55% of peak."
        }
        if phase(week: weekIndex, total: totalWeeks) == .taper {
            return "Taper 75% then 55% of peak weekly volume so you arrive fresh."
        }
        if isRecoveryWeek(weekIndex: weekIndex, totalWeeks: totalWeeks) {
            return "Every 4th week is a recovery week at 80% of the prior week's volume."
        }
        let capKm = Int(longRunCap(for: kind) / 1_000)
        return "Weekly volume increases at most 10%. Long run is capped at 40% of weekly volume and \(capKm) km for this goal."
    }

    public static func longRunCap(for kind: GoalKind) -> Double {
        switch kind {
        case .fiveK: 12_000
        case .tenK: 16_000
        case .halfMarathon: 22_000
        case .marathon: 32_000
        case .newToRunning, .returnToRunning: 10_000
        }
    }

    static func dayRoles(
        weekdays: [Weekday],
        longRun: Weekday,
        phase: Phase,
        weekIndex: Int,
        isRaceWeek: Bool
    ) -> [(Weekday, DayRole)] {
        weekdays.map { day in
            if day == longRun {
                return (day, isRaceWeek ? .rest : .long)
            }
            let others = weekdays.filter { $0 != longRun }
            if others.first == day {
                return (day, (weekIndex % 2 == 0 || phase == .base) ? .tempo : .quality)
            }
            if others.count >= 3, others.dropFirst().first == day, weekdays.count >= 5 {
                return (day, .tempo)
            }
            return (day, .easy)
        }
    }

    static func dateOnWeekday(_ weekday: Weekday, weekStart: Date, calendar: Calendar) -> Date {
        for offset in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: offset, to: weekStart) {
                let wd = calendar.component(.weekday, from: date)
                if wd == weekday.rawValue {
                    return calendar.startOfDay(for: date)
                }
            }
        }
        return weekStart
    }
}

enum WorkoutBuilder {
    static func easyRun(date: Date, meters: Double, location: RunLocation) -> WorkoutBlueprint {
        let steps = [
            WorkoutStep(name: "Easy", target: .distance(meters: meters), intensity: .zone(.easy)),
        ]
        return WorkoutBlueprint(
            date: date,
            kind: .easy,
            title: "Easy run",
            location: location,
            steps: steps,
            plannedDistanceMeters: meters,
            usesPaceTargets: true
        )
    }

    static func longRun(date: Date, meters: Double, location: RunLocation, usesPace: Bool) -> WorkoutBlueprint {
        let warmup = min(1_000, meters * 0.1)
        let main = max(meters - warmup, meters * 0.8)
        let steps = [
            WorkoutStep(name: "Warm up", target: .distance(meters: warmup), intensity: .zone(.easy)),
            WorkoutStep(name: "Long run", target: .distance(meters: main), intensity: usesPace ? .zone(.easy) : .rpe(4)),
        ]
        return WorkoutBlueprint(
            date: date,
            kind: .longRun,
            title: "Long run",
            location: location,
            steps: steps,
            plannedDistanceMeters: warmup + main,
            usesPaceTargets: usesPace
        )
    }

    static func intervals(date: Date, kind: GoalKind, phase: PlanGenerator.Phase, location: RunLocation) -> WorkoutBlueprint {
        let reps: Int
        let work: Double
        let rest: Double
        switch kind {
        case .fiveK:
            reps = phase == .peak ? 8 : 6
            work = 400
            rest = 200
        case .tenK:
            reps = 6
            work = 800
            rest = 400
        case .halfMarathon:
            reps = 5
            work = 1_000
            rest = 400
        default:
            reps = 4
            work = 1_600
            rest = 600
        }
        var steps: [WorkoutStep] = [
            WorkoutStep(name: "Warm up", target: .distance(meters: 1_500), intensity: .zone(.easy)),
        ]
        for i in 1...reps {
            steps.append(WorkoutStep(name: "Interval \(i)", target: .distance(meters: work), intensity: .zone(.interval)))
            steps.append(WorkoutStep(name: "Recover \(i)", target: .distance(meters: rest), intensity: .zone(.recovery)))
        }
        steps.append(WorkoutStep(name: "Cool down", target: .distance(meters: 1_000), intensity: .zone(.easy)))
        let total = steps.reduce(0.0) { sum, step in
            if case .distance(let meters) = step.target { return sum + meters }
            return sum
        }
        return WorkoutBlueprint(
            date: date,
            kind: .intervals,
            title: "Intervals",
            location: location,
            steps: steps,
            plannedDistanceMeters: total,
            usesPaceTargets: true
        )
    }

    static func tempo(date: Date, phase: PlanGenerator.Phase, location: RunLocation) -> WorkoutBlueprint {
        let tempoMeters: Double = phase == .peak ? 8_000 : 5_000
        let steps = [
            WorkoutStep(name: "Warm up", target: .distance(meters: 1_500), intensity: .zone(.easy)),
            WorkoutStep(name: "Tempo", target: .distance(meters: tempoMeters), intensity: .zone(.threshold)),
            WorkoutStep(name: "Cool down", target: .distance(meters: 1_000), intensity: .zone(.easy)),
        ]
        return WorkoutBlueprint(
            date: date,
            kind: .tempo,
            title: "Tempo run",
            location: location,
            steps: steps,
            plannedDistanceMeters: 1_500 + tempoMeters + 1_000,
            usesPaceTargets: true
        )
    }

    static func race(date: Date, meters: Double, kind: GoalKind, location: RunLocation) -> WorkoutBlueprint {
        let zone: PaceZone = kind == .marathon ? .marathon : .threshold
        let steps = [
            WorkoutStep(name: "Warm up", target: .distance(meters: 1_000), intensity: .zone(.easy)),
            WorkoutStep(name: kind.displayName, target: .distance(meters: meters), intensity: .zone(zone)),
        ]
        return WorkoutBlueprint(
            date: date,
            kind: .race,
            title: "\(kind.displayName) race",
            location: location,
            steps: steps,
            plannedDistanceMeters: 1_000 + meters,
            usesPaceTargets: true
        )
    }
}
