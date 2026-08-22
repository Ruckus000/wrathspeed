import CoreGraphics
import XCTest
@testable import Wrathspeed

final class WSMarkTests: XCTestCase {
    // The spec calls this rule "no exceptions": below 24pt the cuts fill in and the mark
    // reads as dirt. If the threshold ever drifts, every small placement degrades quietly.
    func testMarkGoesSolidBelowTwentyFourPoints() {
        XCTAssertEqual(WSMark(size: 128).resolvedVariant, .raked)
        XCTAssertEqual(WSMark(size: 24).resolvedVariant, .raked)
        XCTAssertEqual(WSMark(size: 23.9).resolvedVariant, .solid)
        XCTAssertEqual(WSMark(size: 12).resolvedVariant, .solid)
    }

    func testExplicitVariantOverridesTheSizeRule() {
        XCTAssertEqual(WSMark(size: 12, variant: .raked).resolvedVariant, .raked)
        XCTAssertEqual(WSMark(size: 128, variant: .plate).resolvedVariant, .plate)
    }

    func testEveryVariantDrawsInsideTheArtboard() {
        for variant in [WSMarkVariant.raked, .solid, .plate] {
            let path = WSMarkGeometry.path(variant, fitting: WSMarkGeometry.artboard)
            XCTAssertFalse(path.isEmpty, "\(variant) produced no geometry")
            XCTAssertTrue(
                WSMarkGeometry.artboard.insetBy(dx: -0.5, dy: -0.5).contains(path.boundingBoxOfPath),
                "\(variant) spills outside the artboard: \(path.boundingBoxOfPath)"
            )
        }
    }

    // The cuts take material out of the stroke without changing the silhouette, so the
    // raked and solid marks have to sit on exactly the same optical footprint.
    func testCutsDoNotChangeTheSilhouette() {
        let raked = WSMarkGeometry.raked.boundingBoxOfPath
        let solid = WSMarkGeometry.solid.boundingBoxOfPath
        XCTAssertEqual(raked.minX, solid.minX, accuracy: 0.01)
        XCTAssertEqual(raked.minY, solid.minY, accuracy: 0.01)
        XCTAssertEqual(raked.maxX, solid.maxX, accuracy: 0.01)
        XCTAssertEqual(raked.maxY, solid.maxY, accuracy: 0.01)
    }

    // The spec's measurements: a 137u x 134u mark inside a square 170u artboard.
    func testMarkMatchesTheSpecifiedProportions() {
        let bounds = WSMarkGeometry.solid.boundingBoxOfPath
        XCTAssertEqual(bounds.width, 137, accuracy: 1)
        XCTAssertEqual(bounds.height, 134, accuracy: 1)
    }

    // It is the artboard that gets centred, not the mark: the mark sits a little off
    // centre inside it, which is what keeps the lean from looking like a mistake.
    func testPathAspectFitsIntoNonSquareRects() {
        let wide = CGRect(x: 20, y: 40, width: 400, height: 100)
        let bounds = WSMarkGeometry.path(.raked, fitting: wide).boundingBoxOfPath
        XCTAssertTrue(wide.contains(bounds), "\(bounds) is not inside \(wide)")

        // Fitted to the short side, uniformly.
        let scale = wide.height / WSMarkGeometry.artboard.height
        let unfitted = WSMarkGeometry.raked.boundingBoxOfPath
        XCTAssertEqual(bounds.width, unfitted.width * scale, accuracy: 0.01)
        XCTAssertEqual(bounds.height, unfitted.height * scale, accuracy: 0.01)

        // The artboard's own margins survive the fit, so the mark keeps its breathing room.
        XCTAssertEqual(bounds.minY - wide.minY, 18 * scale, accuracy: 0.01)
        XCTAssertEqual(wide.maxY - bounds.maxY, 18 * scale, accuracy: 0.01)
    }
}
