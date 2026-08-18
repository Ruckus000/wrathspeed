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
        guard HKHealthStore.isHealthDataAvailable() else {
            return HealthImportResult(workouts: [])
        }
        let workoutType = HKObjectType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let hkAnchor = anchor.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: workoutType,
                predicate: runningPredicate,
                anchor: hkAnchor,
                limit: HKObjectQueryNoLimit
            ) { [healthStore] _, samples, deletedObjects, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                let deletedUUIDs = Set((deletedObjects as? [HKWorkout])?.map(\.uuid) ?? [])
                let filtered = workouts.filter { $0.startDate >= since }
                Task {
                    var imports: [ImportedHealthWorkout] = []
                    for workout in filtered {
                        guard let base = Self.mapWorkout(workout) else { continue }
                        let enriched = await Self.enrich(workout: workout, base: base, store: healthStore)
                        imports.append(enriched)
                    }
                    let anchorData = newAnchor.flatMap {
                        try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
                    }
                    continuation.resume(
                        returning: HealthImportResult(
                            workouts: imports,
                            newAnchor: anchorData,
                            deletedHealthKitUUIDs: deletedUUIDs
                        )
                    )
                }
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

    private static func enrich(workout: HKWorkout, base: ImportedHealthWorkout, store: HKHealthStore) async -> ImportedHealthWorkout {
        var enriched = base
        enriched.heartRateAverage = await averageHeartRate(for: workout, store: store)
        enriched.energyKilocalories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        enriched.cadenceAverage = await averageCadence(for: workout, store: store)
        enriched.route = await routePoints(for: workout, store: store)
        return enriched
    }

    private static func averageHeartRate(for workout: HKWorkout, store: HKHealthStore) async -> Double? {
        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private static func averageCadence(for workout: HKWorkout, store: HKHealthStore) async -> Double? {
        let stepType = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )
        let steps: Double? = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .count()))
            }
            store.execute(query)
        }
        guard let steps, workout.duration > 0 else { return nil }
        return (steps / workout.duration) * 60.0
    }

    private static func routePoints(for workout: HKWorkout, store: HKHealthStore) async -> [RoutePoint]? {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            store.execute(query)
        }
        guard let route = routes.first else { return nil }

        var points: [RoutePoint] = []
        return await withCheckedContinuation { continuation in
            let routeQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, _ in
                if let locations {
                    for location in locations {
                        points.append(
                            RoutePoint(
                                latitude: location.coordinate.latitude,
                                longitude: location.coordinate.longitude,
                                timestamp: location.timestamp
                            )
                        )
                    }
                }
                if done {
                    continuation.resume(returning: points.isEmpty ? nil : points)
                }
            }
            store.execute(routeQuery)
        }
    }
}
#endif
