import Foundation
import SwiftData
import WrathspeedCore

@Model
final class MigrationMarkerEntity {
    var schemaVersion: Int
    var migratedAt: Date

    init(schemaVersion: Int, migratedAt: Date = Date()) {
        self.schemaVersion = schemaVersion
        self.migratedAt = migratedAt
    }
}

@Model
final class AppSettingsEntity {
    var id: UUID
    var hasOnboarded: Bool
    var profileData: Data?
    var strengthPrefsData: Data
    var cuesEnabled: Bool
    var freezeMileage: Bool
    var freezeMileageBaselineMeters: Double?
    var pendingVDOT: Double?
    var pendingVDOTReason: String?
    var liveMetricsData: Data
    var dataDensityRaw: String
    var cueStyleRaw: String
    var mobilityPrefsData: Data?
    var healthImportAnchorData: Data?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        hasOnboarded: Bool,
        profileData: Data?,
        strengthPrefsData: Data,
        cuesEnabled: Bool,
        freezeMileage: Bool,
        freezeMileageBaselineMeters: Double?,
        pendingVDOT: Double?,
        pendingVDOTReason: String?,
        liveMetricsData: Data,
        dataDensityRaw: String,
        cueStyleRaw: String,
        mobilityPrefsData: Data? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.hasOnboarded = hasOnboarded
        self.profileData = profileData
        self.strengthPrefsData = strengthPrefsData
        self.cuesEnabled = cuesEnabled
        self.freezeMileage = freezeMileage
        self.freezeMileageBaselineMeters = freezeMileageBaselineMeters
        self.pendingVDOT = pendingVDOT
        self.pendingVDOTReason = pendingVDOTReason
        self.liveMetricsData = liveMetricsData
        self.dataDensityRaw = dataDensityRaw
        self.cueStyleRaw = cueStyleRaw
        self.mobilityPrefsData = mobilityPrefsData
        self.updatedAt = updatedAt
    }
}

@Model
final class TrainingPlanEntity {
    var id: UUID
    var lifecycleStateRaw: String
    var goalData: Data
    var profileData: Data
    var generatedAt: Date
    var isActive: Bool

    init(
        id: UUID,
        lifecycleStateRaw: String,
        goalData: Data,
        profileData: Data,
        generatedAt: Date,
        isActive: Bool
    ) {
        self.id = id
        self.lifecycleStateRaw = lifecycleStateRaw
        self.goalData = goalData
        self.profileData = profileData
        self.generatedAt = generatedAt
        self.isActive = isActive
    }
}

@Model
final class ScheduledWorkoutEntity {
    var id: UUID
    var planID: UUID
    var payloadData: Data
    var payloadVersion: Int

    init(id: UUID, planID: UUID, payloadData: Data, payloadVersion: Int = 1) {
        self.id = id
        self.planID = planID
        self.payloadData = payloadData
        self.payloadVersion = payloadVersion
    }
}

@Model
final class WorkoutResultEntity {
    var id: UUID
    var scheduledWorkoutID: UUID?
    var payloadData: Data
    var payloadVersion: Int
    var sourceRaw: String
    var healthKitUUID: UUID?
    var matchStateRaw: String
    var matchScheduledWorkoutID: UUID?

    init(
        id: UUID,
        scheduledWorkoutID: UUID?,
        payloadData: Data,
        payloadVersion: Int = 1,
        sourceRaw: String = WorkoutSource.wrathspeedPhone.rawValue,
        healthKitUUID: UUID? = nil,
        matchStateRaw: String = WorkoutMatchState.unmatched.rawValue,
        matchScheduledWorkoutID: UUID? = nil
    ) {
        self.id = id
        self.scheduledWorkoutID = scheduledWorkoutID
        self.payloadData = payloadData
        self.payloadVersion = payloadVersion
        self.sourceRaw = sourceRaw
        self.healthKitUUID = healthKitUUID
        self.matchStateRaw = matchStateRaw
        self.matchScheduledWorkoutID = matchScheduledWorkoutID
    }
}

@Model
final class StrengthSessionEntity {
    var id: UUID
    var payloadData: Data
    var payloadVersion: Int

    init(id: UUID, payloadData: Data, payloadVersion: Int = 1) {
        self.id = id
        self.payloadData = payloadData
        self.payloadVersion = payloadVersion
    }
}

@Model
final class StrengthSessionResultEntity {
    var id: UUID
    var sessionID: UUID
    var payloadData: Data
    var payloadVersion: Int

    init(id: UUID, sessionID: UUID, payloadData: Data, payloadVersion: Int = 1) {
        self.id = id
        self.sessionID = sessionID
        self.payloadData = payloadData
        self.payloadVersion = payloadVersion
    }
}

@Model
final class MobilitySessionEntity {
    var id: UUID
    var payloadData: Data
    var payloadVersion: Int

    init(id: UUID, payloadData: Data, payloadVersion: Int = 1) {
        self.id = id
        self.payloadData = payloadData
        self.payloadVersion = payloadVersion
    }
}

@Model
final class MobilitySessionResultEntity {
    var id: UUID
    var sessionID: UUID
    var payloadData: Data
    var payloadVersion: Int

    init(id: UUID, sessionID: UUID, payloadData: Data, payloadVersion: Int = 1) {
        self.id = id
        self.sessionID = sessionID
        self.payloadData = payloadData
        self.payloadVersion = payloadVersion
    }
}

@Model
final class PlanAdjustmentEntity {
    var id: UUID
    var payloadData: Data
    var payloadVersion: Int
    var isActive: Bool

    init(id: UUID, payloadData: Data, payloadVersion: Int = 1, isActive: Bool = true) {
        self.id = id
        self.payloadData = payloadData
        self.payloadVersion = payloadVersion
        self.isActive = isActive
    }
}

@Model
final class PlanChangeEntity {
    var id: UUID
    var payloadData: Data
    var payloadVersion: Int
    var timestamp: Date

    init(id: UUID, payloadData: Data, payloadVersion: Int = 1, timestamp: Date = Date()) {
        self.id = id
        self.payloadData = payloadData
        self.payloadVersion = payloadVersion
        self.timestamp = timestamp
    }
}

@Model
final class ActiveSessionSnapshotEntity {
    var id: UUID
    var payloadData: Data
    var payloadVersion: Int
    var updatedAt: Date

    init(id: UUID = UUID(), payloadData: Data, payloadVersion: Int = 1, updatedAt: Date = Date()) {
        self.id = id
        self.payloadData = payloadData
        self.payloadVersion = payloadVersion
        self.updatedAt = updatedAt
    }
}

@Model
final class PendingHealthOpEntity {
    var id: UUID
    var payloadData: Data
    var payloadVersion: Int
    var createdAt: Date

    init(id: UUID, payloadData: Data, payloadVersion: Int = 1, createdAt: Date = Date()) {
        self.id = id
        self.payloadData = payloadData
        self.payloadVersion = payloadVersion
        self.createdAt = createdAt
    }
}

enum VersionedPayload {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}
