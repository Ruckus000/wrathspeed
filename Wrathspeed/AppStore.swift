import Foundation
import Observation
import SwiftData
import UIKit
import WrathspeedCore

struct PreflightRequest: Identifiable, Equatable {
    var id: UUID { blueprint.id }
    let blueprint: WorkoutBlueprint
    let source: WorkoutSource
}

@MainActor
@Observable
final class AppStore {
    private static let initialState = PersistedState.initial

    /// Static content, parsed once at launch rather than per render. An unreadable catalog
    /// degrades to empty rather than failing launch, the same way missing media degrades
    /// to SF Symbols.
    let movementCatalog = (try? MovementCatalog.load()) ?? MovementCatalog(movements: [])

    /// Browsable strength content for the movement library. Goes through the injected
    /// loader so the library and the planner can never disagree about the catalog.
    @ObservationIgnored
    private(set) lazy var strengthCatalog: StrengthCatalog =
        (try? strengthCatalogLoader()) ?? StrengthCatalog(exercises: [])

    var hasOnboarded = initialState.hasOnboarded
    var profile = initialState.profile
    var plan = initialState.plan
    var n100 = initialState.n100
    var strengthPrefs = initialState.strengthPrefs
    var strengthSessions = initialState.strengthSessions
    var cuesEnabled = initialState.cuesEnabled
    var freezeMileage = initialState.freezeMileage
    var freezeMileageBaselineMeters = initialState.freezeMileageBaselineMeters
    var pendingSuggestion: VDOTSuggestion?
    var results = initialState.results
    var errorMessage: String?
    var liveMetrics = initialState.liveMetrics
    var dataDensity = initialState.dataDensity
    var cueStyle = initialState.cueStyle
    var mobilityPrefs = initialState.mobilityPrefs
    var onboardingDraft: OnboardingDraft?
    var showHealthPermissionPrimer = false
    var healthImportDenied = false
    var healthImportInProgress = false
    var healthImportLastSuccessAt: Date?
    var healthImportErrorMessage: String?
    var healthImportStatus: HealthImportStatusSnapshot {
        HealthImportStatusDeriver.derive(
            isImporting: healthImportInProgress,
            authorizationDenied: healthImportDenied,
            lastSuccessfulImportAt: healthImportLastSuccessAt,
            errorMessage: healthImportErrorMessage
        )
    }
    var lastUndoDescription: String?
    var toastMessage: String?
    var celebration: CelebrationPayload?
    var selectedTab: AppTab = .today
    var pendingRecoverySnapshot: ActiveSessionSnapshot?
    var pendingPreflight: PreflightRequest?
    var showWatchLaunchTimeout = false
    private(set) var guidedStrengthResults: [StrengthSessionResult] = []
    private(set) var guidedMobilityResults: [MobilitySessionResult] = []
    var strengthResults: [StrengthSessionResult] {
        GuidedSessionPolicy.completedStrength(guidedStrengthResults)
    }
    var mobilityResults: [MobilitySessionResult] {
        GuidedSessionPolicy.completedMobility(guidedMobilityResults)
    }
    var pendingWorkoutSource: WorkoutSource = .wrathspeedPhone
    var pendingTreadmillDistance: PendingTreadmillDistance?
#if DEBUG
    @ObservationIgnored
    private(set) var watchPublicationCountForTesting = 0
#endif

    var reminderNotice: String?
    var missedWorkSituation: MissedWorkSituation? {
        guard let plan else { return nil }
        return MissedWorkService.detect(plan: plan)
    }

    private let workoutCoordinator: WorkoutSessionCoordinator
    private let strengthCatalogLoader: () throws -> StrengthCatalog
    private var repository: AppStateRepository?
    private var modelContext: ModelContext?
    private var healthImporter: any HealthImporting = AppStore.defaultHealthImporter()

    /// Under test the live importer raises the system "Health Access" alert, which then
    /// blocks every subsequent interaction in that run.
    static func defaultHealthImporter() -> any HealthImporting {
        #if DEBUG
        if UITestingSupport.isUITesting { return UITestingHealthImportService() }
        #endif
        return LiveHealthImportService()
    }
    private var reminderScheduler: any WorkoutReminderScheduling = AppStore.defaultReminderScheduler()
    private var didAttach = false

    /// Under UI test the live scheduler would raise the system notification prompt, which
    /// blocks every subsequent tap in that run.
    static func defaultReminderScheduler() -> any WorkoutReminderScheduling {
        #if DEBUG
        if UITestingSupport.isUITesting { return UITestingWorkoutReminderScheduler() }
        #endif
        return LiveWorkoutReminderScheduler()
    }
    private var toastTask: Task<Void, Never>?

    var unit: DistanceUnit { profile?.unit ?? DistanceUnit.default() }

    init(
        strengthCatalogLoader: @escaping () throws -> StrengthCatalog = { try StrengthCatalogLoader.load() },
        reminderScheduler: any WorkoutReminderScheduling = AppStore.defaultReminderScheduler(),
        workoutCoordinator: WorkoutSessionCoordinator = WorkoutSessionCoordinator()
    ) {
        self.strengthCatalogLoader = strengthCatalogLoader
        self.reminderScheduler = reminderScheduler
        self.workoutCoordinator = workoutCoordinator
    }

    var zones: PaceZones? {
        guard let vdot = profile?.vdot else { return nil }
        return PaceCalculator.zones(vdot: vdot)
    }

    var session: WorkoutSessionController { workoutCoordinator.session }
    var isWatchAppAvailable: Bool { workoutCoordinator.isWatchAppAvailable }

    var todaysRuns: [ScheduledWorkout] {
        guard let plan = displayPlan else { return [] }
        return plan.workouts.filter {
            Calendar.current.isDateInToday($0.date) && ($0.status == .scheduled || $0.status == .convertedToEasy)
        }
    }

    var todaysCompletedRuns: [ScheduledWorkout] {
        guard let plan = displayPlan else { return [] }
        return plan.workouts.filter {
            Calendar.current.isDateInToday($0.date) && $0.status == .completed
        }
    }

    var todaysStrength: [StrengthSession] {
        strengthSessions.filter { Calendar.current.isDateInToday($0.date) }
    }

    var resumableStrengthSession: StrengthSession? {
        guard let inProgress = guidedStrengthResults.first(where: { $0.lifecycle == .inProgress }) else { return nil }
        return strengthSessions.first { $0.id == inProgress.sessionID }
    }

    var resumableMobilitySessions: [MobilitySession] {
        let routineIDs = Set(
            guidedMobilityResults
                .filter { $0.lifecycle == .inProgress }
                .map(\.routineID)
                .filter { !$0.isEmpty }
        )
        guard !routineIDs.isEmpty else { return [] }
        guard let sessions = try? MobilityCatalogLoader.allSessions() else { return [] }
        return sessions.filter { routineIDs.contains($0.routineID) }
    }

    func mobilitySessionsForToday() -> [MobilitySession] {
        (try? MobilityCatalogLoader.allSessions()) ?? []
    }

    func isMobilityRoutineResumable(_ session: MobilitySession) -> Bool {
        GuidedSessionPolicy.inProgressMobility(routineID: session.routineID, in: guidedMobilityResults) != nil
    }

    var upcomingRuns: [ScheduledWorkout] {
        guard let plan = displayPlan else { return [] }
        return plan.workouts
            .filter { ($0.status == .scheduled || $0.status == .convertedToEasy) && $0.date >= Calendar.current.startOfDay(for: Date()) }
            .sorted { $0.date < $1.date }
    }

    var streak: Int { streakCount() }

