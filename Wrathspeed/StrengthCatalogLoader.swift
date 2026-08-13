import Foundation
import WrathspeedCore

enum StrengthCatalogLoader {
    static func load(bundle: Bundle = .main) throws -> StrengthCatalog {
        guard let url = bundle.url(forResource: "strength_catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(StrengthCatalog.self, from: Data(contentsOf: url))
    }
}
