import Foundation
import SwiftData
import WrathspeedCore

enum PlanChangeStore {
    static func append(_ change: PlanChange, to context: ModelContext) throws {
        let payload = try VersionedPayload.encode(change)
        context.insert(PlanChangeEntity(id: change.id, payloadData: payload, timestamp: change.timestamp))
        try context.save()
    }

    static func latest(in context: ModelContext) throws -> PlanChange? {
        let entities = try context.fetch(FetchDescriptor<PlanChangeEntity>())
        guard let latest = entities.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
        return try VersionedPayload.decode(PlanChange.self, from: latest.payloadData)
    }

    static func removeLatest(in context: ModelContext) throws {
        let entities = try context.fetch(FetchDescriptor<PlanChangeEntity>())
        guard let latest = entities.max(by: { $0.timestamp < $1.timestamp }) else { return }
        context.delete(latest)
        try context.save()
    }
}

enum ActiveSessionStore {
    static func save(_ snapshot: ActiveSessionSnapshot, to context: ModelContext) throws {
        let payload = try VersionedPayload.encode(snapshot)
        let existing = try context.fetch(FetchDescriptor<ActiveSessionSnapshotEntity>())
        for entity in existing { context.delete(entity) }
        context.insert(ActiveSessionSnapshotEntity(payloadData: payload))
        try context.save()
    }

    static func load(from context: ModelContext) throws -> ActiveSessionSnapshot? {
        guard let entity = try context.fetch(FetchDescriptor<ActiveSessionSnapshotEntity>()).first else { return nil }
        return try VersionedPayload.decode(ActiveSessionSnapshot.self, from: entity.payloadData)
    }

    static func clear(from context: ModelContext) throws {
        for entity in try context.fetch(FetchDescriptor<ActiveSessionSnapshotEntity>()) {
            context.delete(entity)
        }
        try context.save()
    }
}
