import Foundation
import Testing
@testable import WrathspeedCore

struct WorkoutStepperTests {
    @Test func advancesOnDistance() {
        let steps = [
            WorkoutStep(name: "A", target: .distance(meters: 1_000), intensity: .zone(.easy)),
            WorkoutStep(name: "B", target: .distance(meters: 1_000), intensity: .zone(.easy)),
        ]
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .easy,
            title: "Test",
            steps: steps,
            plannedDistanceMeters: 2_000,
            usesPaceTargets: true
        )
        var stepper = WorkoutStepper(blueprint: blueprint)
        let start = stepper.update(metrics: LiveMetrics(elapsed: 0, distanceMeters: 0))
        #expect(start.contains { if case .started(0, _) = $0 { return true }; return false })
        let mid = stepper.update(metrics: LiveMetrics(elapsed: 300, distanceMeters: 1_000))
        #expect(mid.contains { if case .completed(0, _) = $0 { return true }; return false })
        #expect(stepper.stepIndex == 1)
        let end = stepper.update(metrics: LiveMetrics(elapsed: 600, distanceMeters: 2_000))
        #expect(end.contains(.finished))
        #expect(stepper.isComplete)
    }

    @Test func advancesOnDuration() {
        let steps = [WorkoutStep(name: "Run", target: .duration(seconds: 60), intensity: .rpe(5))]
        let blueprint = WorkoutBlueprint(
            date: Date(),
            kind: .walkRun,
            title: "Test",
            steps: steps,
            plannedDistanceMeters: 0,
            usesPaceTargets: false
        )
        var stepper = WorkoutStepper(blueprint: blueprint)
        _ = stepper.update(metrics: LiveMetrics(elapsed: 0, distanceMeters: 0))
        let done = stepper.update(metrics: LiveMetrics(elapsed: 60, distanceMeters: 200))
        #expect(done.contains(.finished))
    }
}

struct CuePolicyTests {
    func step(_ zone: PaceZone = .easy) -> WorkoutStep {
        WorkoutStep(name: "Easy", target: .distance(meters: 5_000), intensity: .zone(zone))
    }

    @Test func noCueInsideBand() {
        var policy = CuePolicy()
        let zones = PaceCalculator.zones(vdot: 50)
        let target = zones.secondsPerKilometer(for: .easy) ?? 360
        let cues = policy.evaluate(
            step: step(),
            usesPaceTargets: true,
            zones: zones,
            metrics: LiveMetrics(elapsed: 30, distanceMeters: 100, currentPaceSecPerKm: target),
            events: []
        )
        #expect(!cues.contains(.speedUp))
        #expect(!cues.contains(.slowDown))
    }

    @Test func slowDownWhenTooFastAfterHold() {
        var policy = CuePolicy(offTargetHold: 20, silenceAfterCue: 60)
        let zones = PaceCalculator.zones(vdot: 50)
        let target = zones.secondsPerKilometer(for: .easy) ?? 360
        _ = policy.evaluate(
            step: step(),
            usesPaceTargets: true,
            zones: zones,
            metrics: LiveMetrics(elapsed: 0, distanceMeters: 0, currentPaceSecPerKm: target * 0.8),
            events: []
        )
        let cues = policy.evaluate(
            step: step(),
            usesPaceTargets: true,
            zones: zones,
            metrics: LiveMetrics(elapsed: 21, distanceMeters: 200, currentPaceSecPerKm: target * 0.8),
            events: []
        )
        #expect(cues.contains(.slowDown))
        #expect(!cues.contains(.speedUp))
    }

    @Test func doesNotStormCues() {
        var policy = CuePolicy(offTargetHold: 5, silenceAfterCue: 60)
        let zones = PaceCalculator.zones(vdot: 50)
        let target = zones.secondsPerKilometer(for: .easy) ?? 360
        var slowDowns = 0
        for elapsed in stride(from: 0, through: 40, by: 5) {
            let cues = policy.evaluate(
                step: step(),
                usesPaceTargets: true,
                zones: zones,
                metrics: LiveMetrics(elapsed: TimeInterval(elapsed), distanceMeters: Double(elapsed) * 10, currentPaceSecPerKm: target * 0.8),
                events: []
            )
            if cues.contains(.slowDown) { slowDowns += 1 }
        }
        #expect(slowDowns == 1)
    }

    @Test func announcesKilometerSplits() {
        var policy = CuePolicy()
        let cues = policy.evaluate(
            step: step(),
            usesPaceTargets: false,
            zones: nil,
            metrics: LiveMetrics(elapsed: 360, distanceMeters: 1_000, currentPaceSecPerKm: 360),
            events: []
        )
        #expect(cues.contains { if case .split(1, _) = $0 { return true }; return false })
    }
}

struct AdaptationTests {
    @Test func freezeAfterTwoSkips() {
        let decision = AdaptationRules.evaluate(skippedThisWeek: 2, qualitySessions: [], currentVDOT: 50)
        #expect(decision.freezeMileageIncrease)
        #expect(decision.vdotSuggestion == nil)
    }

    @Test func suggestsHigherVDOTWhenFaster() {
        let sessions = (0..<3).map { _ in
            QualitySession(targetPaceSecPerKm: 300, actualPaceSecPerKm: 270)
        }
        let decision = AdaptationRules.evaluate(skippedThisWeek: 0, qualitySessions: sessions, currentVDOT: 50)
        #expect(decision.vdotSuggestion != nil)
        #expect((decision.vdotSuggestion?.newVDOT ?? 0) > 50)
    }

