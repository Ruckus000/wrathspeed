import Foundation
import SwiftData
import WrathspeedCore

struct PersistedState: Codable {
    var hasOnboarded: Bool
    var profile: RunnerProfile?
    var plan: TrainingPlan?
    var n100: N100Adjustment?
    var strengthPrefs: StrengthPreferences
    var strengthSessions: [StrengthSession]
    var cuesEnabled: Bool
    var freezeMileage: Bool
    var freezeMileageBaselineMeters: Double?
    var pendingVDOT: Double?
    var pendingVDOTReason: String?
    var results: [WorkoutResult]
    var liveMetrics: Set<LiveMetric>
    var dataDensity: DataDensity
    var cueStyle: CueStyle
    var mobilityPrefs: MobilityPreferences

    static let initial = PersistedState(
        hasOnboarded: false,
        profile: nil,
        plan: nil,
        n100: nil,
        strengthPrefs: StrengthPreferences(),
        strengthSessions: [],
        cuesEnabled: true,
        freezeMileage: false,
        freezeMileageBaselineMeters: nil,
        pendingVDOT: nil,
        pendingVDOTReason: nil,
        results: [],
        liveMetrics: [.time, .distance, .heartRate],
        dataDensity: .detailed,
        cueStyle: .standard,
        mobilityPrefs: MobilityPreferences()
    )

    enum CodingKeys: String, CodingKey {
        case hasOnboarded, profile, plan, n100, strengthPrefs, strengthSessions, cuesEnabled, freezeMileage, freezeMileageBaselineMeters, pendingVDOT, pendingVDOTReason, results, liveMetrics, dataDensity, cueStyle, mobilityPrefs
    }

    init(
        hasOnboarded: Bool, profile: RunnerProfile?, plan: TrainingPlan?, n100: N100Adjustment?, strengthPrefs: StrengthPreferences,
        strengthSessions: [StrengthSession], cuesEnabled: Bool, freezeMileage: Bool, freezeMileageBaselineMeters: Double? = nil,
        pendingVDOT: Double?, pendingVDOTReason: String?, results: [WorkoutResult],
        liveMetrics: Set<LiveMetric> = [.time, .distance, .heartRate],
        dataDensity: DataDensity = .detailed,
        cueStyle: CueStyle = .standard,
        mobilityPrefs: MobilityPreferences = MobilityPreferences()
    ) {
        self.hasOnboarded = hasOnboarded; self.profile = profile; self.plan = plan; self.n100 = n100
        self.strengthPrefs = strengthPrefs; self.strengthSessions = strengthSessions; self.cuesEnabled = cuesEnabled
        self.freezeMileage = freezeMileage; self.freezeMileageBaselineMeters = freezeMileageBaselineMeters
        self.pendingVDOT = pendingVDOT; self.pendingVDOTReason = pendingVDOTReason; self.results = results
        self.liveMetrics = liveMetrics; self.dataDensity = dataDensity; self.cueStyle = cueStyle
        self.mobilityPrefs = mobilityPrefs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hasOnboarded = try values.decode(Bool.self, forKey: .hasOnboarded)
        profile = try values.decodeIfPresent(RunnerProfile.self, forKey: .profile)
        plan = try values.decodeIfPresent(TrainingPlan.self, forKey: .plan)
        n100 = try values.decodeIfPresent(N100Adjustment.self, forKey: .n100)
        strengthPrefs = try values.decodeIfPresent(StrengthPreferences.self, forKey: .strengthPrefs) ?? StrengthPreferences()
        strengthSessions = try values.decodeIfPresent([StrengthSession].self, forKey: .strengthSessions) ?? []
        cuesEnabled = try values.decodeIfPresent(Bool.self, forKey: .cuesEnabled) ?? true
        freezeMileage = try values.decodeIfPresent(Bool.self, forKey: .freezeMileage) ?? false
        freezeMileageBaselineMeters = try values.decodeIfPresent(Double.self, forKey: .freezeMileageBaselineMeters)
        pendingVDOT = try values.decodeIfPresent(Double.self, forKey: .pendingVDOT)
        pendingVDOTReason = try values.decodeIfPresent(String.self, forKey: .pendingVDOTReason)
        results = try values.decodeIfPresent([WorkoutResult].self, forKey: .results) ?? []
        liveMetrics = try values.decodeIfPresent(Set<LiveMetric>.self, forKey: .liveMetrics) ?? [.time, .distance, .heartRate]
        dataDensity = try values.decodeIfPresent(DataDensity.self, forKey: .dataDensity) ?? .detailed
        cueStyle = try values.decodeIfPresent(CueStyle.self, forKey: .cueStyle) ?? .standard
        mobilityPrefs = try values.decodeIfPresent(MobilityPreferences.self, forKey: .mobilityPrefs) ?? MobilityPreferences()
    }
}

