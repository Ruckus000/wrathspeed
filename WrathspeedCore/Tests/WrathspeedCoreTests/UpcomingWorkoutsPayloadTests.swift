import Foundation
import Testing
@testable import WrathspeedCore

struct UpcomingWorkoutsPayloadTests {
    @Test func decodesLegacyPayloadWithoutUnit() throws {
        let blueprint = WorkoutBlueprint(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            kind: .easy,
            title: "Easy run",
            steps: [WorkoutStep(name: "Easy", target: .distance(meters: 5_000), intensity: .zone(.easy))],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        )
        let payload = UpcomingWorkoutsPayload(blueprints: [blueprint], vdot: 46.2, unit: .miles)
        let encoded = try JSONEncoder().encode(payload)
        var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        json.removeValue(forKey: "unit")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(UpcomingWorkoutsPayload.self, from: legacy)
        #expect(decoded.unit == nil)
        #expect(decoded.vdot == 46.2)
        #expect(decoded.blueprints.count == 1)
        #expect(decoded.blueprints.first?.title == "Easy run")
    }

    @Test func roundTripsSelectedUnit() throws {
        let payload = UpcomingWorkoutsPayload(blueprints: [], vdot: 50, unit: .miles)
        let decoded = try JSONDecoder().decode(
            UpcomingWorkoutsPayload.self,
            from: try JSONEncoder().encode(payload)
        )
        #expect(decoded.unit == .miles)
    }
}
