import Foundation
import Testing
@testable import WrathspeedCore

struct UnitsFormattingTests {
    @Test func compactDistanceUsesSelectedUnit() {
        #expect(Units.compactDistance(5_000, unit: .kilometers) == "5.00 KM")
        #expect(Units.compactDistance(Units.metersPerMile, unit: .miles) == "1.00 MI")
    }

    @Test func compactPaceConvertsSecondsPerKilometer() {
        #expect(Units.compactPace(secondsPerKilometer: 300, unit: .kilometers) == "5:00 /KM")
        let milePace = Units.compactPace(secondsPerKilometer: 300, unit: .miles)
        #expect(milePace.hasSuffix(" /MI"))
        #expect(milePace != "5:00 /MI")
        #expect(Units.paceClock(secondsPerKilometer: 300, unit: .miles) == "8:03")
    }

    @Test func compactSuffixIsUppercase() {
        #expect(Units.compactUnitSuffix(.kilometers) == "KM")
        #expect(Units.compactUnitSuffix(.miles) == "MI")
    }
}
