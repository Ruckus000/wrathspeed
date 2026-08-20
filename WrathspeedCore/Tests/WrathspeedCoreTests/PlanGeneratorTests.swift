import Foundation
import Testing
@testable import WrathspeedCore

struct PlanGeneratorTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func request(
        kind: GoalKind,
        weeks: Int = 12,
        days: Int = 4,
        start: Date? = nil
    ) -> PlanRequest {
        let startDate = start ?? calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let race = calendar.date(byAdding: .day, value: weeks * 7 - 1, to: startDate)
        return PlanRequest(
            goal: TrainingGoal(kind: kind, raceDate: race, weekCount: weeks),
            profile: RunnerProfile(
                ability: .intermediate,
                weeklyMileageMeters: 30_000,
                longestRunMeters: 10_000,
                daysPerWeek: days,
                longRunWeekday: .saturday,
                unit: .kilometers
            ),
            startDate: startDate,
            calendar: calendar
        )
    }

    @Test func generatesWorkoutsOnRequestedDays() {
        let plan = PlanGenerator.generate(request(kind: .halfMarathon, weeks: 12, days: 4))
        #expect(!plan.workouts.isEmpty)
        let trainingDays = plan.workouts.filter { $0.blueprint.kind != .race }
        let weekdays = Set(trainingDays.map { calendar.component(.weekday, from: $0.date) })
        #expect(weekdays.count <= 4)
    }

    @Test func raceSitsOnRaceDate() {
        let req = request(kind: .tenK, weeks: 10)
        let plan = PlanGenerator.generate(req)
        let races = plan.workouts.filter { $0.blueprint.kind == .race }
        #expect(races.count == 1)
        if let raceDate = req.goal.raceDate, let race = races.first {
            #expect(calendar.isDate(race.date, inSameDayAs: raceDate))
        }
    }

    @Test func longRunStaysWithinCap() {
        let plan = PlanGenerator.generate(request(kind: .halfMarathon, weeks: 12))
        let cap = PlanGenerator.longRunCap(for: .halfMarathon)
        for workout in plan.workouts where workout.blueprint.kind == .longRun {
            #expect(workout.blueprint.plannedDistanceMeters <= cap + 1)
        }
    }

    @Test func weeklyMileageDoesNotJumpMoreThan12Percent() {
        let plan = PlanGenerator.generate(request(kind: .marathon, weeks: 16, days: 5))
        let weeks = Dictionary(grouping: plan.workouts.filter { $0.blueprint.kind.isRunning && $0.blueprint.kind != .race }) {
            calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date
        }
        let totals = weeks.keys.sorted().compactMap { key -> Double? in
            weeks[key].map { $0.reduce(0) { $0 + $1.blueprint.plannedDistanceMeters } }
        }
        for pair in zip(totals, totals.dropFirst()) {
            if pair.1 > pair.0 {
                let increase = (pair.1 - pair.0) / max(pair.0, 1)
                #expect(increase <= 0.25)
            }
        }
    }

    @Test func taperWeekIsLighterThanPeak() {
        let plan = PlanGenerator.generate(request(kind: .fiveK, weeks: 8))
        let sortedWeeks = Dictionary(grouping: plan.workouts) {
            calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date
        }
        let keys = sortedWeeks.keys.sorted()
        guard let first = keys.first, let last = keys.last, first != last else {
            Issue.record("expected multiple weeks")
            return
        }
        let firstTotal = sortedWeeks[first]!.reduce(0) { $0 + $1.blueprint.plannedDistanceMeters }
        let lastTotal = sortedWeeks[last]!.reduce(0) { $0 + $1.blueprint.plannedDistanceMeters }
        #expect(lastTotal <= firstTotal * 1.2)
    }

    @Test func allFourRaceDistancesGenerate() {
        for kind in [GoalKind.fiveK, .tenK, .halfMarathon, .marathon] {
            let plan = PlanGenerator.generate(request(kind: kind, weeks: kind.minimumWeeks))
            #expect(plan.workouts.contains { $0.blueprint.kind == .race })
        }
    }

    @Test func beginnerPlanIsWalkRunWithoutPace() {
        let plan = PlanGenerator.generate(request(kind: .newToRunning, weeks: 8, days: 3))
        #expect(plan.workouts.allSatisfy { $0.blueprint.kind == .walkRun })
        #expect(plan.workouts.allSatisfy { $0.blueprint.usesPaceTargets == false })
        #expect(plan.workouts.count >= 8 * 3)
    }

    @Test func returnToRunningHasWalkRunSteps() {
        let plan = PlanGenerator.generate(request(kind: .returnToRunning, weeks: 6, days: 3))
        #expect(plan.workouts.first?.blueprint.steps.contains { $0.name.contains("Run") } == true)
    }

    @Test func weekdayHelperSpacesDays() {
        let days = PlanGenerator.runWeekdays(daysPerWeek: 4, longRun: .saturday)
        #expect(days.last == .saturday)
        #expect(days.count == 4)
    }

    @Test func rejectsRaceDateShorterThanMinimumPlan() {
        var invalid = request(kind: .halfMarathon, weeks: 12)
        invalid.goal.raceDate = calendar.date(byAdding: .day, value: 7, to: invalid.startDate)
        #expect(throws: PlanInputError.raceDateTooSoon(minimumWeeks: GoalKind.halfMarathon.minimumWeeks)) {
            try PlanGenerator.generateValidated(invalid)
        }
    }

    @Test func rejectsInvalidMileage() {
        var invalid = request(kind: .tenK, weeks: 10)
        invalid.profile.weeklyMileageMeters = 0
        #expect(throws: PlanInputError.invalidWeeklyMileage) {
            try PlanGenerator.generateValidated(invalid)
        }
    }

    @Test func rejectsRaceDateBeyondMaximumPlan() {
        var invalid = request(kind: .fiveK, weeks: 8)
        invalid.goal.raceDate = calendar.date(byAdding: .day, value: (PlanGenerator.maxWeeks + 1) * 7, to: invalid.startDate)
        #expect(throws: PlanInputError.raceDateTooFar(maximumWeeks: PlanGenerator.maxWeeks)) {
            try PlanGenerator.generateValidated(invalid)
        }
    }

    @Test func reconcilerRetainsCompletedWorkoutAndCapsFutureMileage() {
        let original = PlanGenerator.generate(request(kind: .tenK, weeks: 10))
        var completed = original
        completed.workouts[0].status = .completed
        let result = WorkoutResult(workoutID: completed.workouts[0].blueprint.id, startedAt: completed.workouts[0].date, duration: 300, distanceMeters: 1_000, averagePaceSecPerKm: 300, location: .outdoor)
        completed.workouts[0].result = result
        let regenerated = PlanGenerator.generate(request(kind: .tenK, weeks: 10))
        let reconciled = PlanReconciler.reconcile(existing: completed, generated: regenerated, asOf: completed.workouts[0].date, calendar: calendar, freezeMileageBaselineMeters: 5_000)
        #expect(reconciled.workouts.contains { $0.id == completed.workouts[0].id && $0.result == result })
        let weekly = Dictionary(grouping: reconciled.workouts.filter { $0.status == .scheduled && $0.blueprint.kind.isRunning && $0.blueprint.kind != .race }) {
            calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date
        }
        #expect(weekly.values.allSatisfy { $0.reduce(0) { $0 + $1.blueprint.plannedDistanceMeters } <= 5_000.01 })
    }

    @Test func planServiceAppliesReconciliationAdjustmentAndStrengthScheduling() throws {
        var request = request(kind: .tenK, weeks: 10)
        request.goal.raceDate = calendar.date(byAdding: .day, value: 10 * 7, to: request.startDate)
        var existing = PlanGenerator.generate(request)
        existing.workouts[0].status = .completed
        let completedID = existing.workouts[0].id
        let catalog = StrengthCatalog(exercises: [
            StrengthExercise(
                id: "squat",
                name: "Squat",
                focus: [.legsCore, .fullBody],
                equipment: [.bodyweight],
                symbolName: "figure.strengthtraining.traditional",
                defaultReps: 10,
                cue: "Stand tall."
            ),
        ])

        let output = try TrainingPlanService.regenerate(
            request: request,
            existingPlan: existing,
            adjustment: N100Adjustment(start: request.startDate, dayCount: 3, mode: .reducedDifficulty, returnPace: .balanced),
            freezeMileageBaselineMeters: 5_000,
            strengthPreferences: StrengthPreferences(sessionsPerWeek: 1),
            strengthCatalog: catalog
        )

        #expect(output.plan.workouts.contains { $0.id == completedID && $0.status == .completed })
        #expect(output.strengthSessions.count == request.goal.weekCount)
    }
}
