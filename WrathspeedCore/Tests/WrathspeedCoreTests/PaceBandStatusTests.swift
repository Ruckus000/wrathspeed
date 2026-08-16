import Testing
@testable import WrathspeedCore

struct PaceBandStatusTests {
    @Test func pausedTakesPrecedence() {
        #expect(
            PaceBandStatus.evaluate(currentPaceSecPerKm: 300, targetSecPerKm: 300, paused: true) == .paused
        )
    }

    @Test func missingOrNonPositiveDataIsUnavailable() {
        #expect(
            PaceBandStatus.evaluate(currentPaceSecPerKm: nil, targetSecPerKm: 300, paused: false) == .unavailable
        )
        #expect(
            PaceBandStatus.evaluate(currentPaceSecPerKm: 300, targetSecPerKm: nil, paused: false) == .unavailable
        )
        #expect(
            PaceBandStatus.evaluate(currentPaceSecPerKm: 0, targetSecPerKm: 300, paused: false) == .unavailable
        )
    }

    @Test func lowerSecondsPerDistanceIsTooFast() {
        #expect(
            PaceBandStatus.evaluate(currentPaceSecPerKm: 280, targetSecPerKm: 300, paused: false) == .tooFast
        )
    }

    @Test func higherSecondsPerDistanceIsTooSlow() {
        #expect(
            PaceBandStatus.evaluate(currentPaceSecPerKm: 320, targetSecPerKm: 300, paused: false) == .tooSlow
        )
    }

    @Test func withinFivePercentIsInZone() {
        #expect(
            PaceBandStatus.evaluate(currentPaceSecPerKm: 300, targetSecPerKm: 300, paused: false) == .inZone
        )
        #expect(
            PaceBandStatus.evaluate(currentPaceSecPerKm: 300 * 0.96, targetSecPerKm: 300, paused: false) == .inZone
        )
        #expect(
            PaceBandStatus.evaluate(currentPaceSecPerKm: 300 * 1.04, targetSecPerKm: 300, paused: false) == .inZone
        )
    }
}
