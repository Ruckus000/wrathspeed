import Foundation

public enum WorkoutResultRecordOutcome: Equatable, Sendable {
    case insert
    case update
}

public struct WorkoutResultRecordPlan: Equatable, Sendable {
    public let outcome: WorkoutResultRecordOutcome
    public let existingIndex: Int?
    public let mergedResult: WorkoutResult

    public var shouldRunCompletionSideEffects: Bool {
        outcome == .insert
    }

    public init(outcome: WorkoutResultRecordOutcome, existingIndex: Int?, mergedResult: WorkoutResult) {
        self.outcome = outcome
        self.existingIndex = existingIndex
        self.mergedResult = mergedResult
    }
}

public enum WorkoutResultMerge {
    public static func identityKey(for result: WorkoutResult) -> String {
        if let uuid = resolvedHealthKitUUID(for: result) {
            return "hk:\(uuid.uuidString)"
        }
        return "local:\(result.workoutID.uuidString):\(result.startedAt.timeIntervalSince1970)"
    }

    public static func resolvedHealthKitUUID(for result: WorkoutResult) -> UUID? {
        result.healthKitUUID ?? result.healthSync.healthKitUUID
    }

    public static func matches(_ lhs: WorkoutResult, _ rhs: WorkoutResult) -> Bool {
        if let left = resolvedHealthKitUUID(for: lhs), let right = resolvedHealthKitUUID(for: rhs) {
            return left == right
        }
        return lhs.workoutID == rhs.workoutID && lhs.startedAt == rhs.startedAt
    }

    public static func findIndex(of result: WorkoutResult, in results: [WorkoutResult]) -> Int? {
        results.firstIndex { matches($0, result) }
    }

    public static func canonical(of seed: WorkoutResult, in results: [WorkoutResult]) -> WorkoutResult {
        guard let index = findIndex(of: seed, in: results) else { return seed }
        return results[index]
    }

    /// History-only row identity; persistence/merge still uses `identityKey`.
    public static func historyRowIdentity(for result: WorkoutResult, in results: [WorkoutResult]) -> String {
        let hasLocalConflict = results.contains { other in
            other.workoutID == result.workoutID
                && other.startedAt == result.startedAt
                && !matches(other, result)
        }
        if hasLocalConflict, let uuid = resolvedHealthKitUUID(for: result) {
            return "hk:\(uuid.uuidString)"
        }
        return "local:\(result.workoutID.uuidString):\(result.startedAt.timeIntervalSince1970)"
    }

    public static func planRecord(existing: [WorkoutResult], incoming: WorkoutResult) -> WorkoutResultRecordPlan {
        var normalized = incoming
        if normalized.healthSync.state == .notRequired, normalized.healthKitUUID != nil {
            normalized.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: normalized.healthKitUUID)
        }

