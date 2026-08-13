import Foundation
import WrathspeedCore

#if canImport(HealthKit)
import HealthKit

public final class LiveHealthImportService: HealthImporting, @unchecked Sendable {
    private let healthStore = HKHealthStore()
    public private(set) var authorizationDenied = false

    public init() {}

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.stepCount),
        ]
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
        } catch {
            authorizationDenied = true
            throw error
        }
    }

    public func importWorkouts(anchor: Data?, since: Date) async throws -> HealthImportResult {
        guard HKHealthStore.isHealthDataAvailable() else { return HealthImportResult(workouts: []) }
        let workoutType = HKObjectType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let hkAnchor = anchor.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: workoutType,
                predicate: runningPredicate,
                anchor: hkAnchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                let imports = workouts
                    .filter { $0.startDate >= since }
                    .compactMap(Self.mapWorkout)
                let anchorData = newAnchor.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
                continuation.resume(returning: HealthImportResult(workouts: imports, newAnchor: anchorData))
            }
            healthStore.execute(query)
        }
    }

    private static func mapWorkout(_ workout: HKWorkout) -> ImportedHealthWorkout? {
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
        guard distance > 0 || workout.duration > 60 else { return nil }
        let location: RunLocation = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool == true ? .treadmill : .outdoor
        return ImportedHealthWorkout(
            healthKitUUID: workout.uuid,
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            duration: workout.duration,
            distanceMeters: distance,
            location: location,
            source: .appleHealth
        )
    }
}
#endif
