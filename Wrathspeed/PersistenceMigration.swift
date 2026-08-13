import Foundation
import SwiftData
import WrathspeedCore

enum PersistenceMigrationError: LocalizedError {
    case verificationFailed(String)
    case encodingFailed
    case partialWrite

    var errorDescription: String? {
        switch self {
        case .verificationFailed(let detail): "Migration verification failed: \(detail)"
        case .encodingFailed: "Could not encode persisted data during migration."
        case .partialWrite: "Migration did not complete; legacy data remains available."
        }
    }
}

enum PersistenceMigration {
    static func hasMigrated(in context: ModelContext) throws -> Bool {
        let descriptor = FetchDescriptor<MigrationMarkerEntity>()
        return try !context.fetch(descriptor).isEmpty
    }

    static func migrateIfNeeded(from context: ModelContext) throws {
        guard try !hasMigrated(in: context) else { return }
        let legacy = try Persistence.loadLegacySnapshot(from: context)
        try migrate(legacy, into: context)
    }

    static func migrate(_ legacy: PersistedState, into context: ModelContext) throws {
        let settingsID = UUID()
        let profileData = try legacy.profile.map { try VersionedPayload.encode($0) }
        let strengthPrefsData = try VersionedPayload.encode(legacy.strengthPrefs)
        let liveMetricsData = try VersionedPayload.encode(legacy.liveMetrics)

        let settings = AppSettingsEntity(
            id: settingsID,
            hasOnboarded: legacy.hasOnboarded,
            profileData: profileData,
            strengthPrefsData: strengthPrefsData,
            cuesEnabled: legacy.cuesEnabled,
            freezeMileage: legacy.freezeMileage,
            freezeMileageBaselineMeters: legacy.freezeMileageBaselineMeters,
            pendingVDOT: legacy.pendingVDOT,
            pendingVDOTReason: legacy.pendingVDOTReason,
            liveMetricsData: liveMetricsData,
            dataDensityRaw: legacy.dataDensity.rawValue,
            cueStyleRaw: legacy.cueStyle.rawValue,
            mobilityPrefsData: try VersionedPayload.encode(legacy.mobilityPrefs)
        )
        context.insert(settings)

        var planWorkoutCount = 0
        if let plan = legacy.plan {
            let goalData = try VersionedPayload.encode(plan.goal)
            let planProfileData = try VersionedPayload.encode(plan.profile)
            let planEntity = TrainingPlanEntity(
                id: plan.id,
                lifecycleStateRaw: PlanLifecycleState.active.rawValue,
                goalData: goalData,
                profileData: planProfileData,
                generatedAt: plan.generatedAt,
                isActive: true
            )
            context.insert(planEntity)

            for workout in plan.workouts {
                let payload = try VersionedPayload.encode(workout)
                context.insert(ScheduledWorkoutEntity(id: workout.id, planID: plan.id, payloadData: payload))
                planWorkoutCount += 1
            }
        }

        if let n100 = legacy.n100 {
            let adjustment = PlanAdjustment(payload: n100)
            let payload = try VersionedPayload.encode(adjustment)
            context.insert(PlanAdjustmentEntity(id: adjustment.id, payloadData: payload, isActive: true))
        }

        var resultEntities: [WorkoutResultEntity] = []
        var seenResultKeys = Set<String>()

        func insertResult(_ result: WorkoutResult, scheduledWorkoutID: UUID?) throws {
            let key = resultKey(result)
            guard !seenResultKeys.contains(key) else { return }
            seenResultKeys.insert(key)
            let payload = try VersionedPayload.encode(result)
            let entity = WorkoutResultEntity(
                id: result.workoutID,
                scheduledWorkoutID: scheduledWorkoutID,
                payloadData: payload,
                healthKitUUID: result.healthKitUUID
            )
            context.insert(entity)
            resultEntities.append(entity)
        }

        for result in legacy.results {
            let scheduledID = legacy.plan?.workouts.first(where: {
                $0.id == result.workoutID || $0.blueprint.id == result.workoutID
            })?.id
            try insertResult(result, scheduledWorkoutID: scheduledID)
        }

        if let plan = legacy.plan {
            for workout in plan.workouts {
                if let result = workout.result {
                    try insertResult(result, scheduledWorkoutID: workout.id)
                }
            }
        }

        for session in legacy.strengthSessions {
            let payload = try VersionedPayload.encode(session)
            context.insert(StrengthSessionEntity(id: session.id, payloadData: payload))
        }

        try verifyMigration(
            legacy: legacy,
            planWorkoutCount: planWorkoutCount,
            resultCount: resultEntities.count,
            strengthCount: legacy.strengthSessions.count,
            hasAdjustment: legacy.n100 != nil
        )

        try context.save()

        let marker = MigrationMarkerEntity(schemaVersion: PersistenceSchema.currentVersion)
        context.insert(marker)
        try context.save()
    }

