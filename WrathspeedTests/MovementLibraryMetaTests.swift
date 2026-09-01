import Foundation
import XCTest
@testable import Wrathspeed
@testable import WrathspeedCore

/// The movement library's one-line summary under each name.
///
/// A hold has no reps, but the planner still needs a number in `defaultReps`, so a plank
/// carries 8. The library printed it: "8 REPS" sat under SIDE PLANK on the row and again on
/// the detail screen, directly above a step reading "Hold, breathing normally". Nothing caught
/// it because the label is only ever compared against itself.
final class MovementLibraryMetaTests: XCTestCase {
    private func strengthCatalog() throws -> StrengthCatalog {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "Wrathspeed/strength_catalog.json"))
        return try JSONDecoder().decode(StrengthCatalog.self, from: data)
    }

    func testHoldsAreSummarisedInSecondsAndNeverInReps() throws {
        let holds = try strengthCatalog().exercises.filter { $0.holdSeconds != nil }
        XCTAssertFalse(holds.isEmpty, "the catalog should still carry hold movements")

        for exercise in holds {
            let seconds = try XCTUnwrap(exercise.holdSeconds)
            let meta = MovementLibraryView.meta(for: exercise)
            XCTAssertEqual(meta, "\(seconds)s hold", "\(exercise.id) should be summarised as a hold")
            XCTAssertFalse(meta.contains("rep"), "\(exercise.id) is a hold, not reps")
        }
    }

    func testRepMovementsStillReadInReps() throws {
        let repped = try strengthCatalog().exercises.filter { $0.holdSeconds == nil }
        XCTAssertFalse(repped.isEmpty)

        for exercise in repped {
            XCTAssertEqual(
                MovementLibraryView.meta(for: exercise),
                "\(exercise.defaultReps) reps",
                "\(exercise.id) should still be summarised in reps"
            )
        }
    }
}
