import Foundation
import XCTest
@testable import WrathspeedCore

final class InstantWorkoutBuilderTests: XCTestCase {
    func testEasyDistanceRoundTrip() throws {
        let request = InstantWorkoutRequest(kind: .easy, location: .outdoor, distanceMeters: 8_000)
        try InstantWorkoutValidation.validate(request)
        let blueprint = try InstantWorkoutBuilder.build(request)
        XCTAssertEqual(blueprint.kind, .easy)
        XCTAssertGreaterThan(blueprint.plannedDistanceMeters, 0)
    }

    func testRejectsOversizedDistance() {
        let request = InstantWorkoutRequest(kind: .easy, location: .outdoor, distanceMeters: 200_000)
        XCTAssertThrowsError(try InstantWorkoutValidation.validate(request))
    }
}
