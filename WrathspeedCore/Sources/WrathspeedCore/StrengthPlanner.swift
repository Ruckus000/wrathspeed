import Foundation

public enum StrengthAbility: String, Codable, CaseIterable, Sendable {
    case beginner
    case intermediate
    case advanced
}

public enum StrengthGoal: String, Codable, CaseIterable, Sendable {
    case runningFocus
    case allRound

    public var title: String {
        switch self {
        case .runningFocus: "Running focus"
        case .allRound: "All-round strength"
        }
    }
}

public enum StrengthFocus: String, Codable, CaseIterable, Sendable {
    case legsCore
    case fullBody
    case upper
}

public enum StrengthEquipment: String, Codable, CaseIterable, Sendable {
    case stretchBand
    case barbell
    case box
    case bench
    case dumbbell
    case kettlebell
    case pullUpBar
    case swissBall
    case bodyweight

    public var title: String {
        switch self {
        case .stretchBand: "Stretch band"
        case .barbell: "Barbell"
        case .box: "Box"
        case .bench: "Bench"
        case .dumbbell: "Dumbbell"
        case .kettlebell: "Kettlebell"
        case .pullUpBar: "Pull-up bar"
        case .swissBall: "Swiss ball"
        case .bodyweight: "Bodyweight"
        }
    }
}

public struct StrengthPreferences: Codable, Equatable, Sendable {
    public var ability: StrengthAbility
    public var goal: StrengthGoal
    public var durationMinutes: Int
    public var sessionsPerWeek: Int
    public var preferredDays: [Weekday]
    public var equipment: Set<StrengthEquipment>

    public init(
        ability: StrengthAbility = .beginner,
        goal: StrengthGoal = .runningFocus,
        durationMinutes: Int = 30,
        sessionsPerWeek: Int = 2,
        preferredDays: [Weekday] = [.monday, .thursday],
        equipment: Set<StrengthEquipment> = [.bodyweight]
    ) {
        self.ability = ability
        self.goal = goal
        self.durationMinutes = [30, 45, 60].contains(durationMinutes) ? durationMinutes : 30
        self.sessionsPerWeek = min(4, max(1, sessionsPerWeek))
        self.preferredDays = preferredDays
        self.equipment = equipment.isEmpty ? [.bodyweight] : equipment
    }
}

public struct StrengthExercise: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var focus: [StrengthFocus]
    public var equipment: [StrengthEquipment]
    public var symbolName: String
    public var defaultReps: Int
    public var cue: String
}

public struct StrengthSet: Codable, Equatable, Sendable {
    public var exercise: StrengthExercise
    public var sets: Int
    public var reps: Int
    public var restSeconds: Int
}

public struct StrengthSession: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var focus: StrengthFocus
    public var title: String
    public var sets: [StrengthSet]
    public var durationMinutes: Int

    public init(
        id: UUID = UUID(),
        date: Date,
        focus: StrengthFocus,
        title: String,
        sets: [StrengthSet],
        durationMinutes: Int
    ) {
        self.id = id
        self.date = date
        self.focus = focus
        self.title = title
        self.sets = sets
        self.durationMinutes = durationMinutes
    }
}

public struct StrengthCatalog: Codable, Equatable, Sendable {
    public var exercises: [StrengthExercise]
}

