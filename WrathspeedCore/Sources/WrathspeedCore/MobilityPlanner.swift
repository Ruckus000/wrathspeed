import Foundation

public struct RoutineItem: Codable, Equatable, Sendable, Identifiable {
    public var movement: Movement
    public var durationSeconds: Int

    public var id: String { movement.id }

    public init(movement: Movement, durationSeconds: Int) {
        self.movement = movement
        self.durationSeconds = durationSeconds
    }
}

public struct MobilityRoutine: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var phase: MovementPhase
    public var items: [RoutineItem]

    public init(id: String, title: String, phase: MovementPhase, items: [RoutineItem]) {
        self.id = id
        self.title = title
        self.phase = phase
        self.items = items
    }

    public var totalSeconds: Int {
        items.reduce(0) { $0 + $1.durationSeconds }
    }

    public var isEmpty: Bool { items.isEmpty }
}

/// Builds the warm-up, drill and cool-down routines that bracket a run.
///
/// Selection is deterministic given the same workout and catalog: routines are picked by
/// walking the catalog in order and taking movements until the time budget is used up.
/// Deterministic matters here — the same Tuesday tempo should show the same warm-up
/// whether it is rendered on the phone, the watch, or in a test.
public enum MobilityPlanner {
    /// Time budgets in seconds, by workout kind. Quality days get a longer warm-up because
    /// they are the ones that punish going out cold.
    static func warmupBudget(for kind: WorkoutKind) -> Int {
        switch kind {
        case .intervals, .race: 420
        case .tempo: 360
        case .longRun: 300
        case .easy, .walkRun, .freeRun: 240
        case .strength: 240
        }
    }

    static func cooldownBudget(for kind: WorkoutKind) -> Int {
        switch kind {
        case .longRun, .race: 420
        case .intervals, .tempo: 360
        default: 300
        }
    }

    /// Drills are for days where running form under speed matters. On an easy shakeout
    /// they are just extra fatigue, so they are omitted rather than shortened.
    public static func includesDrills(for kind: WorkoutKind) -> Bool {
        kind.isQuality
    }

    public static func warmup(
        for kind: WorkoutKind,
        catalog: MovementCatalog,
        budgetSeconds: Int? = nil
    ) -> MobilityRoutine {
        let budget = budgetSeconds ?? warmupBudget(for: kind)
        return MobilityRoutine(
            id: "warmup-\(kind.rawValue)",
            title: "Warm-up",
            phase: .warmup,
            items: fill(catalog.inPhase(.warmup), budget: budget)
        )
    }

    public static func cooldown(
        for kind: WorkoutKind,
        catalog: MovementCatalog,
        budgetSeconds: Int? = nil
    ) -> MobilityRoutine {
        let budget = budgetSeconds ?? cooldownBudget(for: kind)
        return MobilityRoutine(
            id: "cooldown-\(kind.rawValue)",
            title: "Cool-down",
            phase: .cooldown,
            items: fill(catalog.inPhase(.cooldown), budget: budget)
        )
    }

    /// Empty for non-quality days. Callers can show or hide the section on `isEmpty`.
    public static func drills(
        for kind: WorkoutKind,
        catalog: MovementCatalog,
        budgetSeconds: Int = 240
    ) -> MobilityRoutine {
        let pool = includesDrills(for: kind) ? catalog.inPhase(.drills) : []
        return MobilityRoutine(
            id: "drills-\(kind.rawValue)",
            title: "Form drills",
            phase: .drills,
            items: fill(pool, budget: budgetSeconds)
        )
    }

    /// All routines for a workout, in the order they are performed. Phases with nothing
    /// in them are dropped so the caller never renders an empty section.
    public static func routines(for kind: WorkoutKind, catalog: MovementCatalog) -> [MobilityRoutine] {
        [
            warmup(for: kind, catalog: catalog),
            drills(for: kind, catalog: catalog),
            cooldown(for: kind, catalog: catalog),
        ].filter { !$0.isEmpty }
    }

    /// Takes movements in catalog order until the next one would overrun the budget.
    /// Always yields at least one movement when the pool is non-empty, so a tight budget
    /// produces a short routine rather than nothing at all.
    private static func fill(_ pool: [Movement], budget: Int) -> [RoutineItem] {
        guard !pool.isEmpty, budget > 0 else { return [] }
        var items: [RoutineItem] = []
        var spent = 0
        for movement in pool {
            let cost = max(1, movement.durationSeconds)
            if spent + cost > budget, !items.isEmpty { break }
            items.append(RoutineItem(movement: movement, durationSeconds: cost))
            spent += cost
            if spent >= budget { break }
        }
        return items
    }
}