    @Test func suggestsLowerVDOTWhenSlower() {
        let sessions = (0..<3).map { _ in
            QualitySession(targetPaceSecPerKm: 300, actualPaceSecPerKm: 330)
        }
        let decision = AdaptationRules.evaluate(skippedThisWeek: 0, qualitySessions: sessions, currentVDOT: 50)
        #expect((decision.vdotSuggestion?.newVDOT ?? 100) < 50)
    }

    @Test func longRunMoveWindow() {
        let from = Date(timeIntervalSince1970: 0)
        #expect(AdaptationRules.canMoveLongRun(from: from, to: from.addingTimeInterval(48 * 3600)))
        #expect(!AdaptationRules.canMoveLongRun(from: from, to: from.addingTimeInterval(49 * 3600)))
    }
}

struct NotFeeling100Tests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func dayCountClamped() {
        #expect(NotFeeling100Rules.isValidDayCount(3))
        #expect(NotFeeling100Rules.isValidDayCount(14))
        #expect(!NotFeeling100Rules.isValidDayCount(2))
    }

    @Test func pauseSkipsRunning() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let workout = ScheduledWorkout(
            blueprint: WorkoutBuilder.easyRun(date: start, meters: 5_000, location: .outdoor)
        )
        let adjusted = NotFeeling100Rules.apply(
            workouts: [workout],
            adjustment: N100Adjustment(start: start, dayCount: 5, mode: .pause, returnPace: .balanced),
            calendar: calendar
        )
        #expect(adjusted.first?.status == .skipped)
    }

    @Test func reducedDifficultyConvertsQuality() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let quality = ScheduledWorkout(
            blueprint: WorkoutBuilder.intervals(date: start, kind: .fiveK, phase: .build, location: .outdoor)
        )
        let adjusted = NotFeeling100Rules.apply(
            workouts: [quality],
            adjustment: N100Adjustment(start: start, dayCount: 7, mode: .reducedDifficulty, returnPace: .slow),
            calendar: calendar
        )
        #expect(adjusted.first?.blueprint.kind == .easy)
    }

    @Test func strengthUnchanged() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let strength = ScheduledWorkout(
            blueprint: WorkoutBlueprint(
                date: start,
                kind: .strength,
                title: "Strength",
                steps: [],
                plannedDistanceMeters: 0,
                usesPaceTargets: false
            )
        )
        let adjusted = NotFeeling100Rules.apply(
            workouts: [strength],
            adjustment: N100Adjustment(start: start, dayCount: 7, mode: .pause, returnPace: .quick),
            calendar: calendar
        )
        #expect(adjusted.first?.status == .scheduled)
        #expect(adjusted.first?.blueprint.kind == .strength)
    }
}

struct StrengthPlannerTests {
    private let catalog = StrengthCatalog(exercises: [
        StrengthExercise(
            id: "bodyweight-squat",
            name: "Bodyweight squat",
            focus: [.legsCore, .fullBody],
            equipment: [.bodyweight],
            symbolName: "figure.strengthtraining.traditional",
            defaultReps: 12,
            cue: "Stand tall."
        ),
        StrengthExercise(
            id: "bodyweight-push-up",
            name: "Push-up",
            focus: [.upper, .fullBody],
            equipment: [.bodyweight],
            symbolName: "figure.strengthtraining.traditional",
            defaultReps: 8,
            cue: "Keep a straight line."
        ),
        StrengthExercise(
            id: "dumbbell-row",
            name: "Dumbbell row",
            focus: [.upper, .fullBody],
            equipment: [.dumbbell],
            symbolName: "dumbbell.fill",
            defaultReps: 10,
            cue: "Keep your back flat."
        ),
    ])

    @Test func runningFocusTwoDaysMatchesPublishedGrid() {
        #expect(StrengthPlanner.distribution(goal: .runningFocus, sessionsPerWeek: 2) == [.legsCore, .fullBody])
        #expect(StrengthPlanner.distribution(goal: .allRound, sessionsPerWeek: 3) == [.fullBody, .upper, .legsCore])
    }

    @Test func catalogFiltersEquipment() {
        let prefs = StrengthPreferences(equipment: [.bodyweight])
        let session = StrengthPlanner.makeSession(
            date: Date(),
            focus: .legsCore,
            preferences: prefs,
            catalog: catalog
        )
        #expect(!session.sets.isEmpty)
        #expect(session.sets.allSatisfy { set in
            set.exercise.equipment.contains(.bodyweight) || set.exercise.equipment.contains(where: { prefs.equipment.contains($0) })
        })
    }

    @Test func scheduledStrengthDoesNotChangeRunWorkouts() {
        let prefs = StrengthPreferences(sessionsPerWeek: 2, preferredDays: [.monday, .thursday])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let sessions = StrengthPlanner.schedule(
            preferences: prefs,
            startDate: start,
            weekCount: 4,
            calendar: calendar,
            catalog: catalog
        )
        #expect(sessions.count == 8)
        let asWorkouts = StrengthPlanner.asScheduledWorkouts(sessions)
        #expect(asWorkouts.allSatisfy { $0.blueprint.kind == .strength })
    }
}
