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
    var pendingVDOT: Double?
    var pendingVDOTReason: String?
    var results: [WorkoutResult]
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

    static func load(from context: ModelContext) -> PersistedState {
        decoder.dateDecodingStrategy = .iso8601
        let descriptor = FetchDescriptor<SnapshotEntity>()
        let snapshot = try? context.fetch(descriptor).first
        if let data = snapshot?.json, let state = try? decoder.decode(PersistedState.self, from: data) {
            return state
        }
        return PersistedState(
            hasOnboarded: false,
            profile: nil,
            plan: nil,
            n100: nil,
            strengthPrefs: StrengthPreferences(),
            strengthSessions: [],
            cuesEnabled: true,
            freezeMileage: false,
            pendingVDOT: nil,
            pendingVDOTReason: nil,
            results: []
        )
    }

    static func save(_ state: PersistedState, to context: ModelContext) {
        let data = (try? encoder.encode(state)) ?? Data()
        let descriptor = FetchDescriptor<SnapshotEntity>()
        if let existing = try? context.fetch(descriptor).first {
            existing.json = data
            existing.updatedAt = Date()
        } else {
            context.insert(SnapshotEntity(json: data))
        }
        try? context.save()
    }
}