        if let index = findIndex(of: normalized, in: existing) {
            let merged = merge(existing: existing[index], incoming: normalized)
            return WorkoutResultRecordPlan(outcome: .update, existingIndex: index, mergedResult: merged)
        }
        return WorkoutResultRecordPlan(outcome: .insert, existingIndex: nil, mergedResult: normalized)
    }

    public static func ingest(_ incoming: WorkoutResult, into results: inout [WorkoutResult]) {
        let plan = planRecord(existing: results, incoming: incoming)
        if let index = plan.existingIndex {
            results[index] = plan.mergedResult
        } else {
            results.append(plan.mergedResult)
        }
    }

    public static func canonicalize(
        results: [WorkoutResult],
        plan: TrainingPlan?
    ) -> (results: [WorkoutResult], plan: TrainingPlan?) {
        var canonical: [WorkoutResult] = []
        for result in results {
            ingest(result, into: &canonical)
        }

        guard var plan else {
            return (canonical, nil)
        }

        for index in plan.workouts.indices {
            guard let embedded = plan.workouts[index].result else { continue }
            ingest(embedded, into: &canonical)
            if let matchIndex = findIndex(of: embedded, in: canonical) {
                plan.workouts[index].result = canonical[matchIndex]
            }
        }

        return (canonical, plan)
    }

    public static func merge(existing: WorkoutResult, incoming: WorkoutResult) -> WorkoutResult {
        var merged = existing
        merged.healthSync = mergedHealthSync(existing: existing.healthSync, incoming: incoming.healthSync)
        merged.healthKitUUID = resolvedHealthKitUUID(for: existing) ?? resolvedHealthKitUUID(for: incoming)

        if let route = incoming.route, !route.isEmpty {
            merged.route = route
        }
        if let splits = incoming.splits, !splits.isEmpty {
            merged.splits = splits
        }

        if incoming.duration > 0 { merged.duration = incoming.duration }
        if incoming.distanceMeters > 0 { merged.distanceMeters = incoming.distanceMeters }
        merged.averagePaceSecPerKm = incoming.averagePaceSecPerKm ?? merged.averagePaceSecPerKm
        merged.heartRateAverage = incoming.heartRateAverage ?? merged.heartRateAverage
        merged.energyKilocalories = incoming.energyKilocalories ?? merged.energyKilocalories
        merged.cadenceAverage = incoming.cadenceAverage ?? merged.cadenceAverage
        merged.isUnavailableInHealth = incoming.isUnavailableInHealth ? incoming.isUnavailableInHealth : merged.isUnavailableInHealth

        if incoming.matchInfo.state == .matched || existing.matchInfo.state != .matched {
            merged.matchInfo = incoming.matchInfo
        }

        merged.workoutID = existing.workoutID
        merged.startedAt = existing.startedAt
        merged.source = existing.source

        if merged.healthSync.state == .notRequired, merged.healthKitUUID != nil {
            merged.healthSync = HealthSyncMetadata(state: .synced, healthKitUUID: merged.healthKitUUID)
        }

        return merged
    }

    private static func mergedHealthSync(existing: HealthSyncMetadata, incoming: HealthSyncMetadata) -> HealthSyncMetadata {
        let resolvedState = resolveHealthSyncState(existing: existing.state, incoming: incoming.state)
        var merged = HealthSyncMetadata(
            state: resolvedState,
            failureMessage: incoming.failureMessage ?? existing.failureMessage,
            lastAttemptAt: incoming.lastAttemptAt ?? existing.lastAttemptAt,
            healthKitUUID: existing.healthKitUUID ?? incoming.healthKitUUID
        )
        if resolvedState == .synced {
            merged.failureMessage = nil
        }
        return merged
    }

    private static func resolveHealthSyncState(existing: HealthSyncState, incoming: HealthSyncState) -> HealthSyncState {
        if existing == .synced { return .synced }
        if incoming == .synced { return .synced }
        if existing == .pending && incoming == .failed { return .failed }
        if existing == .failed { return .failed }
        if existing == .pending || incoming == .pending { return .pending }
        return incoming
    }
}

public extension ActiveSessionState {
    var isRecoverableUnfinishedSession: Bool {
        switch self {
        case .preparing, .countdown, .recording, .paused, .finishing: true
        case .saved, .healthSyncPending, .failed: false
        }
    }
}

public extension ActiveSessionSnapshot {
    func estimatedStartedAt() -> Date {
        startedAt ?? updatedAt.addingTimeInterval(-elapsedSeconds)
    }

    func matchesResult(_ result: WorkoutResult) -> Bool {
        guard workoutID == result.workoutID else { return false }
        return result.startedAt == estimatedStartedAt()
    }

    /// Whether a terminal `.saved` snapshot may clear a stored startup recovery snapshot.
    func matchesStartupTerminalClear(from terminal: ActiveSessionSnapshot) -> Bool {
        guard terminal.state == .saved else { return false }
        guard workoutID == terminal.workoutID, source == terminal.source else { return false }
        guard state == .preparing || state == .countdown else { return false }
        switch (startupAttemptMs, terminal.startupAttemptMs) {
        case let (stored?, terminal?):
            return stored == terminal
        case (nil, nil):
            return true
        default:
            return false
        }
    }
}

public extension StrengthSessionResult {
    static func identityKey(_ result: StrengthSessionResult) -> String {
        "id:\(result.id.uuidString)"
    }

    static func matches(_ lhs: StrengthSessionResult, _ rhs: StrengthSessionResult) -> Bool {
        if lhs.id == rhs.id { return true }
        return lhs.sessionID == rhs.sessionID && lhs.startedAt == rhs.startedAt
    }
}

public extension MobilitySessionResult {
    static func identityKey(_ result: MobilitySessionResult) -> String {
        "id:\(result.id.uuidString)"
    }

    static func matches(_ lhs: MobilitySessionResult, _ rhs: MobilitySessionResult) -> Bool {
        if lhs.id == rhs.id { return true }
        return lhs.sessionID == rhs.sessionID && lhs.startedAt == rhs.startedAt
    }
}