    static func resultKey(_ result: WorkoutResult) -> String {
        if let uuid = result.healthKitUUID {
            return "hk:\(uuid.uuidString)"
        }
        return "local:\(result.workoutID.uuidString):\(result.startedAt.timeIntervalSince1970)"
    }

    private static func verifyMigration(
        legacy: PersistedState,
        planWorkoutCount: Int,
        resultCount: Int,
        strengthCount: Int,
        hasAdjustment: Bool
    ) throws {
        if let plan = legacy.plan {
            guard plan.workouts.count == planWorkoutCount else {
                throw PersistenceMigrationError.verificationFailed("workout count mismatch")
            }
            for workout in plan.workouts where workout.status == .completed {
                guard workout.result != nil || legacy.results.contains(where: {
                    $0.workoutID == workout.id || $0.workoutID == workout.blueprint.id
                }) else {
                    throw PersistenceMigrationError.verificationFailed("missing completed result for \(workout.id)")
                }
            }
        } else if planWorkoutCount > 0 {
            throw PersistenceMigrationError.verificationFailed("unexpected workouts without plan")
        }

        var expectedResultKeys = Set(legacy.results.map { PersistenceMigration.resultKey($0) })
        if let plan = legacy.plan {
            for workout in plan.workouts {
                if let result = workout.result {
                    expectedResultKeys.insert(PersistenceMigration.resultKey(result))
                }
            }
        }
        guard expectedResultKeys.count == resultCount else {
            throw PersistenceMigrationError.verificationFailed("result count mismatch expected \(expectedResultKeys.count) got \(resultCount)")
        }

        guard legacy.strengthSessions.count == strengthCount else {
            throw PersistenceMigrationError.verificationFailed("strength session count mismatch")
        }

        if legacy.n100 != nil && !hasAdjustment {
            throw PersistenceMigrationError.verificationFailed("missing plan adjustment")
        }

        if legacy.hasOnboarded && legacy.profile == nil {
            throw PersistenceMigrationError.verificationFailed("onboarded without profile")
        }
    }
}

enum VersionedPersistence {
    static func load(from context: ModelContext) throws -> PersistedState {
        let settings = try context.fetch(FetchDescriptor<AppSettingsEntity>()).first
        guard let settings else {
            return .initial
        }

        let profile = try settings.profileData.map { try VersionedPayload.decode(RunnerProfile.self, from: $0) }
        let strengthPrefs = try VersionedPayload.decode(StrengthPreferences.self, from: settings.strengthPrefsData)
        let liveMetrics = try VersionedPayload.decode(Set<LiveMetric>.self, from: settings.liveMetricsData)
        let dataDensity = DataDensity(rawValue: settings.dataDensityRaw) ?? .detailed
        let cueStyle = CueStyle(rawValue: settings.cueStyleRaw) ?? .standard
        let mobilityPrefs = try settings.mobilityPrefsData.map { try VersionedPayload.decode(MobilityPreferences.self, from: $0) } ?? MobilityPreferences()

        let planEntity = try context.fetch(FetchDescriptor<TrainingPlanEntity>()).first(where: \.isActive)
        var plan: TrainingPlan?
        if let planEntity {
            let goal = try VersionedPayload.decode(TrainingGoal.self, from: planEntity.goalData)
            let planProfile = try VersionedPayload.decode(RunnerProfile.self, from: planEntity.profileData)
            let workoutEntities = try context.fetch(FetchDescriptor<ScheduledWorkoutEntity>())
                .filter { $0.planID == planEntity.id }
            let workouts = try workoutEntities.map { try VersionedPayload.decode(ScheduledWorkout.self, from: $0.payloadData) }
            plan = TrainingPlan(
                id: planEntity.id,
                goal: goal,
                profile: planProfile,
                workouts: workouts.sorted { $0.date < $1.date },
                generatedAt: planEntity.generatedAt
            )
        }

        let adjustmentEntity = try context.fetch(FetchDescriptor<PlanAdjustmentEntity>()).first(where: \.isActive)
        let n100: N100Adjustment?
        if let adjustmentEntity {
            let adjustment = try VersionedPayload.decode(PlanAdjustment.self, from: adjustmentEntity.payloadData)
            n100 = adjustment.payload
        } else {
            n100 = nil
        }

        let resultEntities = try context.fetch(FetchDescriptor<WorkoutResultEntity>())
        let results = try resultEntities
            .map { try VersionedPayload.decode(WorkoutResult.self, from: $0.payloadData) }
            .sorted { $0.startedAt > $1.startedAt }

        let strengthEntities = try context.fetch(FetchDescriptor<StrengthSessionEntity>())
        let strengthSessions = try strengthEntities.map { try VersionedPayload.decode(StrengthSession.self, from: $0.payloadData) }
            .sorted { $0.date < $1.date }

        return PersistedState(
            hasOnboarded: settings.hasOnboarded,
            profile: profile,
            plan: plan,
            n100: n100,
            strengthPrefs: strengthPrefs,
            strengthSessions: strengthSessions,
            cuesEnabled: settings.cuesEnabled,
            freezeMileage: settings.freezeMileage,
            freezeMileageBaselineMeters: settings.freezeMileageBaselineMeters,
            pendingVDOT: settings.pendingVDOT,
            pendingVDOTReason: settings.pendingVDOTReason,
            results: results,
            liveMetrics: liveMetrics,
            dataDensity: dataDensity,
            cueStyle: cueStyle,
            mobilityPrefs: mobilityPrefs
        )
    }