public enum StrengthPlanner {
    public static func loadCatalog(from bundle: Bundle? = nil) throws -> StrengthCatalog {
        let bundle = bundle ?? Bundle.module
        guard let url = bundle.url(forResource: "strength_catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StrengthCatalog.self, from: data)
    }

    public static func distribution(goal: StrengthGoal, sessionsPerWeek: Int) -> [StrengthFocus] {
        switch (goal, sessionsPerWeek) {
        case (.runningFocus, 1): [.legsCore]
        case (.runningFocus, 2): [.legsCore, .fullBody]
        case (.runningFocus, 3): [.legsCore, .legsCore, .fullBody]
        case (.runningFocus, _): [.legsCore, .fullBody, .upper, .legsCore]
        case (.allRound, 1): [.fullBody]
        case (.allRound, 2): [.upper, .legsCore]
        case (.allRound, 3): [.fullBody, .upper, .legsCore]
        case (.allRound, _): [.fullBody, .upper, .legsCore, .fullBody]
        }
    }

    public static func schedule(
        preferences: StrengthPreferences,
        startDate: Date,
        weekCount: Int,
        calendar: Calendar,
        catalog: StrengthCatalog
    ) -> [StrengthSession] {
        let foci = distribution(goal: preferences.goal, sessionsPerWeek: preferences.sessionsPerWeek)
        let days = Array(preferences.preferredDays.prefix(preferences.sessionsPerWeek))
        let start = calendar.startOfDay(for: startDate)
        var sessions: [StrengthSession] = []

        for week in 0..<weekCount {
            let weekStart = calendar.date(byAdding: .day, value: week * 7, to: start) ?? start
            for (index, focus) in foci.enumerated() {
                let weekday = days.indices.contains(index) ? days[index] : days[index % max(days.count, 1)]
                let date = PlanGenerator.dateOnWeekday(weekday, weekStart: weekStart, calendar: calendar)
                sessions.append(makeSession(date: date, focus: focus, preferences: preferences, catalog: catalog))
            }
        }
        return sessions
    }

    public static func makeSession(
        date: Date,
        focus: StrengthFocus,
        preferences: StrengthPreferences,
        catalog: StrengthCatalog
    ) -> StrengthSession {
        let allowed = catalog.exercises.filter { exercise in
            exercise.focus.contains(focus)
                && exercise.equipment.contains(where: { preferences.equipment.contains($0) || $0 == .bodyweight })
        }
        let fallback = catalog.exercises.filter { $0.equipment.contains(.bodyweight) }
        let pool = allowed.isEmpty ? fallback : allowed
        let count: Int
        switch preferences.durationMinutes {
        case 60: count = 8
        case 45: count = 7
        default: count = 5
        }
        let setsCount: Int
        let reps: Int
        switch preferences.ability {
        case .beginner:
            setsCount = 2
            reps = 10
        case .intermediate:
            setsCount = 3
            reps = 10
        case .advanced:
            setsCount = 3
            reps = 8
        }

        var picked: [StrengthExercise] = []
        for exercise in pool where picked.count < count {
            if !picked.contains(where: { $0.id == exercise.id }) {
                picked.append(exercise)
            }
        }
        if picked.count < count {
            for exercise in fallback where picked.count < count {
                if !picked.contains(where: { $0.id == exercise.id }) {
                    picked.append(exercise)
                }
            }
        }

        let sets = picked.map {
            StrengthSet(exercise: $0, sets: setsCount, reps: $0.defaultReps == 0 ? reps : $0.defaultReps, restSeconds: 45)
        }
        let title: String
        switch focus {
        case .legsCore: title = "Legs and core"
        case .fullBody: title = "Full body"
        case .upper: title = "Upper body"
        }
        return StrengthSession(date: date, focus: focus, title: title, sets: sets, durationMinutes: preferences.durationMinutes)
    }

    public static func asScheduledWorkouts(_ sessions: [StrengthSession]) -> [ScheduledWorkout] {
        sessions.map { session in
            let steps = session.sets.enumerated().flatMap { index, item -> [WorkoutStep] in
                (1...item.sets).map { setIndex in
                    WorkoutStep(
                        name: "\(item.exercise.name) \(setIndex)/\(item.sets)",
                        target: .duration(seconds: 45),
                        intensity: .none
                    )
                }
            }
            let blueprint = WorkoutBlueprint(
                id: session.id,
                date: session.date,
                kind: .strength,
                title: session.title,
                location: .treadmill,
                steps: steps,
                plannedDistanceMeters: 0,
                usesPaceTargets: false
            )
            return ScheduledWorkout(id: session.id, blueprint: blueprint)
        }
    }
}