    /// True only inside the pause window itself, not the easier-return days that follow it.
    /// `transformDuring` skips every run in that window, which is what makes those days read
    /// as rest days in the first place.
    var isN100PauseActive: Bool {
        guard let n100, n100.mode == .pause else { return false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return today >= calendar.startOfDay(for: n100.start) && today < n100.windowEnd(calendar: calendar)
    }

    /// The next scheduled run, when today has none of its own and the plan's own rules allow
    /// moving it here. Nil rather than a disabled button: the alternative is offering an
    /// action whose only outcome is an error alert.
    ///
    /// Not offered during an N100 pause, where `upcomingRuns` returns the first run *after*
    /// the block -- pulling that into the window is what the user opted out of.
    var nextRunToPullForward: ScheduledWorkout? {
        guard todaysRuns.isEmpty, todaysCompletedRuns.isEmpty else { return nil }
        guard !isN100PauseActive else { return nil }
        guard let plan, let next = upcomingRuns.first else { return nil }
        let validation = PlanScheduleService.canMove(
            workout: next,
            to: Date(),
            plan: plan,
            profile: profile
        )
        return validation.allowed ? next : nil
    }

    /// Base plan stored in persistence; overlay applied at read time.
    var displayPlan: TrainingPlan? {
        guard let plan else { return nil }
        return PlanAdjustmentService.effectivePlan(plan, adjustment: n100)
    }

    func attach(context: ModelContext, resetStore: Bool = UITestingSupport.shouldResetStore, healthImporter: (any HealthImporting)? = nil) {
        repository = AppStateRepository(context: context)
        modelContext = context
        if let healthImporter { self.healthImporter = healthImporter }
        guard !didAttach else { return }
        didAttach = true
        if resetStore {
            do {
                try repository!.reset()
            } catch {
                errorMessage = "Couldn’t reset saved training data: \(error.localizedDescription)"
                return
            }
            applyPersistedState(.initial)
            finishAttach()
#if DEBUG
            // Ordering here is load-bearing. It runs after `reset()` and
            // `applyPersistedState(.initial)`, or the seeded plan is wiped along with the
            // store; after `finishAttach()`, because `confirmOnboarding` calls
            // `seedInProgressMobilityForUITestingIfNeeded`, which records a mobility result
            // and needs `loadGuidedSessionResults()` to have run first; and in the reset
            // branch only, so the other path's `importHealthWorkouts()` never fires in a
            // sequence the real onboarding flow does not produce.
            seedCompletedOnboardingForUITestingIfNeeded()
#endif
            return
        }
        let state: PersistedState
        do {
            state = try repository!.load()
            if let migrationError = repository?.migrationError {
                errorMessage = "Couldn’t upgrade saved data yet. Your existing plan is still available. \(migrationError)"
            }
        } catch {
            errorMessage = "Couldn’t load saved training data: \(error.localizedDescription)"
            return
        }
        applyPersistedState(state)
        finishAttach()
        if hasOnboarded {
            Task { await importHealthWorkouts() }
        }
    }

    func generateOnboardingDraft(from inputs: OnboardingInputs) throws -> OnboardingDraft {
        let catalog = try strengthCatalogLoader()
        let draft = try OnboardingDraftBuilder.build(inputs: inputs, catalog: catalog)
        onboardingDraft = draft
        return draft
    }

    func confirmOnboarding(draft: OnboardingDraft) {
        guard let repository else {
            errorMessage = "Couldn’t save your plan yet."
            return
        }
        profile = draft.plan.profile
        strengthPrefs = draft.inputs.makeStrengthPreferences()
        mobilityPrefs = draft.inputs.mobility
        plan = draft.plan
        strengthSessions = (try? strengthCatalogLoader()).flatMap { catalog in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let planEnd = draft.plan.workouts.map(\.date).max() ?? today
            let daysRemaining = max(0, calendar.dateComponents([.day], from: today, to: planEnd).day ?? 0)
            let weekCount = max(1, Int(ceil(Double(daysRemaining + 1) / 7.0)))
            return StrengthPlanner.schedule(
                preferences: strengthPrefs,
                startDate: today,
                weekCount: weekCount,
                calendar: calendar,
                catalog: catalog
            ).filter { $0.date <= planEnd }
        } ?? []
        onboardingDraft = nil
        do {
            hasOnboarded = true
            try repository.save(currentPersistedState())
            pushWatchWorkouts()
#if DEBUG
            if !UITestingSupport.shouldResetStore && !UITestingSupport.shouldSeedCompletedOnboarding {
                showHealthPermissionPrimer = true
            }
#else
            showHealthPermissionPrimer = true
#endif
            showToast("PLAN READY — \(draft.plan.goal.weekCount) WEEKS")
#if DEBUG
            seedInProgressMobilityForUITestingIfNeeded()
            seedTodayRunForUITestingIfNeeded()
            seedTodayStrengthForUITestingIfNeeded()
#endif
        } catch {
            hasOnboarded = false
            plan = nil
            profile = nil
            errorMessage = "Couldn’t save your plan: \(error.localizedDescription)"
        }
    }

    func completeOnboarding(goal: TrainingGoal, profile: RunnerProfile, strength: StrengthPreferences) {
        var calendar = Calendar.current
        calendar.timeZone = .current
        do {
            try PlanRequest(goal: goal, profile: profile, startDate: Date(), calendar: calendar).validate()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        self.profile = profile
        self.strengthPrefs = strength
        hasOnboarded = true
        regeneratePlan(goal: goal, profile: profile)
        let weeks = plan?.goal.weekCount ?? goal.weekCount
        showToast("PLAN READY — \(weeks) WEEKS")
    }

    func regeneratePlan(goal: TrainingGoal? = nil, profile: RunnerProfile? = nil) {
        guard let profile = profile ?? self.profile else { return }
        do {
            let generated = try buildRegeneratedSchedule(goal: goal, profile: profile)
            plan = generated.plan
            strengthSessions = generated.strengthSessions
            self.profile = profile
            persist()
            pushWatchWorkouts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func skip(_ workout: ScheduledWorkout, convertQuality: Bool = false) {
        guard workout.status == .scheduled || workout.status == .convertedToEasy else { return }
        let description = convertQuality ? "Converted to easy" : "Skipped session"
        let kind: PlanChangeKind = convertQuality ? .convert : .skip
        performPlanMutation(
            description: description,
            kind: kind,
            affected: [workout.id],
            successToast: convertQuality ? "CONVERTED TO EASY" : "SESSION SKIPPED",
            evaluateAdaptationAfter: true,
            mutate: {
                try updateWorkoutInPlan(workout.id) { AdaptationRules.applySkip($0, convertQualityToEasy: convertQuality) }
            }
        )
    }

    func move(
        _ workout: ScheduledWorkout,
        to date: Date,
        allowWarnings: Bool = false,
        scheduledTimeMinutes: Int? = nil,
        reminderEnabled: Bool = false
    ) {
        guard let plan else { return }
        let validation = PlanScheduleService.canMove(
            workout: workout,
            to: date,
            plan: plan,
            profile: profile
        )
        guard validation.allowed else {
            errorMessage = validation.reason
            return
        }
        if !allowWarnings, !validation.warnings.isEmpty {
            errorMessage = validation.warnings.joined(separator: " ")
            return
        }
        let targetDay = Calendar.current.startOfDay(for: date)
        performPlanMutation(
            description: "Moved workout",
            kind: .move,
            affected: [workout.id],
            successToast: "WORKOUT MOVED",
            mutate: {
                try updateWorkoutInPlan(workout.id) { current in
                    var copy = current
                    copy.blueprint.date = targetDay
                    copy.scheduledTimeMinutes = reminderEnabled ? scheduledTimeMinutes : nil
                    copy.reminderEnabled = reminderEnabled
                    return copy
                }
            }
        )
    }

    func undoLastPlanChange() {
        guard let context = modelContext,
              let entry = try? PlanChangeStore.latestEntry(in: context),
              let snapshotData = entry.change.previousSnapshot,
              let snapshot = try? JSONDecoder().decode(PlanUndoSnapshot.self, from: snapshotData)
        else { return }

        let previous = capturePlanMutationSnapshot()
        let workoutsBefore = plan?.workouts ?? []
        plan = snapshot.plan
        n100 = snapshot.n100
        do {
            PlanChangeStore.stageRemove(entry.entity, in: context)
            try persistThrowing()
        } catch {
            restorePlanMutationSnapshot(previous)
            errorMessage = "Couldn't undo the last change: \(error.localizedDescription)"
            return
        }

        pushWatchWorkouts()
        showToast("UNDONE")
        lastUndoDescription = nil
        reconcileReminders(before: workoutsBefore, after: plan?.workouts ?? [])
    }

    private func stagePlanChange(_ change: PlanChange) throws {
        guard let context = modelContext else { throw AppPersistenceError.storageUnavailable }
        try PlanChangeStore.stageAppend(change, to: context)
        lastUndoDescription = change.description
    }

    private func offerUndo() {
        if lastUndoDescription != nil {
            showToast("UPDATED · UNDO AVAILABLE IN PLAN")
        }
    }

    func applyNotFeeling100(_ adjustment: N100Adjustment) {
        guard NotFeeling100Rules.isValidDayCount(adjustment.dayCount),
              NotFeeling100Rules.isValidStart(start: adjustment.start, dayCount: adjustment.dayCount)
        else {
            errorMessage = "That adjustment period isn't valid."
            return
        }
        performPlanMutation(
            description: "Not feeling 100%",
            kind: .adjustment,
            affected: [],
            successToast: "PLAN ADJUSTED FOR \(adjustment.dayCount) DAYS · RETURN: \(adjustment.returnPace.title.uppercased())",
            mutate: {
                var stored = adjustment
                stored.createdAt = n100?.createdAt ?? Date()
                n100 = stored
            }
        )
    }

    @discardableResult
    func endNotFeeling100() -> Bool {
        guard n100 != nil else { return false }
        performPlanMutation(
            description: "Ended not feeling 100%",
            kind: .adjustment,
            affected: [],
            successToast: "ADJUSTMENT ENDED",
            mutate: { n100 = nil }
        )
        return errorMessage == nil
    }

    @discardableResult
    func discardNotFeeling100IfCreationDay() -> Bool {
        guard let adjustment = n100,
              NotFeeling100Rules.canDiscardOnCreationDay(adjustment: adjustment, createdOn: Date())
        else { return false }
        return endNotFeeling100()
    }

    func previewMissedWork(choice: MissedWorkChoice, situation: MissedWorkSituation) -> MissedWorkPreview? {
        guard let plan else { return nil }
        return MissedWorkService.preview(choice: choice, plan: plan, situation: situation)
    }

    func applyMissedWork(choice: MissedWorkChoice, situation: MissedWorkSituation, preview: MissedWorkPreview?) throws {
        guard let currentPlan = plan else { return }
        guard let preview,
              preview == MissedWorkService.preview(choice: choice, plan: currentPlan, situation: situation)
        else {
            throw MissedWorkApplyError.previewRequired
        }
        switch choice {
        case .skipMissed:
            performPlanMutation(
                description: "Skipped missed work",
                kind: .skip,
                affected: situation.missedWorkouts.map(\.id),
                successToast: "MISSED WORK SKIPPED",
                mutate: {
                    plan = MissedWorkService.applySkip(plan: currentPlan, situation: situation)
                }
            )
        case .moveEligible:
            performPlanMutation(
                description: "Moved missed work",
                kind: .move,
                affected: situation.missedWorkouts.map(\.id),
                successToast: "MISSED WORK MOVED",
                mutate: {
                    plan = MissedWorkService.applyMoveEligible(plan: currentPlan, situation: situation)
                }
            )
        case .extendPlan:
            guard let extendedGoal = MissedWorkService.extendedGoal(from: currentPlan.goal) else {
                throw MissedWorkExtendError.racePlan
            }
            performPlanMutation(
                description: "Extended plan",
                kind: .scheduleRegeneration,
                affected: situation.missedWorkouts.map(\.id),
                successToast: "PLAN EXTENDED",
                mutate: {
                    let generated = try buildRegeneratedSchedule(goal: extendedGoal, profile: profile)
                    let extensionStart = generated.plan.workouts.map(\.date).max() ?? Date()
                    plan = MissedWorkService.reassignedIntoExtensionWeek(
                        plan: generated.plan,
                        situation: situation,
                        extensionWeekStart: extensionStart
                    )
                    strengthSessions = generated.strengthSessions
                }
            )
        }
    }

    private enum MissedWorkExtendError: LocalizedError {
        case racePlan
        var errorDescription: String? { "Race plans can't be extended through missed-work choices." }
    }

    enum MissedWorkApplyError: LocalizedError {
        case previewRequired
        var errorDescription: String? { "Preview missed-work changes before applying." }
    }

    func acceptVDOTSuggestion() {
        guard var profile, let pendingSuggestion else { return }
        profile.vdot = pendingSuggestion.newVDOT
        self.profile = profile
        self.pendingSuggestion = nil
        regeneratePlan(profile: profile)
        showToast("VDOT UPDATED")
    }

    func declineVDOTSuggestion() {
        pendingSuggestion = nil
        persist()
    }

    func confirmTreadmillDistance(_ displayDistance: Double) {
        guard var pending = pendingTreadmillDistance else { return }
        let meters = Units.meters(fromDisplay: displayDistance, unit: unit)
        session.applyActualTreadmillDistance(meters)
        pending.result.distanceMeters = meters
        if pending.result.duration > 0, meters > 0 {
            pending.result.averagePaceSecPerKm = (pending.result.duration / meters) * 1_000
        }
        pendingTreadmillDistance = pending
        do {
            try record(pending.result)
            pendingTreadmillDistance = nil
        } catch {
            errorMessage = "Couldn’t save training data: \(error.localizedDescription)"
        }
    }

#if DEBUG
    func testing_handleWorkoutResult(_ result: WorkoutResult) {
        handleWorkoutResult(result)
    }
#endif

    private func handleWorkoutResult(_ result: WorkoutResult) {
        if var pending = pendingTreadmillDistance, WorkoutResultMerge.matches(pending.result, result) {
            if result.healthSync.state == .synced || result.healthSync.state == .failed {
                pending.result.healthSync = result.healthSync
                if let uuid = WorkoutResultMerge.resolvedHealthKitUUID(for: result) {
                    pending.result.healthKitUUID = uuid
                }
                if let route = result.route { pending.result.route = route }
                if let splits = result.splits { pending.result.splits = splits }
                pendingTreadmillDistance = pending
            }
            return
        }
        if result.location == .treadmill,
           session.usesManualTreadmillDistance,
           session.pendingActualTreadmillDistance == nil,
           pendingTreadmillDistance == nil {
            pendingTreadmillDistance = PendingTreadmillDistance(
                result: result,
                estimateMeters: result.distanceMeters
            )
            return
        }
        do {
            try record(resultPreservingConfirmedTreadmillDistance(result))
        } catch {
            errorMessage = "Couldn’t save training data: \(error.localizedDescription)"
        }
    }

    private func resultPreservingConfirmedTreadmillDistance(_ incoming: WorkoutResult) -> WorkoutResult {
        guard incoming.location == .treadmill,
              let index = WorkoutResultMerge.findIndex(of: incoming, in: results)
        else { return incoming }
        let existing = results[index]
        guard existing.location == .treadmill else { return incoming }
        var copy = incoming
        copy.distanceMeters = existing.distanceMeters
        if copy.duration > 0, existing.distanceMeters > 0 {
            copy.averagePaceSecPerKm = (copy.duration / existing.distanceMeters) * 1_000
        } else {
            copy.averagePaceSecPerKm = existing.averagePaceSecPerKm
        }
        return copy
    }

    func record(_ result: WorkoutResult) throws {
        let recordPlan = WorkoutResultMerge.planRecord(existing: results, incoming: result)
        let stored = recordPlan.mergedResult
        let previous = captureRecordedState()

        switch recordPlan.outcome {
        case .insert:
            results.insert(stored, at: 0)
        case .update:
            guard let index = recordPlan.existingIndex else { return }
            results[index] = stored
        }

        if recordPlan.shouldRunCompletionSideEffects {
            applyPlannedWorkoutCompletion(for: stored, incoming: result)
            let previousVDOT = profile?.vdot
            evaluateAdaptation(shouldPersist: false)
            celebration = makeCelebration(for: stored, previousVDOT: previousVDOT)
        } else {
            reconcilePlanEmbeddedResult(stored)
        }

        do {
            try persistThrowing()
            clearRecoverySnapshotIfResultExists(for: stored)
            if recordPlan.shouldRunCompletionSideEffects {
                pushWatchWorkouts()
            }
        } catch {
            restoreRecordedState(previous)
            errorMessage = "Couldn’t save training data: \(error.localizedDescription)"
            throw error
        }
    }

    func importHealthWorkouts() async {
        guard hasOnboarded else { return }
        healthImportInProgress = true
        defer { healthImportInProgress = false }
        let since = importWindowStart()
        let anchor = modelContext.flatMap { try? HealthImportAnchorStore.load(from: $0) }
        let previousResults = results
        let previousPlan = plan
        let importResult: HealthImportResult
        do {
            try await healthImporter.requestAuthorization()
            importResult = try await healthImporter.importWorkouts(anchor: anchor, since: since)
            results = HealthImportApply.apply(existing: results, importResult: importResult)
            for result in results {
                reconcilePlanEmbeddedResult(result)
            }
            applyMatchSuggestions()
            try persistThrowing()
            healthImportLastSuccessAt = Date()
            healthImportErrorMessage = nil
        } catch {
            results = previousResults
            plan = previousPlan
            healthImportDenied = healthImporter.authorizationDenied
            if !healthImportDenied {
                healthImportErrorMessage = "Couldn’t import Apple Health workouts: \(error.localizedDescription)"
            }
            return
        }
        do {
            if let newAnchor = importResult.newAnchor, let context = modelContext {
                try HealthImportAnchorStore.save(newAnchor, to: context)
            }
            healthImportDenied = false
        } catch {
            healthImportDenied = healthImporter.authorizationDenied
            if !healthImportDenied {
                healthImportErrorMessage = "Couldn’t import Apple Health workouts: \(error.localizedDescription)"
            }
        }
    }

    func confirmHealthMatch(_ selected: WorkoutResult, scheduledWorkoutID: UUID) {
        guard let index = WorkoutResultMerge.findIndex(of: selected, in: results) else { return }
        guard results[index].matchInfo.state != .matched else { return }
        guard let workout = plan?.workouts.first(where: { $0.id == scheduledWorkoutID }),
              workout.status == .scheduled || workout.status == .convertedToEasy
        else { return }
        let claimedByAnother = results.contains {
            $0.matchInfo.state == .matched
                && $0.matchInfo.scheduledWorkoutID == scheduledWorkoutID
                && !WorkoutResultMerge.matches($0, selected)
        }
        if claimedByAnother { return }
        if let embedded = workout.result, !WorkoutResultMerge.matches(embedded, selected) { return }

        let previous = captureRecordedState()
        var result = results[index]
        result.matchInfo = WorkoutMatchInfo(state: .matched, scheduledWorkoutID: scheduledWorkoutID)
        results[index] = result
        updateWorkout(scheduledWorkoutID, shouldPersist: false) { workout in
            var copy = workout
            copy.status = .completed
            copy.result = result
            return copy
        }
        evaluateAdaptation(shouldPersist: false)
        applyMatchSuggestions()
        do {
            try persistThrowing()
            pushWatchWorkouts()
            showToast("RUN LINKED TO PLAN")
        } catch {
            restoreRecordedState(previous)
            errorMessage = "Couldn’t save training data: \(error.localizedDescription)"
        }
    }

    func rejectHealthMatch(_ selected: WorkoutResult, suggestedWorkoutID: UUID) {
        guard let index = WorkoutResultMerge.findIndex(of: selected, in: results) else { return }
        persistResultMutation {
            var result = results[index]
            var rejected = result.matchInfo.rejectedWorkoutIDs
            if !rejected.contains(suggestedWorkoutID) { rejected.append(suggestedWorkoutID) }
            result.matchInfo = WorkoutMatchInfo(state: .ignored, rejectedWorkoutIDs: rejected)
            results[index] = result
            applyMatchSuggestions(for: result)
        }
    }

    func keepHealthUnmatched(_ selected: WorkoutResult) {
        guard WorkoutResultMerge.findIndex(of: selected, in: results) != nil else { return }
        persistResultMutation {
            guard let index = WorkoutResultMerge.findIndex(of: selected, in: results) else { return }
            results[index].matchInfo.state = .unmatched
        }
    }

    func unmatchHealthResult(_ selected: WorkoutResult) {
        guard let index = WorkoutResultMerge.findIndex(of: selected, in: results),
              let scheduledID = results[index].matchInfo.scheduledWorkoutID else { return }
        persistResultMutation(publishesWatchPlan: true) {
            guard let currentIndex = WorkoutResultMerge.findIndex(of: selected, in: results) else { return }
            var result = results[currentIndex]
            result.matchInfo = WorkoutMatchInfo(state: .unmatched)
            results[currentIndex] = result
            updateWorkout(scheduledID, shouldPersist: false) { workout in
                var copy = workout
                if copy.status == .completed, let embedded = copy.result, WorkoutResultMerge.matches(embedded, selected) {
                    copy.status = .scheduled
                    copy.result = nil
                }
                return copy
            }
        }
    }

    func openHealthSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func importWindowStart() -> Date {
        let cal = Calendar.current
        let ninetyDays = cal.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        if let planStart = plan?.workouts.map(\.date).min() {
            return max(ninetyDays, cal.startOfDay(for: planStart))
        }
        return ninetyDays
    }

    private func applyMatchSuggestions(for selected: WorkoutResult? = nil) {
        for index in results.indices {
            if let selected, !WorkoutResultMerge.matches(results[index], selected) { continue }
            let result = results[index]
            guard result.source == .appleHealth, result.matchInfo.state != .matched else { continue }
            let rejected = Set(result.matchInfo.rejectedWorkoutIDs)
            if let suggestion = WorkoutMatcher.bestSuggestion(for: result, plan: plan, rejectedIDs: rejected) {
                results[index].matchInfo.state = .suggested
                results[index].matchInfo.suggestedWorkoutID = suggestion
            } else if result.matchInfo.state != .ignored {
                results[index].matchInfo.state = .unmatched
                results[index].matchInfo.suggestedWorkoutID = nil
            }
        }
    }

    func alternateMatchCandidates(for result: WorkoutResult) -> [WorkoutMatchCandidate] {
        WorkoutMatcher.candidates(for: result, plan: plan)
    }

    func start(_ blueprint: WorkoutBlueprint, source: WorkoutSource? = nil) async {
        let resolvedSource = source ?? pendingWorkoutSource
        pendingWorkoutSource = .wrathspeedPhone
        do {
            session.splitUnit = unit
            session.cueStyle = cueStyle
            try await workoutCoordinator.start(
                blueprint: blueprint,
                vdot: profile?.vdot,
                zones: zones,
                cuesEnabled: cuesEnabled,
                source: resolvedSource,
                unit: unit
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Moves a future run onto today and opens preflight for it.
    ///
    /// Moving rather than starting it where it sits is what keeps Today honest afterwards:
    /// the result lands on a workout dated today, so `todaysCompletedRuns` and the week bar
    /// show it. `move` reports refusal through `errorMessage`, which RootView already
    /// surfaces, so the guard needs no second failure channel.
    func pullForwardAndStart(_ workout: ScheduledWorkout) {
        // Passing the reminder settings through deliberately: `move` defaults
        // `reminderEnabled` to false and assigns it unconditionally, so the plain call would
        // silently clear a reminder the user had set.
        move(
            workout,
            to: Date(),
            allowWarnings: true,
            scheduledTimeMinutes: workout.scheduledTimeMinutes,
            reminderEnabled: workout.reminderEnabled
        )
        guard let moved = todaysRuns.first else { return }
        presentPreflight(blueprint: moved.blueprint)
    }

    func presentPreflight(blueprint: WorkoutBlueprint, source: WorkoutSource = .wrathspeedPhone) {
        pendingPreflight = PreflightRequest(blueprint: blueprint, source: source)
    }

    func retryWatchLaunch() async {
        showWatchLaunchTimeout = false
        await workoutCoordinator.retryWatchLaunch()
    }

    func startOnPhoneAfterWatchTimeout() async {
        showWatchLaunchTimeout = false
        await workoutCoordinator.startOnPhoneAfterWatchTimeout()
    }

    func cancelWatchLaunch() {
        showWatchLaunchTimeout = false
        workoutCoordinator.cancelWatchLaunch()
    }

    func savePartialRecovery(from snapshot: ActiveSessionSnapshot) {
        guard let blueprint = try? JSONDecoder().decode(WorkoutBlueprint.self, from: snapshot.blueprintData) else {
            discardRecovery()
            return
        }
        let startedAt = snapshot.estimatedStartedAt()
        if results.contains(where: { WorkoutResultMerge.matches($0, WorkoutResult(
            workoutID: blueprint.id,
            startedAt: startedAt,
            duration: snapshot.elapsedSeconds,
            distanceMeters: snapshot.distanceMeters,
            averagePaceSecPerKm: nil,
            location: blueprint.location,
            source: snapshot.source
        )) }) {
            discardRecovery()
            return
        }
        let pace = snapshot.distanceMeters > 0 ? (snapshot.elapsedSeconds / snapshot.distanceMeters) * 1_000 : nil
        let result = WorkoutResult(
            workoutID: blueprint.id,
            startedAt: startedAt,
            duration: snapshot.elapsedSeconds,
            distanceMeters: snapshot.distanceMeters,
            averagePaceSecPerKm: pace,
            location: blueprint.location,
            source: snapshot.source,
            healthSync: snapshot.healthSync
        )
        do {
            try record(result)
            discardRecovery()
            showToast("PARTIAL WORKOUT SAVED")
        } catch {
            errorMessage = "Couldn’t save training data: \(error.localizedDescription)"
        }
    }

    func discardRecovery() {
        pendingRecoverySnapshot = nil
        if let context = modelContext {
            try? ActiveSessionStore.clear(from: context)
        }
    }

    func recordStrengthResult(_ result: StrengthSessionResult) throws {
        do {
            try persistStrengthResult(result)
        } catch {
            errorMessage = "Couldn't save strength session: \(error.localizedDescription)"
            throw error
        }
        upsertGuidedResult(&guidedStrengthResults, result, matches: StrengthSessionResult.matches)
    }

    func recordMobilityResult(_ result: MobilitySessionResult) throws {
        do {
            try persistMobilityResult(result)
        } catch {
            errorMessage = "Couldn't save mobility session: \(error.localizedDescription)"
            throw error
        }
        upsertGuidedResult(&guidedMobilityResults, result, matches: MobilitySessionResult.matches)
    }

    private func persistStrengthResult(_ result: StrengthSessionResult) throws {
        guard let context = modelContext else {
            throw AppPersistenceError.storageUnavailable
        }
#if DEBUG
        if repository?.forceGuidedResultSaveFailure == true {
            throw NSError(domain: "WrathspeedTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated guided result save failure"])
        }
#endif
        try GuidedSessionResultStore.upsertStrengthResult(result, to: context)
    }

    private func persistMobilityResult(_ result: MobilitySessionResult) throws {
        guard let context = modelContext else {
            throw AppPersistenceError.storageUnavailable
        }
#if DEBUG
        if repository?.forceGuidedResultSaveFailure == true {
            throw NSError(domain: "WrathspeedTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated guided result save failure"])
        }
#endif
        try GuidedSessionResultStore.upsertMobilityResult(result, to: context)
    }

    func startInstant(request: InstantWorkoutRequest) async {
        do {
            try InstantWorkoutValidation.validate(request)
            let blueprint = try InstantWorkoutBuilder.build(request)
            presentPreflight(blueprint: blueprint, source: .instant)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startInstant(kind: WorkoutKind, location: RunLocation) async {
        let request = InstantWorkoutRequest(kind: kind, location: location, distanceMeters: 5_000)
        await startInstant(request: request)
    }

    func managePlanSchedule(days: Set<Weekday>, daysPerWeek: Int, longRunDay: Weekday) throws -> PlanScheduleDiff {
        guard let profile, let plan else { throw PlanInputError.invalidWeeklyMileage }
        guard days.count >= 3 else { throw OnboardingValidationError.tooFewAvailableDays }
        guard days.contains(longRunDay) else { throw OnboardingValidationError.longRunNotAvailable }

        var previewProfile = profile
        previewProfile.availableWeekdays = days.sorted()
        previewProfile.daysPerWeek = daysPerWeek
        previewProfile.longRunWeekday = longRunDay

        var calendar = Calendar.current
        calendar.timeZone = .current
        let request = PlanRequest(goal: plan.goal, profile: previewProfile, startDate: Date(), calendar: calendar)
        let catalog = try strengthCatalogLoader()
        let generated = try TrainingPlanService.regenerate(
            request: request,
            existingPlan: plan,
            adjustment: nil,
            freezeMileageBaselineMeters: freezeMileage ? freezeMileageBaselineMeters : nil,
            strengthPreferences: strengthPrefs,
            strengthCatalog: catalog
        )
        return PlanAdjustmentService.diffFutureUnstarted(current: plan.workouts, proposed: generated.plan.workouts)
    }

    func applyManagePlanSchedule(days: Set<Weekday>, daysPerWeek: Int, longRunDay: Weekday) throws {
        guard profile != nil else { throw PlanInputError.invalidWeeklyMileage }
        var proposedProfile = profile!
        proposedProfile.availableWeekdays = days.sorted()
        proposedProfile.daysPerWeek = daysPerWeek
        proposedProfile.longRunWeekday = longRunDay
        performPlanMutation(
            description: "Updated schedule",
            kind: .scheduleRegeneration,
            affected: [],
            successToast: nil,
            mutate: {
                self.profile = proposedProfile
                let generated = try buildRegeneratedSchedule(profile: proposedProfile)
                plan = generated.plan
                strengthSessions = generated.strengthSessions
            }
        )
    }

    func updateStrengthPreferences(_ preferences: StrengthPreferences) {
        let normalized = StrengthPreferences(
            ability: preferences.ability,
            goal: preferences.goal,
            durationMinutes: preferences.durationMinutes,
            sessionsPerWeek: preferences.sessionsPerWeek,
            preferredDays: preferences.preferredDays,
            equipment: preferences.equipment
        )
        do {
            var reconciledSessions = strengthSessions
            if let plan {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let planEnd = plan.workouts.map(\.date).max() ?? today
                let daysRemaining = max(0, calendar.dateComponents([.day], from: today, to: planEnd).day ?? 0)
                let weekCount = max(1, Int(ceil(Double(daysRemaining + 1) / 7.0)))
                let generated = StrengthPlanner.schedule(
                    preferences: normalized,
                    startDate: today,
                    weekCount: weekCount,
                    calendar: calendar,
                    catalog: try strengthCatalogLoader()
                ).filter { $0.date <= planEnd }
                reconciledSessions = StrengthSessionReconciler.reconcile(
                    existing: strengthSessions,
                    generated: generated,
                    asOf: today,
                    calendar: calendar
                )
            }
            strengthPrefs = normalized
            strengthSessions = reconciledSessions
            persist()
            pushWatchWorkouts()
        } catch {
            errorMessage = "Couldn’t update strength sessions: \(error.localizedDescription)"
        }
    }

    func showToast(_ message: String) {
        toastMessage = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(WSMotion.toast))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    func toggleLiveMetric(_ metric: LiveMetric) {
        if liveMetrics.contains(metric) {
            if liveMetrics.count > 1 { liveMetrics.remove(metric) }
        } else {
            liveMetrics.insert(metric)
        }
        persist()
    }

    func setDataDensity(_ density: DataDensity) {
        dataDensity = density
        persist()
    }

    func setCueStyle(_ style: CueStyle) {
        cueStyle = style
        session.cueStyle = style
        persist()
    }

    func comparison(for result: WorkoutResult) -> String? {
        guard let workout = plan?.workouts.first(where: { $0.blueprint.id == result.workoutID || $0.id == result.workoutID }) else {
            return nil
        }
        let planned = workout.blueprint.plannedDistanceMeters
        guard planned > 0 else { return nil }
        let delta = result.distanceMeters - planned
        let distance = WSFormat.distance(abs(delta), unit: unit)
        let vsDistance = delta >= 0 ? "+\(distance) VS PLAN" : "-\(distance) VS PLAN"
        guard workout.blueprint.usesPaceTargets,
              let actual = result.averagePaceSecPerKm,
              let target = WorkoutPaceTarget.targetPaceSecPerKm(blueprint: workout.blueprint, zones: zones)
        else { return vsDistance }
        let faster = actual < target
        return "\(vsDistance) · PACE \(faster ? "FASTER" : "SLOWER") THAN TARGET"
    }

    func resolvedSplits(for result: WorkoutResult) -> [WorkoutSplit] {
        if let splits = result.splits, !splits.isEmpty { return splits }
        if let route = result.route { return SplitBuilder.fromRoute(route, unit: unit) }
        return []
    }

    func weekGroups() -> [(start: Date, workouts: [ScheduledWorkout])] {
        guard let plan = displayPlan else { return [] }
        let groups = Dictionary(grouping: plan.workouts) {
            Calendar.current.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date
        }
        return groups.keys.sorted().map { (start: $0, workouts: groups[$0]!.sorted { $0.date < $1.date }) }
    }

    func rollingFourWeekSummaries() -> [WeeklyLoadSummary] {
        HistoryInsights.rollingFourWeekSummaries(plan: displayPlan, results: results)
    }

    func currentWeekSummary() -> WeeklyLoadSummary? {
        guard let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start else { return nil }
        return HistoryInsights.weeklySummary(plan: displayPlan, results: results, weekStart: start)
    }

    func currentWeekIndex() -> (current: Int, total: Int) {
        guard let plan else { return (1, 1) }
        let groups = weekGroups()
        let today = Date()
        let index = groups.firstIndex { WeekWindow(startingAt: $0.start)?.contains(today) ?? false } ?? 0
        return (index + 1, max(1, plan.goal.weekCount))
    }

    private func applyPersistedState(_ state: PersistedState) {
        hasOnboarded = state.hasOnboarded
        profile = state.profile
        plan = state.plan
        n100 = state.n100
        strengthPrefs = state.strengthPrefs
        strengthSessions = state.strengthSessions
        cuesEnabled = state.cuesEnabled
        freezeMileage = state.freezeMileage
        freezeMileageBaselineMeters = state.freezeMileageBaselineMeters
        results = state.results
        liveMetrics = state.liveMetrics
        dataDensity = state.dataDensity
        cueStyle = state.cueStyle
        mobilityPrefs = state.mobilityPrefs
        if let vdot = state.pendingVDOT, let reason = state.pendingVDOTReason {
            pendingSuggestion = VDOTSuggestion(newVDOT: vdot, reason: reason)
        } else {
            pendingSuggestion = nil
        }
    }

    private func finishAttach() {
        workoutCoordinator.configure(cuesEnabled: cuesEnabled, zones: zones, onResult: { [weak self] result in
            self?.handleWorkoutResult(result)
        }, onFailure: { [weak self] error in
            self?.errorMessage = "Workout wasn't saved to Health: \(error.localizedDescription)"
        })
        // The Watch wait times out 12 seconds after `start` returns, so this is the only
        // place that can see `.timedOut`. Reading the phase after `await` -- which is what
        // this replaces -- always saw `.waitingForWatch`, leaving the watch-not-ready sheet
        // and its START ON PHONE fallback permanently unreachable.
        workoutCoordinator.onWatchLaunchPhaseChange = { [weak self] phase in
            self?.showWatchLaunchTimeout = phase == .timedOut
        }
        session.onSnapshot = { [weak self] snapshot in
            self?.handleSessionSnapshot(snapshot)
        }
        workoutCoordinator.installMirroringHandler()
        pushWatchWorkouts()
        if let result = workoutCoordinator.consumeLatestResult() {
            handleWorkoutResult(result)
        }
        loadGuidedSessionResults()
        restorePendingRecoverySnapshotIfNeeded()
    }

    private func loadGuidedSessionResults() {
        guard let context = modelContext else { return }
        do {
            guidedStrengthResults = try GuidedSessionResultStore.loadStrengthResults(from: context)
            guidedMobilityResults = try GuidedSessionResultStore.loadMobilityResults(from: context)
        } catch {
            errorMessage = "Couldn't load guided session history: \(error.localizedDescription)"
        }
    }

    private func restorePendingRecoverySnapshotIfNeeded() {
        guard let context = modelContext else { return }
        guard let snapshot = try? ActiveSessionStore.load(from: context) else { return }
        if results.contains(where: { snapshot.matchesResult($0) }) {
            try? ActiveSessionStore.clear(from: context)
            return
        }
        guard snapshot.state.isRecoverableUnfinishedSession else {
            try? ActiveSessionStore.clear(from: context)
            return
        }
        pendingRecoverySnapshot = snapshot
    }

    private func handleSessionSnapshot(_ snapshot: ActiveSessionSnapshot) {
        guard let context = modelContext else { return }
        if results.contains(where: { snapshot.matchesResult($0) }) {
            try? ActiveSessionStore.clear(from: context)
            pendingRecoverySnapshot = nil
            return
        }
        guard snapshot.state.isRecoverableUnfinishedSession else {
            if snapshot.state == .saved {
                clearMatchingStartupRecovery(for: snapshot, in: context)
            }
            return
        }
        do {
            try ActiveSessionStore.save(snapshot, to: context)
        } catch {
            errorMessage = "Couldn't save workout recovery state: \(error.localizedDescription)"
        }
    }

    private func clearMatchingStartupRecovery(for snapshot: ActiveSessionSnapshot, in context: ModelContext) {
        if let pending = pendingRecoverySnapshot,
           pending.matchesStartupTerminalClear(from: snapshot) {
            pendingRecoverySnapshot = nil
        }
        if let stored = try? ActiveSessionStore.load(from: context),
           stored.matchesStartupTerminalClear(from: snapshot) {
            try? ActiveSessionStore.clear(from: context)
        }
    }

    private func clearRecoverySnapshotIfResultExists(for result: WorkoutResult) {
        guard let context = modelContext else { return }
        if pendingRecoverySnapshot?.matchesResult(result) == true {
            pendingRecoverySnapshot = nil
        }
        if let snapshot = try? ActiveSessionStore.load(from: context), snapshot.matchesResult(result) {
            try? ActiveSessionStore.clear(from: context)
        }
    }

    private func evaluateAdaptation(shouldPersist: Bool = true) {
        guard let plan, let profile else { return }
        let cal = Calendar.current
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let skipped = plan.workouts.filter {
            $0.status == .skipped && $0.date >= startOfWeek
        }.count
        let quality = plan.workouts.compactMap { workout -> QualitySession? in
            guard workout.blueprint.kind.isQuality, let result = workout.result, let actual = result.averagePaceSecPerKm else { return nil }
            let zone: PaceZone = workout.blueprint.kind == .tempo ? .threshold : .interval
            guard let target = zones?.secondsPerKilometer(for: zone) else { return nil }
            return QualitySession(targetPaceSecPerKm: target, actualPaceSecPerKm: actual)
        }
        let decision = AdaptationRules.evaluate(
            skippedThisWeek: skipped,
            qualitySessions: quality,
            currentVDOT: profile.vdot
        )
        if decision.freezeMileageIncrease && !freezeMileage {
            freezeMileageBaselineMeters = currentWeekMileage(in: plan, calendar: cal)
        }
        freezeMileage = decision.freezeMileageIncrease
        pendingSuggestion = decision.vdotSuggestion
        if shouldPersist {
            persist()
        }
    }

    private func applyPlannedWorkoutCompletion(for stored: WorkoutResult, incoming: WorkoutResult) {
        if stored.matchInfo.state == .matched, let scheduledID = stored.matchInfo.scheduledWorkoutID {
            updateWorkout(scheduledID, shouldPersist: false) { workout in
                var copy = workout
                copy.status = .completed
                copy.result = stored
                return copy
            }
        } else if incoming.source != .instant, plan?.workouts.contains(where: { $0.id == incoming.workoutID || $0.blueprint.id == incoming.workoutID }) == true {
            updateWorkout(incoming.workoutID, shouldPersist: false) { workout in
                var copy = workout
                copy.status = .completed
                copy.result = stored
                return copy
            }
        }
    }

    private func updateWorkout(_ id: UUID, shouldPersist: Bool = true, transform: (ScheduledWorkout) -> ScheduledWorkout) {
        guard var plan else { return }
        plan.workouts = plan.workouts.map { $0.id == id || $0.blueprint.id == id ? transform($0) : $0 }
        self.plan = plan
        if shouldPersist {
            persist()
            pushWatchWorkouts()
        }
    }

    private func currentWeekMileage(in plan: TrainingPlan, calendar: Calendar) -> Double {
        let window = calendar.weekWindow(for: Date())
        return plan.workouts.filter { workout in
            workout.status == .scheduled && workout.blueprint.kind.isRunning && workout.blueprint.kind != .race
                && (window?.contains(workout.date) ?? false)
        }.reduce(0) { $0 + $1.blueprint.plannedDistanceMeters }
    }

    private func weekMileage(completed: Bool) -> (done: Double, planned: Double) {
        guard let plan else { return (0, 0) }
        let window = Calendar.current.weekWindow(for: Date())
        let week = plan.workouts.filter {
            $0.blueprint.kind.isRunning && (window?.contains($0.date) ?? false)
        }
        let planned = week.reduce(0) { $0 + $1.blueprint.plannedDistanceMeters }
        let done = week.filter { $0.status == .completed }.reduce(0) { $0 + ($1.result?.distanceMeters ?? $1.blueprint.plannedDistanceMeters) }
        return (done, planned)
    }

    private func streakCount(asOf date: Date = Date()) -> Int {
        let days = Set(results.map { Calendar.current.startOfDay(for: $0.startedAt) })
        var cursor = Calendar.current.startOfDay(for: date)
        if !days.contains(cursor) {
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private func makeCelebration(for result: WorkoutResult, previousVDOT: Double?) -> CelebrationPayload {
        let workout = plan?.workouts.first { $0.blueprint.id == result.workoutID || $0.id == result.workoutID }
        let mileage = weekMileage(completed: true)
        return CelebrationPayload(
            title: workout?.blueprint.title ?? "Run",
            date: result.startedAt,
            distanceMeters: result.distanceMeters,
            duration: result.duration,
            averagePaceSecPerKm: result.averagePaceSecPerKm,
            prCopy: prCopy(for: result, kind: workout?.blueprint.kind ?? .freeRun),
            streak: streakCount(asOf: result.startedAt),
            weekCompletedMeters: mileage.done,
            weekPlannedMeters: mileage.planned,
            previousVDOT: previousVDOT,
            suggestion: pendingSuggestion
        )
    }

    private func prCopy(for result: WorkoutResult, kind: WorkoutKind) -> String? {
        let splits = resolvedSplits(for: result)
        let newBest = splits.map(\.paceSecPerKm).min() ?? result.averagePaceSecPerKm
        guard let newBest else { return nil }
        let previousBest = results.dropFirst().compactMap { existing -> Double? in
            let existingSplits = resolvedSplits(for: existing)
            return existingSplits.map(\.paceSecPerKm).min() ?? existing.averagePaceSecPerKm
        }.min()
        guard previousBest == nil || newBest < (previousBest ?? .greatestFiniteMagnitude) else { return nil }
        let label = kind == .tempo ? "THRESHOLD" : kind.title.uppercased()
        let unitLabel = unit == .miles ? "MILE" : "KM"
        return "FASTEST \(label) \(unitLabel) — \(WSFormat.paceClock(newBest, unit: unit))"
    }

    private func pushWatchWorkouts() {
#if DEBUG
        watchPublicationCountForTesting += 1
#endif
        let upcoming = upcomingRuns.prefix(14).map(\.blueprint)
        workoutCoordinator.pushUpcoming(UpcomingWorkoutsPayload(blueprints: Array(upcoming), vdot: profile?.vdot, unit: unit))
    }

    func save() {
        persist()
    }

#if DEBUG
    func setForceSaveFailureForTesting(_ value: Bool) {
        repository?.forceSaveFailure = value
    }

    func setForceSaveFailureAfterMutationForTesting(_ value: Bool) {
        repository?.forceSaveFailureAfterMutation = value
    }

    func setForceGuidedResultSaveFailureForTesting(_ value: Bool) {
        repository?.forceGuidedResultSaveFailure = value
    }

    func setForcePlanChangeFailureForTesting(_ value: Bool) {
        repository?.forcePlanChangeFailure = value
    }

    /// Reaches Today without replaying onboarding, for the sixteen UI tests whose subject
    /// is not onboarding. Replaying nine taps and a plan build was about four fifths of the
    /// whole UI suite's runtime.
    ///
    /// Deliberately routed through the same two calls `OnboardingView` makes, with no
    /// hand-assigned `plan` or `hasOnboarded`, so the seeded store cannot drift from the
    /// tapped one -- and so the three seeds `confirmOnboarding` already runs come for free.
    /// The inputs reproduce exactly what `UITestOnboardingHelper.completeOnboarding`
    /// produces: `OnboardingInputs()` defaults, because the helper taps NEXT past every step
    /// without selecting anything; `.miles`, the one row it does tap; and the race date that
    /// `OnboardingView.normalizeDraftInputs()` fills in on the first advance, without which
    /// `OnboardingValidator` rejects the default `.race` goal as `.missingRaceDate`.
    func seedCompletedOnboardingForUITestingIfNeeded() {
        guard UITestingSupport.shouldSeedCompletedOnboarding, !hasOnboarded else { return }
        var inputs = OnboardingInputs()
        inputs.unit = .miles
        inputs.raceDate = Calendar.current.date(
            byAdding: .weekOfYear,
            value: inputs.goalKind.minimumWeeks,
            to: Date()
        )
        do {
            let draft = try generateOnboardingDraft(from: inputs)
            confirmOnboarding(draft: draft)
        } catch {
            errorMessage = "Couldn’t seed onboarding for UI testing: \(error.localizedDescription)"
        }
    }

    func seedInProgressMobilityForUITestingIfNeeded() {
        guard UITestingSupport.shouldSeedInProgressMobility else { return }
        guard GuidedSessionPolicy.inProgressMobility(routineID: "pre_run", in: guidedMobilityResults) == nil else { return }
        guard let session = (try? MobilityCatalogLoader.allSessions())?.first(where: { $0.routineID == "pre_run" }),
              let firstMovement = session.movements.first else { return }
        let result = MobilitySessionResult(
            id: UUID(),
            sessionID: session.id,
            startedAt: Date(),
            endedAt: Date(),
            completedMovementIDs: [firstMovement.id],
            routineID: session.routineID,
            lifecycle: .inProgress,
            progress: MobilitySessionProgress(movementIndex: 1, remainingSeconds: 30)
        )
        try? recordMobilityResult(result)
    }

    /// Pulls the next scheduled run onto today so Today always has one to start. A
    /// generated plan places runs on particular weekdays, so whether one falls on the day
    /// the suite runs is otherwise down to the calendar.
    func seedTodayRunForUITestingIfNeeded() {
        guard UITestingSupport.shouldSeedTodayRun, todaysRuns.isEmpty, var plan else { return }
        let today = Calendar.current.startOfDay(for: Date())
        guard let index = plan.workouts.firstIndex(where: {
            $0.blueprint.kind.isRunning && $0.status == .scheduled && $0.date > today
        }) else { return }
        plan.workouts[index].blueprint.date = today
        // Pulling a future run back to today moves it past everything between, so a UI test
        // reading the plan sees the same order a real move would leave behind.
        plan.restoreDateOrder()
        self.plan = plan
        persist()
    }

    /// The same, for the strength session Today offers.
    ///
    /// Picks a session containing a hold rather than simply the next one. Only `fullBody`
    /// sessions carry one -- with the default two-a-week split the other is `legsCore`, which
    /// has none -- so "the next session" was a coin flip on today's weekday, which is the trap
    /// `UITestOnboardingHelper` documents as having made two tests fail only on a Friday.
    /// Tests that do not care about holds are unaffected: every focus opens with a squat.
    /// The contract is "today offers a strength session containing a hold", not "today offers
    /// some strength session". The difference matters: the guard used to be
    /// `todaysStrength.isEmpty`, so whenever today already carried a session the seed did
    /// nothing at all and the test ran against whatever happened to be there. That is how a CI
    /// run reached `StrengthHoldLogUITests` with a legs-and-core session -- no hold in it
    /// anywhere -- and failed hunting for a hold card, while the same test passed locally.
    /// Seeding has to leave the same state however the day was arranged beforehand.
    func seedTodayStrengthForUITestingIfNeeded() {
        guard UITestingSupport.shouldSeedTodayStrength else { return }
        func carriesHold(_ session: StrengthSession) -> Bool {
            session.sets.contains { $0.exercise.holdSeconds != nil }
        }
        guard !todaysStrength.contains(where: carriesHold) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        guard let index = strengthSessions.firstIndex(where: { session in
            session.date > today && carriesHold(session)
        }) else { return }
        // Anything already sitting on today is moved out of the way first. Today offers
        // `todaysStrength.first`, so leaving a second session there would make which one the
        // test sees depend on array order.
        let displaced = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        for existing in strengthSessions.indices where Calendar.current.isDateInToday(strengthSessions[existing].date) {
            strengthSessions[existing].date = displaced
        }
        strengthSessions[index].date = today
        persist()
    }
#endif

    func setReminderSchedulerForTesting(_ scheduler: any WorkoutReminderScheduling) {
        reminderScheduler = scheduler
    }

    private func buildRegeneratedSchedule(
        goal: TrainingGoal? = nil,
        profile: RunnerProfile? = nil
    ) throws -> GeneratedTrainingSchedule {
        guard let profile = profile ?? self.profile else { throw PlanInputError.invalidWeeklyMileage }
        let goal = goal ?? plan?.goal ?? TrainingGoal(kind: .fiveK)
        var calendar = Calendar.current
        calendar.timeZone = .current
        let request = PlanRequest(goal: goal, profile: profile, startDate: Date(), calendar: calendar)
        let catalog = try strengthCatalogLoader()
        return try TrainingPlanService.regenerate(
            request: request,
            existingPlan: plan,
            adjustment: nil,
            freezeMileageBaselineMeters: freezeMileage ? freezeMileageBaselineMeters : nil,
            strengthPreferences: strengthPrefs,
            strengthCatalog: catalog
        )
    }

    private struct PlanMutationSnapshot {
        var plan: TrainingPlan?
        var n100: N100Adjustment?
        var profile: RunnerProfile?
        var strengthSessions: [StrengthSession]
        var freezeMileage: Bool
        var freezeMileageBaselineMeters: Double?
        var pendingSuggestion: VDOTSuggestion?
        var lastUndoDescription: String?
    }

    private func capturePlanMutationSnapshot() -> PlanMutationSnapshot {
        PlanMutationSnapshot(
            plan: plan,
            n100: n100,
            profile: profile,
            strengthSessions: strengthSessions,
            freezeMileage: freezeMileage,
            freezeMileageBaselineMeters: freezeMileageBaselineMeters,
            pendingSuggestion: pendingSuggestion,
            lastUndoDescription: lastUndoDescription
        )
    }

    private func restorePlanMutationSnapshot(_ snapshot: PlanMutationSnapshot) {
        plan = snapshot.plan
        n100 = snapshot.n100
        profile = snapshot.profile
        strengthSessions = snapshot.strengthSessions
        freezeMileage = snapshot.freezeMileage
        freezeMileageBaselineMeters = snapshot.freezeMileageBaselineMeters
        pendingSuggestion = snapshot.pendingSuggestion
        lastUndoDescription = snapshot.lastUndoDescription
    }

    private var reminderReconciliationTask: Task<Void, Never>?

    func awaitReminderReconciliation() async {
        await reminderReconciliationTask?.value
    }

    private func performPlanMutation(
        description: String,
        kind: PlanChangeKind,
        affected: [UUID],
        successToast: String?,
        publishesWatch: Bool = true,
        evaluateAdaptationAfter: Bool = false,
        mutate: () throws -> Void
    ) {
        guard plan != nil else { return }
        let snapshot = capturePlanMutationSnapshot()
        let workoutsBefore = plan?.workouts ?? []
        let undoSnapshot = PlanUndoSnapshot(plan: plan!, n100: n100)
        guard let undoData = try? JSONEncoder().encode(undoSnapshot) else {
            errorMessage = "Couldn't record plan change."
            return
        }

        let change = PlanChange(
            kind: kind,
            affectedWorkoutIDs: affected,
            previousSnapshot: undoData,
            description: description
        )

        do {
            try mutate()
            if evaluateAdaptationAfter {
                evaluateAdaptation(shouldPersist: false)
            }
            try stagePlanChange(change)
            try persistThrowing()
        } catch {
            restorePlanMutationSnapshot(snapshot)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't save training data: \(error.localizedDescription)"
            return
        }

        if publishesWatch {
            pushWatchWorkouts()
        }
        if let successToast {
            showToast(successToast)
        }
        offerUndo()
        reconcileReminders(before: workoutsBefore, after: plan?.workouts ?? [])
    }

    private func updateWorkoutInPlan(_ id: UUID, transform: (ScheduledWorkout) -> ScheduledWorkout) throws {
        guard var currentPlan = plan else { throw AppPersistenceError.storageUnavailable }
        currentPlan.workouts = currentPlan.workouts.map { workout in
            workout.id == id || workout.blueprint.id == id ? transform(workout) : workout
        }
        // `moveWorkout` comes through here, and a moved workout keeps its old index until this
        // runs. Consumers that render `workouts` directly show it in the wrong place otherwise.
        currentPlan.restoreDateOrder()
        plan = currentPlan
    }

    private func reconcileReminders(before: [ScheduledWorkout], after: [ScheduledWorkout]) {
        let operations = WorkoutReminderReconciliation.operations(
            before: before,
            after: after,
            calendar: Calendar.current
        )
        guard !operations.isEmpty else { return }
        reminderReconciliationTask = Task {
            await executeReminderOperations(operations)
        }
    }

    private func executeReminderOperations(_ operations: [WorkoutReminderOperation]) async {
        reminderNotice = nil
        for operation in operations {
            switch operation {
            case .cancel(let workoutID):
                await reminderScheduler.cancelReminder(workoutID: workoutID)
            case .schedule(let workoutID, let fireDate, let title):
                let granted = await reminderScheduler.requestAuthorizationIfNeeded()
                guard granted else {
                    reminderNotice = WorkoutReminderSchedulingError.permissionDenied.errorDescription
                    continue
                }
                do {
                    try await reminderScheduler.scheduleReminder(workoutID: workoutID, fireDate: fireDate, title: title)
                } catch {
                    reminderNotice = (error as? LocalizedError)?.errorDescription ?? WorkoutReminderSchedulingError.schedulingFailed.errorDescription
                }
            }
        }
    }

    private func currentPersistedState() -> PersistedState {
        PersistedState(
            hasOnboarded: hasOnboarded,
            profile: profile,
            plan: plan,
            n100: n100,
            strengthPrefs: strengthPrefs,
            strengthSessions: strengthSessions,
            cuesEnabled: cuesEnabled,
            freezeMileage: freezeMileage,
            freezeMileageBaselineMeters: freezeMileageBaselineMeters,
            pendingVDOT: pendingSuggestion?.newVDOT,
            pendingVDOTReason: pendingSuggestion?.reason,
            results: results,
            liveMetrics: liveMetrics,
            dataDensity: dataDensity,
            cueStyle: cueStyle,
            mobilityPrefs: mobilityPrefs
        )
    }

    private func persist() {
        do {
            try persistThrowing()
        } catch {
            errorMessage = "Couldn’t save training data: \(error.localizedDescription)"
        }
    }

    private func persistThrowing() throws {
        guard let repository else { throw AppPersistenceError.storageUnavailable }
        try repository.save(currentPersistedState())
    }

    private struct RecordedStateSnapshot {
        var results: [WorkoutResult]
        var plan: TrainingPlan?
        var profile: RunnerProfile?
        var celebration: CelebrationPayload?
        var pendingSuggestion: VDOTSuggestion?
        var freezeMileage: Bool
        var freezeMileageBaselineMeters: Double?
    }

    private func captureRecordedState() -> RecordedStateSnapshot {
        RecordedStateSnapshot(
            results: results,
            plan: plan,
            profile: profile,
            celebration: celebration,
            pendingSuggestion: pendingSuggestion,
            freezeMileage: freezeMileage,
            freezeMileageBaselineMeters: freezeMileageBaselineMeters
        )
    }

    private func restoreRecordedState(_ snapshot: RecordedStateSnapshot) {
        results = snapshot.results
        plan = snapshot.plan
        profile = snapshot.profile
        celebration = snapshot.celebration
        pendingSuggestion = snapshot.pendingSuggestion
        freezeMileage = snapshot.freezeMileage
        freezeMileageBaselineMeters = snapshot.freezeMileageBaselineMeters
    }

    private func persistResultMutation(publishesWatchPlan: Bool = false, _ mutate: () -> Void) {
        let previous = captureRecordedState()
        mutate()
        do {
            try persistThrowing()
            if publishesWatchPlan {
                pushWatchWorkouts()
            }
        } catch {
            restoreRecordedState(previous)
            errorMessage = "Couldn’t save training data: \(error.localizedDescription)"
        }
    }

    private func reconcilePlanEmbeddedResult(_ stored: WorkoutResult) {
        guard var plan else { return }
        var changed = false
        for index in plan.workouts.indices {
            guard let embedded = plan.workouts[index].result,
                  WorkoutResultMerge.matches(embedded, stored) else { continue }
            plan.workouts[index].result = stored
            changed = true
        }
        if changed {
            self.plan = plan
        }
    }

    private func upsertGuidedResult<T>(
        _ items: inout [T],
        _ result: T,
        matches: (T, T) -> Bool
    ) where T: StrengthOrMobilityResult {
        if let index = items.firstIndex(where: { matches($0, result) }) {
            items[index] = result
        } else {
            items.insert(result, at: 0)
        }
        items.sort { $0.startedAt > $1.startedAt }
    }
}

private protocol StrengthOrMobilityResult {
    var startedAt: Date { get }
}

extension StrengthSessionResult: StrengthOrMobilityResult {}
extension MobilitySessionResult: StrengthOrMobilityResult {}
