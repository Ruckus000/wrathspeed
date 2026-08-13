import Foundation

/// Jack Daniels VDOT paces and Riegel race-time predictions.
public enum PaceCalculator {
    /// Percent of VDOT (VO2) used for each training zone.
    private static let zonePercents: [PaceZone: Double] = [
        .easy: 0.70,
        .recovery: 0.65,
        .marathon: 0.841,
        .threshold: 0.883,
        .interval: 0.976,
        .repetition: 1.035,
    ]

    public static func vdot(distanceMeters: Double, duration: TimeInterval) -> Double {
        let minutes = duration / 60
        guard minutes > 0, distanceMeters > 0 else { return 0 }
        let velocity = distanceMeters / minutes
        return vo2(velocityMetersPerMinute: velocity) / percentVO2Max(minutes: minutes)
    }

    public static func percentVO2(for zone: PaceZone) -> Double {
        zonePercents[zone] ?? 0.70
    }

    public static func zones(vdot: Double) -> PaceZones {
        var map: [PaceZone: TimeInterval] = [:]
        for zone in PaceZone.allCases {
            let percent = zonePercents[zone] ?? 0.70
            let velocity = velocity(fromVO2: vdot * percent)
            map[zone] = paceSecondsPerKilometer(velocityMetersPerMinute: velocity)
        }
        return PaceZones(secondsPerKilometer: map)
    }

    /// Predict time at `targetDistanceMeters` from a known race using Riegel.
    public static func riegelPredict(
        knownDistanceMeters: Double,
        knownDuration: TimeInterval,
        targetDistanceMeters: Double,
        exponent: Double = 1.06
    ) -> TimeInterval {
        guard knownDistanceMeters > 0 else { return 0 }
        return knownDuration * pow(targetDistanceMeters / knownDistanceMeters, exponent)
    }

    public static func predictedDuration(vdot: Double, distanceMeters: Double) -> TimeInterval {
        var low: TimeInterval = 60
        var high: TimeInterval = 12 * 3600
        for _ in 0..<40 {
            let mid = (low + high) / 2
            let estimated = Self.vdot(distanceMeters: distanceMeters, duration: mid)
            if estimated > vdot {
                low = mid
            } else {
                high = mid
            }
        }
        return (low + high) / 2
    }

    public static func vo2(velocityMetersPerMinute v: Double) -> Double {
        -4.60 + 0.182258 * v + 0.000104 * v * v
    }

    public static func percentVO2Max(minutes: Double) -> Double {
        0.8
            + 0.1894393 * exp(-0.012778 * minutes)
            + 0.2989558 * exp(-0.1932605 * minutes)
    }

    public static func velocity(fromVO2 vo2Value: Double) -> Double {
        let a = 0.000104
        let b = 0.182258
        let c = -4.60 - vo2Value
        let discriminant = max(0, b * b - 4 * a * c)
        return (-b + sqrt(discriminant)) / (2 * a)
    }

    public static func paceSecondsPerKilometer(velocityMetersPerMinute: Double) -> TimeInterval {
        guard velocityMetersPerMinute > 0 else { return 0 }
        return 60_000 / velocityMetersPerMinute
    }
}
