import Foundation
import XCTest
@testable import WrathspeedCore

final class AnchoredHealthImportTests: XCTestCase {
    func testIncrementalImportUsesAnchor() async throws {
        let mock = MockHealthImportService()
        mock.workouts = [
            ImportedHealthWorkout(
                healthKitUUID: UUID(),
                startedAt: Date().addingTimeInterval(-86_400),
                endedAt: Date(),
                duration: 1_800,
                distanceMeters: 5_000,
                location: .outdoor
            ),
            ImportedHealthWorkout(
                healthKitUUID: UUID(),
                startedAt: Date(),
                endedAt: Date().addingTimeInterval(1_800),
                duration: 1_800,
                distanceMeters: 4_000,
                location: .outdoor
            ),
        ]
        let since = Date().addingTimeInterval(-7 * 86_400)
        let first = try await mock.importWorkouts(anchor: nil, since: since)
        XCTAssertEqual(first.workouts.count, 2)
        XCTAssertNotNil(first.newAnchor)

        let second = try await mock.importWorkouts(anchor: first.newAnchor, since: since)
        XCTAssertEqual(mock.importCallCount, 2)
        XCTAssertNotNil(second.newAnchor)
    }

    func testUUIDDedupStillMergesAfterImport() {
        let uuid = UUID()
        let existing = WorkoutResult(
            workoutID: UUID(),
            startedAt: Date(),
            duration: 1_800,
            distanceMeters: 5_000,
            averagePaceSecPerKm: 360,
            location: .outdoor,
            healthKitUUID: uuid,
            source: .wrathspeedPhone
        )
        let imported = ImportedHealthWorkout(
            healthKitUUID: uuid,
            startedAt: existing.startedAt,
            endedAt: Date(),
            duration: 2_000,
            distanceMeters: 5_500,
            location: .outdoor
        )
        let merged = HealthImportMerge.merge(existing: [existing], imports: [imported])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].distanceMeters, 5_500)
    }
}
