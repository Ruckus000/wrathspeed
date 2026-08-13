import Foundation
import XCTest
@testable import WrathspeedCore

final class PlanAdjustmentServiceTests: XCTestCase {
    func testOverlayDoesNotMutateBaseWorkouts() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date())
        let quality = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: calendar.date(byAdding: .day, value: 1, to: day)!,
            kind: .tempo,
            title: "Tempo",
            steps: [],
            plannedDistanceMeters: 8_000,
            usesPaceTargets: true
        ))
        let base = [quality]
        let adjustment = N100Adjustment(start: day, dayCount: 7, mode: .reducedDifficulty, returnPace: .balanced)
        let effective = PlanAdjustmentService.effectiveWorkouts(base: base, adjustment: adjustment, calendar: calendar)
        XCTAssertEqual(base.first?.blueprint.kind, .tempo)
        XCTAssertEqual(effective.first?.blueprint.title, "Easy (reduced)")
    }

    func testDiffFutureUnstartedDetectsChanges() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let future = calendar.date(byAdding: .day, value: 3, to: today)!
        let current = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: future,
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        var moved = current
        moved.blueprint.date = calendar.date(byAdding: .day, value: 1, to: future)!
        let diff = PlanAdjustmentService.diffFutureUnstarted(current: [current], proposed: [moved], asOf: today, calendar: calendar)
        XCTAssertEqual(diff.moved.count, 1)
    }
}
