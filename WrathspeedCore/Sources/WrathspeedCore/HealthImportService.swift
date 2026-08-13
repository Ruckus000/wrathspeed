import Foundation

public struct HealthImportResult: Equatable, Sendable {
    public var workouts: [ImportedHealthWorkout]
    public var newAnchor: Data?

    public init(workouts: [ImportedHealthWorkout], newAnchor: Data? = nil) {
        self.workouts = workouts
        self.newAnchor = newAnchor
    }
}

public protocol HealthImporting: Sendable {
    var authorizationDenied: Bool { get }
    func requestAuthorization() async throws
    func importWorkouts(anchor: Data?, since: Date) async throws -> HealthImportResult
}

public final class MockHealthImportService: HealthImporting, @unchecked Sendable {
    public var authorizationDenied = false
    public var workouts: [ImportedHealthWorkout] = []
    public var anchor: Data?
    public private(set) var importCallCount = 0

    public init() {}

    public func requestAuthorization() async throws {}

    public func importWorkouts(anchor: Data?, since: Date) async throws -> HealthImportResult {
        importCallCount += 1
        let filtered = workouts.filter { $0.startedAt >= since }
        let newAnchor = Data("anchor-\(importCallCount)".utf8)
        self.anchor = newAnchor
        return HealthImportResult(workouts: filtered, newAnchor: newAnchor)
    }
}
