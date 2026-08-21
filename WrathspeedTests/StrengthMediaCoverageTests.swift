import Foundation
import XCTest
@testable import Wrathspeed
@testable import WrathspeedCore

/// The strength half of the media coverage rule. The movement half lives in
/// `WrathspeedCoreTests/MovementMediaTests`; this one is here because the strength
/// catalog is owned by the app bundle rather than by WrathspeedCore.
final class StrengthMediaCoverageTests: XCTestCase {
    private func strengthCatalog() throws -> StrengthCatalog {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "Wrathspeed/strength_catalog.json"))
        return try JSONDecoder().decode(StrengthCatalog.self, from: data)
    }

    func testEveryExerciseHasEitherAClipOrASymbolToFallBackOn() throws {
        let library = try MediaLibrary()
        for exercise in try strengthCatalog().exercises where !library.hasClip(for: exercise.id) {
            XCTAssertFalse(
                exercise.symbolName.isEmpty,
                "\(exercise.id) has neither clip nor symbol"
            )
        }
    }

    /// Guards the id contract between the app's strength catalog and the bundled clips:
    /// renaming an exercise id silently drops its demo loop, which the UI would absorb
    /// as a symbol fallback rather than surface as a failure. Every strength exercise now
    /// has one, so the expected set is empty.
    func testKnownExercisesWithoutAClipAreOnlyTheDocumentedOnes() throws {
        let library = try MediaLibrary()
        let missing = try strengthCatalog().exercises
            .map(\.id)
            .filter { !library.hasClip(for: $0) }
            .sorted()
        XCTAssertEqual(
            missing,
            [],
            "Strength clip coverage changed. See docs/exercise-media-plan.md."
        )
    }
}
