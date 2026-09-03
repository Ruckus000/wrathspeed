import XCTest
@testable import WrathspeedCore

/// The deterministic inputs behind the coach's quick actions. A button supplies its parameter
/// from these; the model is never in the loop for a button.
final class CoachQuickActionsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let vdot = 45.0
    private var zones: PaceZones { PaceCalculator.zones(vdot: vdot) }
    private var start: Date { calendar.date(from: DateComponents(year: 2026, month: 8, day: 2))! }   // a Sunday
    private var asOf: Date { calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))! }  // four weeks in

    private func profile(days: Int = 5, longRun: Weekday = .sunday, available: [Weekday]? = nil) -> RunnerProfile {
        RunnerProfile(ability: .intermediate, daysPerWeek: days, longRunWeekday: longRun, unit: .kilometers, vdot: vdot, availableWeekdays: available)
    }

    private func plan(_ profile: RunnerProfile) -> TrainingPlan {
        PlanGenerator.generate(PlanRequest(goal: TrainingGoal(kind: .tenK), profile: profile, startDate: start, calendar: calendar))
    }

    /// Completes a run at `factor` times its target pace (0.95 = 5% faster).
    private func complete(_ plan: inout TrainingPlan, index: Int, paceFactor: Double) {
        let workout = plan.workouts[index]
        let target = WorkoutPaceTarget.targetPaceSecPerKm(blueprint: workout.blueprint, zones: zones)!
        let distance = workout.blueprint.plannedDistanceMeters
        plan.workouts[index].status = .completed
        plan.workouts[index].result = WorkoutResult(
            workoutID: workout.id, startedAt: workout.date, duration: distance / 1000 * target * paceFactor,
            distanceMeters: distance, averagePaceSecPerKm: target * paceFactor, location: .outdoor
        )
    }

    private func pastRunIndices(in plan: TrainingPlan) -> [Int] {
        plan.workouts.indices.filter { plan.workouts[$0].blueprint.kind.isRunning && plan.workouts[$0].date < asOf }.sorted { plan.workouts[$0].date > plan.workouts[$1].date }
    }

    // MARK: long run weekday

    func testLongRunOptionsExcludeTheCurrentDayAndUnavailableDays() {
        XCTAssertEqual(CoachQuickActions.longRunWeekdayOptions(profile: profile(days: 3, longRun: .saturday)), [.tuesday, .thursday])
        XCTAssertEqual(CoachQuickActions.longRunWeekdayOptions(profile: profile(days: 3, longRun: .saturday, available: [.monday, .wednesday, .saturday])), [.monday, .wednesday])
    }

    // MARK: indoor workout

    func testIndoorOptionsAreUpcomingOutdoorRunsInDateOrderWithinTwoWeeks() throws {
        var plan = plan(profile())
        let upcoming = plan.workouts.indices.filter { plan.workouts[$0].blueprint.kind.isRunning && plan.workouts[$0].date >= asOf }
        plan.workouts[upcoming[0]].blueprint.location = .treadmill        // already indoors
        plan.workouts[upcoming[1]].status = .completed                    // not unstarted
        let options = CoachQuickActions.indoorWorkoutOptions(plan: plan, asOf: asOf, calendar: calendar)
        XCTAssertFalse(options.isEmpty)
        XCTAssertFalse(options.contains { $0.id == plan.workouts[upcoming[0]].id }, "a treadmill run is not an option")
        XCTAssertFalse(options.contains { $0.id == plan.workouts[upcoming[1]].id }, "a completed run is not an option")
        XCTAssertTrue(options.allSatisfy { $0.blueprint.kind.isRunning && $0.blueprint.location != .treadmill })
        let limit = calendar.date(byAdding: .day, value: 14, to: asOf)!
        XCTAssertTrue(options.allSatisfy { $0.date >= asOf && $0.date < limit })
        XCTAssertEqual(options.map(\.date), options.map(\.date).sorted())
        XCTAssertTrue(CoachQuickActions.indoorWorkoutOptions(plan: plan, asOf: calendar.date(byAdding: .year, value: 1, to: asOf)!, calendar: calendar).isEmpty)
    }

    // MARK: faster paces evidence

    func testFasterPacesNeedsThreeRecentRunsAtLeastThreePercentFasterThanTarget() throws {
        let profile = profile()
        var plan = plan(profile)
        let past = pastRunIndices(in: plan)
        XCTAssertGreaterThanOrEqual(past.count, 4)

        XCTAssertEqual(CoachQuickActions.fasterPacesVerdict(plan: plan, profile: profile, zones: zones, asOf: asOf, calendar: calendar), .fewerThanThreeRuns(0))

        complete(&plan, index: past[0], paceFactor: 0.95)
        complete(&plan, index: past[1], paceFactor: 0.95)
        XCTAssertEqual(CoachQuickActions.fasterPacesVerdict(plan: plan, profile: profile, zones: zones, asOf: asOf, calendar: calendar), .fewerThanThreeRuns(2))

        complete(&plan, index: past[2], paceFactor: 0.95)
        guard case let .evidence(evidence) = CoachQuickActions.fasterPacesVerdict(plan: plan, profile: profile, zones: zones, asOf: asOf, calendar: calendar) else {
            return XCTFail("three runs 5% faster than target are evidence")
        }
        XCTAssertEqual(evidence.runs.count, 3)
        XCTAssertEqual(evidence.meanDeltaFraction, -0.05, accuracy: 0.001)
        XCTAssertEqual(evidence.suggestedVDOT, vdot * (1 + CoachPlanRules.vdotChangeLimit), accuracy: 0.0001)

        // The most recent three are what count: a slow fourth run further back changes nothing,
        // a slow run in the last three does.
        complete(&plan, index: past[3], paceFactor: 1.20)
        if case .evidence = CoachQuickActions.fasterPacesVerdict(plan: plan, profile: profile, zones: zones, asOf: asOf, calendar: calendar) {} else {
            XCTFail("a fourth, older run is outside the window")
        }
        complete(&plan, index: past[0], paceFactor: 1.10)
        guard case let .notFasterThanTarget(mean) = CoachQuickActions.fasterPacesVerdict(plan: plan, profile: profile, zones: zones, asOf: asOf, calendar: calendar) else {
            return XCTFail("two fast and one slow run average to no evidence")
        }
        XCTAssertEqual(mean, 0, accuracy: 0.001)
    }

    func testFasterPacesJustUnderTheBarIsNotEvidence() {
        let profile = profile()
        var plan = plan(profile)
        for index in pastRunIndices(in: plan).prefix(3) { complete(&plan, index: index, paceFactor: 0.98) }
        guard case .notFasterThanTarget = CoachQuickActions.fasterPacesVerdict(plan: plan, profile: profile, zones: zones, asOf: asOf, calendar: calendar) else {
            return XCTFail("2% faster is under the 3% bar")
        }
    }
}
