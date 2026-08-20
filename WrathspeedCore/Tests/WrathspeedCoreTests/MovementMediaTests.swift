import Foundation
import Testing
@testable import WrathspeedCore

@Suite("Movement catalog")
struct MovementCatalogTests {
    @Test("Catalog loads and every movement is well formed")
    func catalogLoads() throws {
        let catalog = try MovementCatalog.load()
        #expect(!catalog.movements.isEmpty)
        for movement in catalog.movements {
            #expect(!movement.name.isEmpty)
            #expect(!movement.cue.isEmpty)
            #expect(!movement.symbolName.isEmpty, "\(movement.id) needs a symbol for the media fallback")
            #expect(movement.durationSeconds > 0, "\(movement.id) has no duration")
        }
    }

    @Test("Movement ids are unique")
    func idsUnique() throws {
        let ids = try MovementCatalog.load().movements.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every phase has movements to draw from")
    func phasesPopulated() throws {
        let catalog = try MovementCatalog.load()
        for phase in MovementPhase.allCases {
            #expect(!catalog.inPhase(phase).isEmpty, "\(phase.rawValue) is empty")
        }
    }
}

@Suite("Media library")
struct MediaLibraryTests {
    @Test("Manifest loads and resolves clips to real bundled files")
    func manifestResolves() throws {
        let library = try MediaLibrary()
        #expect(!library.clips.isEmpty)
        // Every manifest entry must resolve; an entry pointing at a missing file means
        // the build script and the bundle have drifted apart.
        for id in library.clips.keys {
            #expect(library.url(for: id) != nil, "\(id) is in the manifest but has no bundled file")
        }
    }

    @Test("Every catalog movement either has a clip or a symbol to fall back to")
    func coverageIsTotal() throws {
        let library = try MediaLibrary()
        let movements = try MovementCatalog.load().movements
        let exercises = try StrengthPlanner.loadCatalog().exercises

        for movement in movements where !library.hasClip(for: movement.id) {
            #expect(!movement.symbolName.isEmpty, "\(movement.id) has neither clip nor symbol")
        }
        for exercise in exercises where !library.hasClip(for: exercise.id) {
            #expect(!exercise.symbolName.isEmpty, "\(exercise.id) has neither clip nor symbol")
        }
    }

    @Test("Missing ids resolve to nil rather than trapping")
    func missingIDsAreSafe() throws {
        let library = try MediaLibrary()
        #expect(library.url(for: "no-such-movement") == nil)
        #expect(library.clip(for: "no-such-movement") == nil)
        #expect(library.hasClip(for: "no-such-movement") == false)
    }

    @Test("An empty library degrades to symbol-only instead of failing")
    func emptyLibraryIsUsable() {
        let library = MediaLibrary.empty
        #expect(library.url(for: "bw-squat") == nil)
        #expect(library.availableIDs.isEmpty)
    }
}

@Suite("Mobility planner")
struct MobilityPlannerTests {
    private func catalog() throws -> MovementCatalog { try MovementCatalog.load() }

    @Test("Warm-up and cool-down are produced for every workout kind")
    func routinesForEveryKind() throws {
        let catalog = try catalog()
        for kind in WorkoutKind.allCases {
            let warmup = MobilityPlanner.warmup(for: kind, catalog: catalog)
            let cooldown = MobilityPlanner.cooldown(for: kind, catalog: catalog)
            #expect(!warmup.isEmpty, "\(kind.rawValue) has no warm-up")
            #expect(!cooldown.isEmpty, "\(kind.rawValue) has no cool-down")
        }
    }

    @Test("Routines respect their time budget")
    func routinesFitBudget() throws {
        let catalog = try catalog()
        for kind in WorkoutKind.allCases {
            let warmup = MobilityPlanner.warmup(for: kind, catalog: catalog)
            #expect(warmup.totalSeconds <= MobilityPlanner.warmupBudget(for: kind))
        }
    }

    @Test("A tight budget yields a short routine, never an empty one")
    func tinyBudgetStillReturnsWork() throws {
        let routine = MobilityPlanner.warmup(for: .easy, catalog: try catalog(), budgetSeconds: 1)
        #expect(routine.items.count == 1)
    }

    @Test("Drills only appear on quality days")
    func drillsOnQualityOnly() throws {
        let catalog = try catalog()
        for kind in WorkoutKind.allCases {
            let drills = MobilityPlanner.drills(for: kind, catalog: catalog)
            #expect(drills.isEmpty != kind.isQuality, "drills wrong for \(kind.rawValue)")
        }
    }

    @Test("Selection is deterministic")
    func deterministic() throws {
        let catalog = try catalog()
        let first = MobilityPlanner.routines(for: .intervals, catalog: catalog)
        let second = MobilityPlanner.routines(for: .intervals, catalog: catalog)
        #expect(first == second)
    }

    @Test("An empty catalog produces no routines instead of crashing")
    func emptyCatalogIsSafe() {
        let routines = MobilityPlanner.routines(for: .easy, catalog: MovementCatalog(movements: []))
        #expect(routines.isEmpty)
    }
}