    static func save(_ state: PersistedState, to context: ModelContext) throws {
        let profileData = try state.profile.map { try VersionedPayload.encode($0) }
        let strengthPrefsData = try VersionedPayload.encode(state.strengthPrefs)
        let liveMetricsData = try VersionedPayload.encode(state.liveMetrics)
        let mobilityPrefsData = try VersionedPayload.encode(state.mobilityPrefs)

        let settingsDescriptor = FetchDescriptor<AppSettingsEntity>()
        let settings: AppSettingsEntity
        if let existing = try context.fetch(settingsDescriptor).first {
            settings = existing
        } else {
            settings = AppSettingsEntity(
                id: UUID(),
                hasOnboarded: state.hasOnboarded,
                profileData: profileData,
                strengthPrefsData: strengthPrefsData,
                cuesEnabled: state.cuesEnabled,
                freezeMileage: state.freezeMileage,
                freezeMileageBaselineMeters: state.freezeMileageBaselineMeters,
                pendingVDOT: state.pendingVDOT,
                pendingVDOTReason: state.pendingVDOTReason,
                liveMetricsData: liveMetricsData,
                dataDensityRaw: state.dataDensity.rawValue,
                cueStyleRaw: state.cueStyle.rawValue,
                mobilityPrefsData: mobilityPrefsData
            )
            context.insert(settings)
        }

        settings.hasOnboarded = state.hasOnboarded
        settings.profileData = profileData
        settings.strengthPrefsData = strengthPrefsData
        settings.cuesEnabled = state.cuesEnabled
        settings.freezeMileage = state.freezeMileage
        settings.freezeMileageBaselineMeters = state.freezeMileageBaselineMeters
        settings.pendingVDOT = state.pendingVDOT
        settings.pendingVDOTReason = state.pendingVDOTReason
        settings.liveMetricsData = liveMetricsData
        settings.dataDensityRaw = state.dataDensity.rawValue
        settings.cueStyleRaw = state.cueStyle.rawValue
        settings.mobilityPrefsData = mobilityPrefsData
        settings.updatedAt = Date()

        try syncPlan(state.plan, in: context)
        try syncAdjustment(state.n100, in: context)
        try syncResults(state, in: context)
        try syncStrengthSessions(state.strengthSessions, in: context)

        try context.save()
    }

