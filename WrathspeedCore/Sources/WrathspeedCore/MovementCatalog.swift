import Foundation

/// What a movement is for. Strength work lives in `StrengthExercise`; this covers
/// everything that wraps around a run.
public enum MovementKind: String, Codable, CaseIterable, Sendable {
    case mobility
    case stretch
    case drill

    public var title: String {
        switch self {
        case .mobility: "Mobility"
        case .stretch: "Stretch"
        case .drill: "Drill"
        }
    }
}

/// Where a movement belongs relative to the run.
public enum MovementPhase: String, Codable, CaseIterable, Sendable {
    case warmup
    case drills
    case cooldown

    public var title: String {
        switch self {
        case .warmup: "Warm-up"
        case .drills: "Drills"
        case .cooldown: "Cool-down"
        }
    }
}

public struct Movement: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: MovementKind
    public var phase: MovementPhase
    public var bodyArea: String
    public var durationSeconds: Int
    public var symbolName: String
    public var cue: String
    // Beginner instructions, all optional: the catalog is being filled a movement at a time,
    // and every surface hides the block rather than rendering an empty one. This is the only
    // home for the copy -- `MobilityMovement` is a routine step and points here by id.
    /// Numbered steps, rendered one per numbered bullet.
    public var howToDoIt: [String]?
    public var shouldFeel: String?
    public var commonMistake: String?
    /// The regression to offer when the movement as written is too hard.
    public var easier: String?

    public init(
        id: String,
        name: String,
        kind: MovementKind,
        phase: MovementPhase,
        bodyArea: String,
        durationSeconds: Int,
        symbolName: String,
        cue: String,
        howToDoIt: [String]? = nil,
        shouldFeel: String? = nil,
        commonMistake: String? = nil,
        easier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.phase = phase
        self.bodyArea = bodyArea
        self.durationSeconds = durationSeconds
        self.symbolName = symbolName
        self.cue = cue
        self.howToDoIt = howToDoIt
        self.shouldFeel = shouldFeel
        self.commonMistake = commonMistake
        self.easier = easier
    }
}

public struct MovementCatalog: Codable, Equatable, Sendable {
    public var movements: [Movement]

    public init(movements: [Movement]) {
        self.movements = movements
    }

    public func inPhase(_ phase: MovementPhase) -> [Movement] {
        movements.filter { $0.phase == phase }
    }

    public func movement(id: String) -> Movement? {
        movements.first { $0.id == id }
    }

    public static func load(from bundle: Bundle? = nil) throws -> MovementCatalog {
        let bundle = bundle ?? Bundle.module
        guard let url = bundle.url(forResource: "movement_catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(MovementCatalog.self, from: Data(contentsOf: url))
    }
}
