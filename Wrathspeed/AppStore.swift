import Foundation
import SwiftData
import WrathspeedCore

@MainActor
@Observable
final class AppStore {
    private static let initialState = PersistedState.initial

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
    var toastMessage: String?
    var celebration: CelebrationPayload?
    var selectedTab: AppTab = .today

    private let workoutCoordinator = WorkoutSessionCoordinator()
    private let strengthCatalogLoader: () throws -> StrengthCatalog
    private var repository: AppStateRepository?
    private var didAttach = false
    private var toastTask: Task<Void, Never>?

    var unit: DistanceUnit { profile?.unit ?? DistanceUnit.default() }

    init(strengthCatalogLoader: @escaping () throws -> StrengthCatalog = { try StrengthCatalogLoader.load() }) {
        self.strengthCatalogLoader = strengthCatalogLoader
    }

    var zones: PaceZones? {
        guard let vdot = profile?.vdot else { return nil }
        return PaceCalculator.zones(vdot: vdot)
    }

    var session: WorkoutSessionController { workoutCoordinator.session }

    var todaysRuns: [ScheduledWorkout] {
        guard let plan else { return [] }
        return plan.workouts.filter {
            Calendar.current.isDateInToday($0.date) && ($0.status == .scheduled || $0.status == .convertedToEasy)
        }
    }

    var todaysCompletedRuns: [ScheduledWorkout] {
        guard let plan else { return [] }
        return plan.workouts.filter {
            Calendar.current.isDateInToday($0.date) && $0.status == .completed
        }
    }

    var todaysStrength: [StrengthSession] {
        strengthSessions.filter { Calendar.current.isDateInToday($0.date) }
    }

    var upcomingRuns: [ScheduledWorkout] {
        guard let plan else { return [] }
        return plan.workouts
            .filter { ($0.status == .scheduled || $0.status == .convertedToEasy) && $0.date >= Calendar.current.startOfDay(for: Date()) }
            .sorted { $0.date < $1.date }
    }

    var streak: Int { streakCount() }

