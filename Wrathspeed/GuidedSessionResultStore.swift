import Foundation
import SwiftData
import WrathspeedCore

enum GuidedSessionResultStore {
    static func loadStrengthResults(from context: ModelContext) throws -> [StrengthSessionResult] {
        let entities = try context.fetch(FetchDescriptor<StrengthSessionResultEntity>())
        return try entities
            .map { try VersionedPayload.decode(StrengthSessionResult.self, from: $0.payloadData) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    static func loadMobilityResults(from context: ModelContext) throws -> [MobilitySessionResult] {
        let entities = try context.fetch(FetchDescriptor<MobilitySessionResultEntity>())
        return try entities
            .map { try VersionedPayload.decode(MobilitySessionResult.self, from: $0.payloadData) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    static func upsertStrengthResult(_ result: StrengthSessionResult, to context: ModelContext) throws {
        let payload = try VersionedPayload.encode(result)
        let existing = try context.fetch(FetchDescriptor<StrengthSessionResultEntity>())
        if let entity = existing.first(where: { $0.id == result.id }) {
            entity.payloadData = payload
            entity.sessionID = result.sessionID
        } else if let entity = existing.first(where: {
            guard let stored = try? VersionedPayload.decode(StrengthSessionResult.self, from: $0.payloadData) else {
                return false
            }
            return StrengthSessionResult.matches(stored, result)
        }) {
            entity.id = result.id
            entity.sessionID = result.sessionID
            entity.payloadData = payload
        } else {
            context.insert(StrengthSessionResultEntity(id: result.id, sessionID: result.sessionID, payloadData: payload))
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func upsertMobilityResult(_ result: MobilitySessionResult, to context: ModelContext) throws {
        let payload = try VersionedPayload.encode(result)
        let existing = try context.fetch(FetchDescriptor<MobilitySessionResultEntity>())
        if let entity = existing.first(where: { $0.id == result.id }) {
            entity.payloadData = payload
            entity.sessionID = result.sessionID
        } else if let entity = existing.first(where: {
            guard let stored = try? VersionedPayload.decode(MobilitySessionResult.self, from: $0.payloadData) else {
                return false
            }
            return MobilitySessionResult.matches(stored, result)
        }) {
            entity.id = result.id
            entity.sessionID = result.sessionID
            entity.payloadData = payload
        } else {
            context.insert(MobilitySessionResultEntity(id: result.id, sessionID: result.sessionID, payloadData: payload))
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