    private static func syncPlan(_ plan: TrainingPlan?, in context: ModelContext) throws {
        let existingPlans = try context.fetch(FetchDescriptor<TrainingPlanEntity>())
        let existingWorkouts = try context.fetch(FetchDescriptor<ScheduledWorkoutEntity>())

        if let plan {
            let planEntity: TrainingPlanEntity
            if let existing = existingPlans.first(where: { $0.id == plan.id }) {
                planEntity = existing
            } else {
                for other in existingPlans where other.isActive {
                    other.isActive = false
                    other.lifecycleStateRaw = PlanLifecycleState.archived.rawValue
                }
                planEntity = TrainingPlanEntity(
                    id: plan.id,
                    lifecycleStateRaw: PlanLifecycleState.active.rawValue,
                    goalData: try VersionedPayload.encode(plan.goal),
                    profileData: try VersionedPayload.encode(plan.profile),
                    generatedAt: plan.generatedAt,
                    isActive: true
                )
                context.insert(planEntity)
            }
            planEntity.goalData = try VersionedPayload.encode(plan.goal)
            planEntity.profileData = try VersionedPayload.encode(plan.profile)
            planEntity.generatedAt = plan.generatedAt
            planEntity.isActive = true
            planEntity.lifecycleStateRaw = PlanLifecycleState.active.rawValue

            let currentIDs = Set(plan.workouts.map(\.id))
            for entity in existingWorkouts where entity.planID == plan.id && !currentIDs.contains(entity.id) {
                context.delete(entity)
            }
            for workout in plan.workouts {
                let payload = try VersionedPayload.encode(workout)
                if let entity = existingWorkouts.first(where: { $0.id == workout.id }) {
                    entity.payloadData = payload
                    entity.planID = plan.id
                } else {
                    context.insert(ScheduledWorkoutEntity(id: workout.id, planID: plan.id, payloadData: payload))
                }
            }
        } else {
            for entity in existingPlans where entity.isActive {
                entity.isActive = false
                entity.lifecycleStateRaw = PlanLifecycleState.archived.rawValue
            }
        }
    }

    private static func syncAdjustment(_ n100: N100Adjustment?, in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<PlanAdjustmentEntity>())
        if let n100 {
            let adjustment = PlanAdjustment(payload: n100)
            let payload = try VersionedPayload.encode(adjustment)
            if let entity = existing.first(where: \.isActive) {
                entity.payloadData = payload
                entity.isActive = true
            } else {
                for entity in existing { entity.isActive = false }
                context.insert(PlanAdjustmentEntity(id: adjustment.id, payloadData: payload, isActive: true))
            }
        } else {
            for entity in existing {
                entity.isActive = false
            }
        }
    }

    private static func syncResults(_ state: PersistedState, in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<WorkoutResultEntity>())
        let desired = mergedResults(from: state)
        let desiredIDs = Set(desired.map(\.workoutID))

        for entity in existing where !desiredIDs.contains(entity.id) {
            context.delete(entity)
        }

        for result in desired {
            let payload = try VersionedPayload.encode(result)
            let scheduledID = state.plan?.workouts.first(where: {
                $0.id == result.workoutID || $0.blueprint.id == result.workoutID
            })?.id
            if let entity = existing.first(where: { $0.id == result.workoutID }) {
                entity.payloadData = payload
                entity.scheduledWorkoutID = scheduledID
                entity.healthKitUUID = result.healthKitUUID
            } else {
                context.insert(WorkoutResultEntity(
                    id: result.workoutID,
                    scheduledWorkoutID: scheduledID,
                    payloadData: payload,
                    healthKitUUID: result.healthKitUUID
                ))
            }
        }
    }

    private static func syncStrengthSessions(_ sessions: [StrengthSession], in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<StrengthSessionEntity>())
        let desiredIDs = Set(sessions.map(\.id))
        for entity in existing where !desiredIDs.contains(entity.id) {
            context.delete(entity)
        }
        for session in sessions {
            let payload = try VersionedPayload.encode(session)
            if let entity = existing.first(where: { $0.id == session.id }) {
                entity.payloadData = payload
            } else {
                context.insert(StrengthSessionEntity(id: session.id, payloadData: payload))
            }
        }
    }

    private static func mergedResults(from state: PersistedState) -> [WorkoutResult] {
        var merged: [WorkoutResult] = []
        var keys = Set<String>()
        for result in state.results {
            let key = PersistenceMigration.resultKey(result)
            guard !keys.contains(key) else { continue }
            keys.insert(key)
            merged.append(result)
        }
        if let plan = state.plan {
            for workout in plan.workouts {
                if let result = workout.result {
                    let key = PersistenceMigration.resultKey(result)
                    guard !keys.contains(key) else { continue }
                    keys.insert(key)
                    merged.append(result)
                }
            }
        }
        return merged
    }
}
