import Foundation
import HealthKit
import SwiftData
import WrathspeedCore

protocol HealthImporting: Sendable {
    var authorizationDenied: Bool { get }
    func requestAuthorization() async throws
    func importWorkouts(since: Date, existing: [WorkoutResult]) async throws -> [ImportedHealthWorkout]
}

final class LiveHealthImportService: HealthImporting, @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private(set) var authorizationDenied = false

    func requestAuthorization() async throws {
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

    func importWorkouts(since: Date, existing: [WorkoutResult]) async throws -> [ImportedHealthWorkout] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
        let workoutType = HKObjectType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let compound = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, runningPredicate])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: compound,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                let imports = workouts.compactMap { Self.mapWorkout($0) }
                continuation.resume(returning: imports)
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

enum HealthImportAnchorStore {
    static func load(from context: ModelContext) throws -> Data? {
        try context.fetch(FetchDescriptor<AppSettingsEntity>()).first?.healthImportAnchorData
    }

    static func save(_ anchor: Data, to context: ModelContext) throws {
        guard let settings = try context.fetch(FetchDescriptor<AppSettingsEntity>()).first else { return }
        settings.healthImportAnchorData = anchor
        try context.save()
    }
}
