import Foundation
import WrathspeedCore

struct DiagnosticsExport: Codable {
    var appVersion: String
    var schemaVersion: Int
    var hasOnboarded: Bool
    var resultCount: Int
    var scheduledWorkoutCount: Int
    var healthImportDenied: Bool
    var pendingHealthOps: Int
    var recentErrors: [String]
}

enum DiagnosticsExporter {
    @MainActor
    static func make(from store: AppStore, schemaVersion: Int = PersistenceSchema.currentVersion, recentErrors: [String] = []) -> DiagnosticsExport {
        DiagnosticsExport(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            schemaVersion: schemaVersion,
            hasOnboarded: store.hasOnboarded,
            resultCount: store.results.count,
            scheduledWorkoutCount: store.plan?.workouts.count ?? 0,
            healthImportDenied: store.healthImportDenied,
            pendingHealthOps: 0,
            recentErrors: recentErrors
        )
    }

    @MainActor
    static func exportJSON(from store: AppStore) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(make(from: store))
    }
}
