import Foundation
import SwiftData
import WrathspeedCore

enum PlanChangeStore {
    struct Entry {
        let change: PlanChange
        let entity: PlanChangeEntity
    }

    static func stageAppend(_ change: PlanChange, to context: ModelContext) throws {
        let payload = try VersionedPayload.encode(change)
        context.insert(PlanChangeEntity(id: change.id, payloadData: payload, timestamp: change.timestamp))
    }

    static func latestEntry(in context: ModelContext) throws -> Entry? {
        let entities = try context.fetch(FetchDescriptor<PlanChangeEntity>())
        guard let latest = entities.max(by: compareEntities) else { return nil }
        let change = try VersionedPayload.decode(PlanChange.self, from: latest.payloadData)
        return Entry(change: change, entity: latest)
    }

    static func stageRemove(_ entity: PlanChangeEntity, in context: ModelContext) {
        context.delete(entity)
    }

    private static func compareEntities(_ lhs: PlanChangeEntity, _ rhs: PlanChangeEntity) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        return lhs.id.uuidString < rhs.id.uuidString
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
