import Foundation
import WrathspeedCore

struct MobilityCatalog: Codable, Equatable {
    var version: Int
    var routines: [MobilityRoutineTemplate]
}

struct MobilityRoutineTemplate: Codable, Equatable, Identifiable {
    var id: String
    var category: MobilityCategory
    var title: String
    var durationMinutes: Int
    var movements: [MobilityMovement]
}

enum MobilityCatalogLoader {
    static func load() throws -> MobilityCatalog {
        let url = Bundle.main.url(forResource: "mobility_catalog", withExtension: "json")
            ?? Bundle.main.bundleURL.appending(path: "mobility_catalog.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MobilityCatalog.self, from: data)
    }
}
