import Foundation
import SwiftData

enum HealthImportAnchorStore {
    static func load(from context: ModelContext) throws -> Data? {
        let settings = try context.fetch(FetchDescriptor<AppSettingsEntity>())
        return settings.first?.healthImportAnchorData
    }

    static func save(_ anchor: Data, to context: ModelContext) throws {
        guard let entity = try context.fetch(FetchDescriptor<AppSettingsEntity>()).first else { return }
        entity.healthImportAnchorData = anchor
        entity.updatedAt = Date()
        try context.save()
    }
}
