import Foundation
import Testing
@testable import WrathspeedCore

struct SkipStepTests {
    @Test func skipMovesToNextStep() {
        let steps = [
            WorkoutStep(name: "A", target: .distance(meters: 5_000), intensity: .zone(.easy)),
            WorkoutStep(name: "B", target: .distance(meters: 5_000), intensity: .zone(.easy)),
        ]
        var stepper = WorkoutStepper(
            blueprint: WorkoutBlueprint(
                date: Date(),
                kind: .easy,
                title: "t",
                steps: steps,
                plannedDistanceMeters: 10_000,
                usesPaceTargets: true
            )
        )
        let events = stepper.skipCurrent(metrics: LiveMetrics(elapsed: 10, distanceMeters: 100))
        #expect(stepper.stepIndex == 1)
        #expect(events.contains { if case .started(1, _) = $0 { return true }; return false })
    }
}
