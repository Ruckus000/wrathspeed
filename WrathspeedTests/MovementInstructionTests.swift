import Foundation
import XCTest
@testable import Wrathspeed
@testable import WrathspeedCore

/// Guards the instruction fields the redesign added, and the reps/hold split that decides
/// which card the strength player shows.
///
/// Both catalogs are being filled in a movement at a time, so these assert the *shape* --
/// that what is present is well-formed and that the split is coherent -- rather than a
/// coverage count that would fail every time a movement is written.
final class MovementInstructionTests: XCTestCase {
    private func strengthCatalog() throws -> StrengthCatalog {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "Wrathspeed/strength_catalog.json"))
        return try JSONDecoder().decode(StrengthCatalog.self, from: data)
    }

    // MARK: - Decoding

    /// The fields are optional and were added after the catalog shipped, so the thing worth
    /// proving is that a movement written *without* them still decodes.
    func testExercisesWithoutInstructionsDecodeToNil() throws {
        let json = Data(#"""
        {"exercises":[{"id":"x","name":"X","focus":["legsCore"],"equipment":["bodyweight"],
        "symbolName":"figure.core.training","defaultReps":10,"cue":"Do it."}]}
        """#.utf8)
        let exercise = try XCTUnwrap(JSONDecoder().decode(StrengthCatalog.self, from: json).exercises.first)
        XCTAssertNil(exercise.howToDoIt)
        XCTAssertNil(exercise.shouldFeel)
        XCTAssertNil(exercise.commonMistake)
        XCTAssertNil(exercise.easier)
        XCTAssertNil(exercise.holdSeconds, "absent holdSeconds must mean reps, not a zero-second hold")
    }

    func testInstructionFieldsRoundTripThroughTheRealCatalog() throws {
        let squat = try XCTUnwrap(strengthCatalog().exercises.first { $0.id == "bw-squat" })
        XCTAssertEqual(squat.howToDoIt?.count, 3)
        XCTAssertFalse(squat.shouldFeel?.isEmpty ?? true)
        XCTAssertFalse(squat.commonMistake?.isEmpty ?? true)
        XCTAssertFalse(squat.easier?.isEmpty ?? true)
    }

    /// A half-written entry is worse than an empty one: the card shows the headings it has
    /// content for, so a blank string would render a labelled void.
    func testNoInstructionFieldIsPresentButEmpty() throws {
        for exercise in try strengthCatalog().exercises {
            for (index, step) in (exercise.howToDoIt ?? []).enumerated() {
                XCTAssertFalse(
                    step.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(exercise.id) step \(index + 1) is blank"
                )
            }
            for (name, value) in [
                ("shouldFeel", exercise.shouldFeel),
                ("commonMistake", exercise.commonMistake),
                ("easier", exercise.easier),
            ] {
                guard let value else { continue }
                XCTAssertFalse(
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(exercise.id).\(name) is present but blank"
                )
            }
        }
    }

    // MARK: - The reps / hold split

    /// `plank` carried `defaultReps: 8` before `holdSeconds` existed -- a number that means
    /// nothing for a movement you do not rep out, and which the player would have shown as a
    /// rep target.
    func testIsometricsAndCarriesAreMarkedAsHolds() throws {
        let byID = Dictionary(uniqueKeysWithValues: try strengthCatalog().exercises.map { ($0.id, $0) })
        for id in ["plank", "side-plank", "farmer-carry"] {
            let exercise = try XCTUnwrap(byID[id], "\(id) missing from the catalog")
            let seconds = try XCTUnwrap(exercise.holdSeconds, "\(id) is timed, not repped")
            XCTAssertGreaterThan(seconds, 0)
        }
    }

    func testRepBasedExercisesAreNotMarkedAsHolds() throws {
        let byID = Dictionary(uniqueKeysWithValues: try strengthCatalog().exercises.map { ($0.id, $0) })
        for id in ["bw-squat", "push-up", "rdl", "db-row"] {
            let exercise = try XCTUnwrap(byID[id])
            XCTAssertNil(exercise.holdSeconds, "\(id) is counted in reps")
        }
    }

    /// Every hold needs a duration the player can count down from, and every non-hold needs a
    /// rep target. One or the other, never neither.
    func testEveryExerciseHasEitherRepsOrAHoldDuration() throws {
        for exercise in try strengthCatalog().exercises {
            if let seconds = exercise.holdSeconds {
                XCTAssertGreaterThan(seconds, 0, "\(exercise.id) holds for no time")
            } else {
                XCTAssertGreaterThan(exercise.defaultReps, 0, "\(exercise.id) has no rep target")
            }
        }
    }

    // MARK: - Movement catalog

    func testMovementCatalogCarriesTheSameOptionalFields() throws {
        let catalog = try MovementCatalog.load()
        XCTAssertFalse(catalog.movements.isEmpty)
        // Nothing is written here yet; the point is that the field exists and decodes as nil
        // rather than failing the load.
        for movement in catalog.movements {
            for step in movement.howToDoIt ?? [] {
                XCTAssertFalse(step.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
