import Foundation
import HealthKit
import SwiftData
import WrathspeedCore

@MainActor
@Observable
final class AppStore {
    var hasOnboarded = false
    var profile: RunnerProfile?
    var plan: TrainingPlan?
    var n100: N100Adjustment?
    var strengthPrefs = StrengthPreferences()
    var strengthSessions: [StrengthSession] = []
    var cuesEnabled = true
    var freezeMileage = false
    var pendingSuggestion: VDOTSuggestion?
    var results: [WorkoutResult] = []
    var errorMessage: String?

    let session = WorkoutSessionController()
    let bridge = WCSessionBridge()
    private var context: ModelContext?
    private var didAttach = false

    var unit: DistanceUnit { profile?.unit ?? DistanceUnit.default() }
    var zones: PaceZones? {
        guard let vdot = profile?.vdot else { return nil }
        return PaceCalculator.zones(vdot: vdot)
    }

    var todaysRuns: [ScheduledWorkout] {
        guard let plan else { return [] }
        return plan.workouts.filter { Calendar.current.isDateInToday($0.date) && $0.status == .scheduled }
    }

    var todaysStrength: [StrengthSession] {
        strengthSessions.filter { Calendar.current.isDateInToday($0.date) }
    }

    var upcomingRuns: [ScheduledWorkout] {
        guard let plan else { return [] }
        return plan.workouts
            .filter { $0.status == .scheduled && $0.date >= Calendar.current.startOfDay(for: Date()) }
            .sorted { $0.date < $1.date }
    }

    func attach(context: ModelContext) {
        self.context = context
        guard !didAttach else { return }
        didAttach = true
        let state = Persistence.load(from: context)
        hasOnboarded = state.hasOnboarded
        profile = state.profile
        plan = state.plan
        n100 = state.n100
        strengthPrefs = state.strengthPrefs
        strengthSessions = state.strengthSessions
        cuesEnabled = state.cuesEnabled
        freezeMileage = state.freezeMileage
        results = state.results
        if let vdot = state.pendingVDOT, let reason = state.pendingVDOTReason {
            pendingSuggestion = VDOTSuggestion(newVDOT: vdot, reason: reason)
        }
        session.cuesEnabled = cuesEnabled
        session.zones = zones
        session.onFinished = { [weak self] result in
            self?.record(result)
        }
        installMirrorHandler()
        pushWatchWorkouts()
        if let result = bridge.latestResult {
            record(result)
            bridge.latestResult = nil
        }
    }

    func completeOnboarding(goal: TrainingGoal, profile: RunnerProfile, strength: StrengthPreferences) {
        self.profile = profile
        self.strengthPrefs = strength
        hasOnboarded = true
        regeneratePlan(goal: goal, profile: profile)
    }

    func regeneratePlan(goal: TrainingGoal? = nil, profile: RunnerProfile? = nil) {
        guard let profile = profile ?? self.profile else { return }
        let goal = goal ?? plan?.goal ?? TrainingGoal(kind: .fiveK)
        var calendar = Calendar.current
        calendar.timeZone = .current
        var generated = PlanGenerator.generate(
            PlanRequest(goal: goal, profile: profile, startDate: Date(), calendar: calendar)
        )
        if freezeMileage, let existing = plan {
            generated.workouts = blendFuture(from: existing, into: generated)
        }
        if let n100 {
            generated.workouts = NotFeeling100Rules.apply(workouts: generated.workouts, adjustment: n100, calendar: calendar)
        }
        if let catalog = try? StrengthPlanner.loadCatalog() {
            strengthSessions = StrengthPlanner.schedule(
                preferences: strengthPrefs,
                startDate: Date(),
                weekCount: generated.goal.weekCount,
                calendar: calendar,
                catalog: catalog
            )
            generated.strengthWorkouts = StrengthPlanner.asScheduledWorkouts(strengthSessions)
        }
        plan = generated
        self.profile = profile
        persist()
        pushWatchWorkouts()
    }

    func skip(_ workout: ScheduledWorkout, convertQuality: Bool = false) {
        updateWorkout(workout.id) { AdaptationRules.applySkip($0, convertQualityToEasy: convertQuality) }
        evaluateAdaptation()
    }