    func attach(context: ModelContext, resetStore: Bool = UITestingSupport.shouldResetStore) {
        repository = AppStateRepository(context: context)
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
        let goal = goal ?? plan?.goal ?? TrainingGoal(kind: .fiveK)
        var calendar = Calendar.current
        calendar.timeZone = .current
        let request = PlanRequest(goal: goal, profile: profile, startDate: Date(), calendar: calendar)
        do {
            let catalog = try strengthCatalogLoader()
            let generated = try TrainingPlanService.regenerate(
                request: request,
                existingPlan: plan,
                adjustment: n100,
                freezeMileageBaselineMeters: freezeMileage ? freezeMileageBaselineMeters : nil,
                strengthPreferences: strengthPrefs,
                strengthCatalog: catalog
            )
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
        updateWorkout(workout.id) { AdaptationRules.applySkip($0, convertQualityToEasy: convertQuality) }
        evaluateAdaptation()
        showToast(convertQuality ? "CONVERTED TO EASY" : "SESSION SKIPPED")
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
        showToast("MOVED +1 DAY")
    }

    func applyNotFeeling100(_ adjustment: N100Adjustment) {
        n100 = adjustment
        if var plan {
            plan.workouts = NotFeeling100Rules.apply(workouts: plan.workouts, adjustment: adjustment, calendar: .current)
            self.plan = plan
        }
        persist()
        pushWatchWorkouts()
        showToast("PLAN ADJUSTED FOR \(adjustment.dayCount) DAYS · RETURN: \(adjustment.returnPace.title.uppercased())")
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

    func record(_ result: WorkoutResult) {
        if results.contains(where: { existing in
            if let uuid = result.healthKitUUID, uuid == existing.healthKitUUID { return true }
            return existing.workoutID == result.workoutID && existing.startedAt == result.startedAt
        }) { return }
        let previousVDOT = profile?.vdot
        results.insert(result, at: 0)
        updateWorkout(result.workoutID) { workout in
            var copy = workout
            copy.status = .completed
            copy.result = result
            return copy
        }
        evaluateAdaptation()
        persist()
        celebration = makeCelebration(for: result, previousVDOT: previousVDOT)
    }

    func start(_ blueprint: WorkoutBlueprint) async {
        do {
            session.splitUnit = unit
            session.cueStyle = cueStyle
            try await workoutCoordinator.start(
                blueprint: blueprint,
                vdot: profile?.vdot,
                zones: zones,
                cuesEnabled: cuesEnabled
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startInstant(kind: WorkoutKind, location: RunLocation) async {
        let blueprint = InstantWorkoutFactory.make(kind: kind, location: location, date: Date())
        await start(blueprint)
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
              let zone = targetZone(for: workout.blueprint.kind),
              let target = zones?.secondsPerKilometer(for: zone)
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
        guard let plan else { return [] }
        let groups = Dictionary(grouping: plan.workouts) {
            Calendar.current.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date
        }
        return groups.keys.sorted().map { (start: $0, workouts: groups[$0]!.sorted { $0.date < $1.date }) }
    }

    func currentWeekIndex() -> (current: Int, total: Int) {
        guard let plan else { return (1, 1) }
        let groups = weekGroups()
        let today = Date()
        let index = groups.firstIndex { week in
            let end = Calendar.current.date(byAdding: .day, value: 7, to: week.start) ?? week.start
            return today >= week.start && today < end
        } ?? 0
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
        if let vdot = state.pendingVDOT, let reason = state.pendingVDOTReason {
            pendingSuggestion = VDOTSuggestion(newVDOT: vdot, reason: reason)
        } else {
            pendingSuggestion = nil
        }
    }

    private func finishAttach() {
        workoutCoordinator.configure(cuesEnabled: cuesEnabled, zones: zones, onResult: { [weak self] result in
            self?.record(result)
        }, onFailure: { [weak self] error in
            self?.errorMessage = "Workout wasn't saved to Health: \(error.localizedDescription)"
        })
        workoutCoordinator.installMirroringHandler()
        pushWatchWorkouts()
        if let result = workoutCoordinator.consumeLatestResult() {
            record(result)
        }
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
        if decision.freezeMileageIncrease && !freezeMileage {
            freezeMileageBaselineMeters = currentWeekMileage(in: plan, calendar: cal)
        }
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

    private func currentWeekMileage(in plan: TrainingPlan, calendar: Calendar) -> Double {
        let interval = calendar.dateInterval(of: .weekOfYear, for: Date())
        return plan.workouts.filter { workout in
            workout.status == .scheduled && workout.blueprint.kind.isRunning && workout.blueprint.kind != .race
                && (interval?.contains(workout.date) ?? false)
        }.reduce(0) { $0 + $1.blueprint.plannedDistanceMeters }
    }

    private func weekMileage(completed: Bool) -> (done: Double, planned: Double) {
        guard let plan else { return (0, 0) }
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date())
        let week = plan.workouts.filter {
            $0.blueprint.kind.isRunning && (interval?.contains($0.date) ?? false)
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

    private func targetZone(for kind: WorkoutKind) -> PaceZone? {
        switch kind {
        case .easy, .longRun, .freeRun: .easy
        case .tempo: .threshold
        case .intervals: .interval
        case .race: .marathon
        default: nil
        }
    }

    private func pushWatchWorkouts() {
        let upcoming = upcomingRuns.prefix(14).map(\.blueprint)
        workoutCoordinator.pushUpcoming(UpcomingWorkoutsPayload(blueprints: Array(upcoming), vdot: profile?.vdot))
    }

    func save() {
        persist()
    }

    private func persist() {
        guard let repository else { return }
        do {
            try repository.save(
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
                    cueStyle: cueStyle
                )
            )
        } catch {
            errorMessage = "Couldn’t save training data: \(error.localizedDescription)"
        }
    }
}
