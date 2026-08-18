import Foundation

public struct HealthImportResult: Equatable, Sendable {
    public var workouts: [ImportedHealthWorkout]
    public var newAnchor: Data?
    public var deletedHealthKitUUIDs: Set<UUID>

    public init(
        workouts: [ImportedHealthWorkout],
        newAnchor: Data? = nil,
        deletedHealthKitUUIDs: Set<UUID> = []
    ) {
        self.workouts = workouts
        self.newAnchor = newAnchor
        self.deletedHealthKitUUIDs = deletedHealthKitUUIDs
    }
}

public protocol HealthImporting: Sendable {
    var authorizationDenied: Bool { get }
    func requestAuthorization() async throws
    func importWorkouts(anchor: Data?, since: Date) async throws -> HealthImportResult
}

public enum HealthImportPresentationState: Equatable, Sendable {
    case idle
    case importing
    case succeeded
    case failed(HealthImportRecoverableFailure)
}

public struct HealthImportRecoverableFailure: Equatable, Sendable {
    public var message: String
    public var isAuthorizationDenied: Bool

    public var canRetry: Bool { !isAuthorizationDenied }
    public var canOpenSettings: Bool { isAuthorizationDenied }

    public init(message: String, isAuthorizationDenied: Bool) {
        self.message = message
        self.isAuthorizationDenied = isAuthorizationDenied
    }
}

public struct HealthImportStatusSnapshot: Equatable, Sendable {
    public var presentation: HealthImportPresentationState
    public var lastSuccessfulImportAt: Date?

    public init(
        presentation: HealthImportPresentationState = .idle,
        lastSuccessfulImportAt: Date? = nil
    ) {
        self.presentation = presentation
        self.lastSuccessfulImportAt = lastSuccessfulImportAt
    }
}

public enum HealthImportStatusDeriver {
    public static func derive(
        isImporting: Bool,
        authorizationDenied: Bool,
        lastSuccessfulImportAt: Date?,
        errorMessage: String?
    ) -> HealthImportStatusSnapshot {
        if isImporting {
            return HealthImportStatusSnapshot(
                presentation: .importing,
                lastSuccessfulImportAt: lastSuccessfulImportAt
            )
        }
        if authorizationDenied {
            return HealthImportStatusSnapshot(
                presentation: .failed(
                    HealthImportRecoverableFailure(
                        message: "Apple Health access is required to import workouts.",
                        isAuthorizationDenied: true
                    )
                ),
                lastSuccessfulImportAt: lastSuccessfulImportAt
            )
        }
        if let errorMessage {
            return HealthImportStatusSnapshot(
                presentation: .failed(
                    HealthImportRecoverableFailure(
                        message: errorMessage,
                        isAuthorizationDenied: false
                    )
                ),
                lastSuccessfulImportAt: lastSuccessfulImportAt
            )
        }
        if lastSuccessfulImportAt != nil {
            return HealthImportStatusSnapshot(
                presentation: .succeeded,
                lastSuccessfulImportAt: lastSuccessfulImportAt
            )
        }
        return HealthImportStatusSnapshot(
            presentation: .idle,
            lastSuccessfulImportAt: lastSuccessfulImportAt
        )
    }
}

public final class MockHealthImportService: HealthImporting, @unchecked Sendable {
    public var authorizationDenied = false
    public var workouts: [ImportedHealthWorkout] = []
    public var deletedHealthKitUUIDs: Set<UUID> = []
    public var anchor: Data?
    public private(set) var importCallCount = 0

    public init() {}

    public func requestAuthorization() async throws {}

    public func importWorkouts(anchor: Data?, since: Date) async throws -> HealthImportResult {
        importCallCount += 1
        let filtered = workouts.filter { $0.startedAt >= since }
        let newAnchor = Data("anchor-\(importCallCount)".utf8)
        self.anchor = newAnchor
        return HealthImportResult(
            workouts: filtered,
            newAnchor: newAnchor,
            deletedHealthKitUUIDs: deletedHealthKitUUIDs
        )
    }
}