    func move(_ workout: ScheduledWorkout, to date: Date) {
        if workout.blueprint.kind == .longRun, !AdaptationRules.canMoveLongRun(from: workout.date, to: date) {
            errorMessage = "Long runs can only move within 48 hours."
            return
        }
        if let plan, AdaptationRules.wouldStackQuality(existing: plan.workouts, moving: workout, to: date, calendar: .current) {
            errorMessage = "That would stack two quality days."
            return
        }
        updateWorkout(workout.id) { current in
            var copy = current
            copy.blueprint.date = Calendar.current.startOfDay(for: date)
            return copy
        }
    }

    func applyNotFeeling100(_ adjustment: N100Adjustment) {
        n100 = adjustment
        if var plan {
            plan.workouts = NotFeeling100Rules.apply(workouts: plan.workouts, adjustment: adjustment, calendar: .current)
            self.plan = plan
        }
        persist()
        pushWatchWorkouts()
    }

    func acceptVDOTSuggestion() {
        guard var profile, let pendingSuggestion else { return }
        profile.vdot = pendingSuggestion.newVDOT
        self.profile = profile
        self.pendingSuggestion = nil
        regeneratePlan(profile: profile)
    }

    func declineVDOTSuggestion() {
        pendingSuggestion = nil
        persist()
    }

    func record(_ result: WorkoutResult) {
        results.insert(result, at: 0)
        updateWorkout(result.workoutID) { workout in
            var copy = workout
            copy.status = .completed
            copy.result = result
            return copy
        }
        evaluateAdaptation()
        persist()
    }

    func start(_ blueprint: WorkoutBlueprint) async {
        session.zones = zones
        session.cuesEnabled = cuesEnabled
        do {
            if WCSessionBridge.isWatchAppInstalled {
                bridge.requestStart(blueprint)
            }
            try await session.start(blueprint: blueprint, zones: zones)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startInstant(kind: WorkoutKind, location: RunLocation) async {
        let blueprint = InstantWorkoutFactory.make(kind: kind, location: location, date: Date())
        await start(blueprint)
    }

    private func evaluateAdaptation() {
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
        freezeMileage = decision.freezeMileageIncrease
        pendingSuggestion = decision.vdotSuggestion
        persist()
    }

    private func updateWorkout(_ id: UUID, transform: (ScheduledWorkout) -> ScheduledWorkout) {
        guard var plan else { return }
        plan.workouts = plan.workouts.map { $0.id == id || $0.blueprint.id == id ? transform($0) : $0 }
        self.plan = plan
        persist()
        pushWatchWorkouts()
    }

    private func blendFuture(from existing: TrainingPlan, into generated: TrainingPlan) -> [ScheduledWorkout] {
        let today = Calendar.current.startOfDay(for: Date())
        let past = existing.workouts.filter { $0.date < today }
        let future = generated.workouts.filter { $0.date >= today }
        return (past + future).sorted { $0.date < $1.date }
    }

    private func pushWatchWorkouts() {
        let upcoming = upcomingRuns.prefix(14).map(\.blueprint)
        bridge.pushUpcoming(UpcomingWorkoutsPayload(blueprints: Array(upcoming), vdot: profile?.vdot))
    }

    func save() {
        persist()
    }

    private func persist() {
        guard let context else { return }
        Persistence.save(
            PersistedState(
                hasOnboarded: hasOnboarded,
                profile: profile,
                plan: plan,
                n100: n100,
                strengthPrefs: strengthPrefs,
                strengthSessions: strengthSessions,
                cuesEnabled: cuesEnabled,
                freezeMileage: freezeMileage,
                pendingVDOT: pendingSuggestion?.newVDOT,
                pendingVDOTReason: pendingSuggestion?.reason,
                results: results
            ),
            to: context
        )
    }

    private func installMirrorHandler() {
        HKHealthStore().workoutSessionMirroringStartHandler = { [weak self] mirrored in
            Task { @MainActor in
                await self?.session.attachMirrored(session: mirrored)
            }
        }
    }
}
