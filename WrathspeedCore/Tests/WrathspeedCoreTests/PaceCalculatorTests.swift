import Foundation
import Testing
@testable import WrathspeedCore

struct PaceCalculatorTests {
    @Test func fiveKIn20MinutesIsAboutVDOT50() {
        let vdot = PaceCalculator.vdot(distanceMeters: 5_000, duration: 20 * 60)
        #expect(abs(vdot - 49.8) < 0.5)
    }

    @Test func fasterRaceYieldsHigherVDOT() {
        let slower = PaceCalculator.vdot(distanceMeters: 5_000, duration: 25 * 60)
        let faster = PaceCalculator.vdot(distanceMeters: 5_000, duration: 18 * 60)
        #expect(faster > slower)
    }

    @Test func zonesGetFasterFromEasyToInterval() {
        let zones = PaceCalculator.zones(vdot: 50)
        let easy = zones.secondsPerKilometer(for: .easy) ?? 0
        let threshold = zones.secondsPerKilometer(for: .threshold) ?? 0
        let interval = zones.secondsPerKilometer(for: .interval) ?? 0
        #expect(easy > threshold)
        #expect(threshold > interval)
        #expect(easy > 0)
    }

    @Test func riegelScalesWithDistance() {
        let fiveK = 20 * 60.0
        let tenK = PaceCalculator.riegelPredict(
            knownDistanceMeters: 5_000,
            knownDuration: fiveK,
            targetDistanceMeters: 10_000
        )
        #expect(tenK > fiveK * 2)
        #expect(tenK < fiveK * 2.2)
    }

    @Test func predictedDurationRoundTripsNearInput() {
        let duration: TimeInterval = 20 * 60
        let vdot = PaceCalculator.vdot(distanceMeters: 5_000, duration: duration)
        let predicted = PaceCalculator.predictedDuration(vdot: vdot, distanceMeters: 5_000)
        #expect(abs(predicted - duration) < 5)
    }

    @Test func localeUnitsFollowMeasurementSystem() {
        #expect(DistanceUnit.default(locale: Locale(identifier: "fr_FR")) == .kilometers)
        #expect(DistanceUnit.default(locale: Locale(identifier: "en_US")) == .miles)
    }

    @Test func metersRoundTrip() {
        let km = Units.meters(fromDisplay: 5, unit: .kilometers)
        #expect(abs(km - 5_000) < 0.01)
        let miles = Units.meters(fromDisplay: 1, unit: .miles)
        #expect(abs(miles - 1_609.344) < 0.01)
    }
}