@Model
final class SnapshotEntity {
    var json: Data
    var updatedAt: Date

    init(json: Data, updatedAt: Date = Date()) {
        self.json = json
        self.updatedAt = updatedAt
    }
}

enum Persistence {
    static let decoder = JSONDecoder()
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static func load(from context: ModelContext) throws -> PersistedState {
        if try PersistenceMigration.hasMigrated(in: context) {
            return try VersionedPersistence.load(from: context)
        }
        return try loadLegacySnapshot(from: context)
    }

    static func loadLegacySnapshot(from context: ModelContext) throws -> PersistedState {
        decoder.dateDecodingStrategy = .iso8601
        let descriptor = FetchDescriptor<SnapshotEntity>()
        let snapshot = try context.fetch(descriptor).first
        if let data = snapshot?.json {
            return try decoder.decode(PersistedState.self, from: data)
        }
        return .initial
    }

    static func save(_ state: PersistedState, to context: ModelContext) throws {
        if try PersistenceMigration.hasMigrated(in: context) {
            try VersionedPersistence.save(state, to: context)
            return
        }
        let data = try encoder.encode(state)
        let descriptor = FetchDescriptor<SnapshotEntity>()
        if let existing = try context.fetch(descriptor).first {
            existing.json = data
            existing.updatedAt = Date()
        } else {
            context.insert(SnapshotEntity(json: data))
        }
        try context.save()
    }

    static func reset(from context: ModelContext) throws {
        for entity in try context.fetch(FetchDescriptor<SnapshotEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<MigrationMarkerEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<AppSettingsEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<TrainingPlanEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<ScheduledWorkoutEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<WorkoutResultEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<StrengthSessionEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<StrengthSessionResultEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<MobilitySessionEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<MobilitySessionResultEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<PlanAdjustmentEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<PlanChangeEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<ActiveSessionSnapshotEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<PendingHealthOpEntity>()) {
            context.delete(entity)
        }
        try context.save()
    }
}

enum AppPersistenceError: LocalizedError, Equatable {
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "Storage is not ready yet."
        }
    }
}

@MainActor
final class AppStateRepository {
    private let context: ModelContext
    private(set) var migrationError: String?
    var forceSaveFailure = false
    var forceSaveFailureAfterMutation = false
    var forceGuidedResultSaveFailure = false

    init(context: ModelContext) {
        self.context = context
    }

    func load() throws -> PersistedState {
        migrationError = nil
        if try PersistenceMigration.hasMigrated(in: context) {
            return try VersionedPersistence.load(from: context)
        }
        let legacy = try Persistence.loadLegacySnapshot(from: context)
        do {
            try PersistenceMigration.migrate(legacy, into: context)
        } catch {
            migrationError = error.localizedDescription
            return legacy
        }
        return try VersionedPersistence.load(from: context)
    }

    func save(_ state: PersistedState) throws {
        if forceSaveFailure {
            throw NSError(domain: "WrathspeedTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated save failure"])
        }
        do {
            if try PersistenceMigration.hasMigrated(in: context) {
                try VersionedPersistence.save(state, to: context, beforeCommit: {
                    if forceSaveFailureAfterMutation {
                        throw NSError(
                            domain: "WrathspeedTests",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Simulated save failure after mutation"]
                        )
                    }
                })
            } else {
                try Persistence.save(state, to: context)
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func reset() throws {
        try Persistence.reset(from: context)
    }
}
