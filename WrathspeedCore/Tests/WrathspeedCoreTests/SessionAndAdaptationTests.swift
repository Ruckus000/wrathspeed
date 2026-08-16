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
            events: [],
            splitUnit: .kilometers
        )
        #expect(cues.contains { if case .split(1, .kilometers, _) = $0 { return true }; return false })
    }

    @Test func announcesFirstAndSubsequentKilometerSplits() {
        var policy = CuePolicy()
        let first = policy.evaluate(
            step: step(),
            usesPaceTargets: false,
            zones: nil,
            metrics: LiveMetrics(elapsed: 360, distanceMeters: 1_000, currentPaceSecPerKm: 360),
            events: [],
            splitUnit: .kilometers
        )
        #expect(first.contains { if case .split(1, .kilometers, _) = $0 { return true }; return false })

        let second = policy.evaluate(
            step: step(),
            usesPaceTargets: false,
            zones: nil,
            metrics: LiveMetrics(elapsed: 720, distanceMeters: 2_000, currentPaceSecPerKm: 365),
            events: [],
            splitUnit: .kilometers
        )
        #expect(second.contains { if case .split(2, .kilometers, _) = $0 { return true }; return false })
    }

    @Test func announcesFirstAndSubsequentMileSplits() {
        var policy = CuePolicy()
        let mile = Units.metersPerMile
        let first = policy.evaluate(
            step: step(),
            usesPaceTargets: false,
            zones: nil,
            metrics: LiveMetrics(elapsed: 600, distanceMeters: mile, currentPaceSecPerKm: 390),
            events: [],
            splitUnit: .miles
        )
        #expect(first.contains { if case .split(1, .miles, _) = $0 { return true }; return false })

        let second = policy.evaluate(
            step: step(),
            usesPaceTargets: false,
            zones: nil,
            metrics: LiveMetrics(elapsed: 1_200, distanceMeters: mile * 2, currentPaceSecPerKm: 395),
            events: [],
            splitUnit: .miles
        )
        #expect(second.contains { if case .split(2, .miles, _) = $0 { return true }; return false })
    }

    @Test func doesNotDuplicateSplitWithinSameBoundary() {
        var policy = CuePolicy()
        _ = policy.evaluate(
            step: step(),
            usesPaceTargets: false,
            zones: nil,
            metrics: LiveMetrics(elapsed: 360, distanceMeters: 1_050, currentPaceSecPerKm: 360),
            events: [],
            splitUnit: .kilometers
        )
        let repeatCue = policy.evaluate(
            step: step(),
            usesPaceTargets: false,
            zones: nil,
            metrics: LiveMetrics(elapsed: 370, distanceMeters: 1_080, currentPaceSecPerKm: 360),
            events: [],
            splitUnit: .kilometers
        )
        #expect(!repeatCue.contains { if case .split = $0 { return true }; return false })
    }

    @Test func announcesMultipleBoundariesCrossedBetweenSamples() {
        var policy = CuePolicy()
        let cues = policy.evaluate(
            step: step(),
            usesPaceTargets: false,
            zones: nil,
            metrics: LiveMetrics(elapsed: 900, distanceMeters: 2_100, currentPaceSecPerKm: 360),
            events: [],
            splitUnit: .kilometers
        )
        let splitIndices = cues.compactMap { cue -> Int? in
            if case .split(let index, .kilometers, _) = cue { return index }
            return nil
        }
        #expect(splitIndices == [1, 2])
    }

    @Test func legacyDefaultUnitUsesKilometers() {
        var policy = CuePolicy()
        let cues = policy.evaluate(
            step: step(),
            usesPaceTargets: false,
            zones: nil,
            metrics: LiveMetrics(elapsed: 360, distanceMeters: 1_000, currentPaceSecPerKm: 360),
            events: []
        )
        #expect(cues.contains { if case .split(1, .kilometers, _) = $0 { return true }; return false })
    }

    @Test func retainsBoundaryWhenPaceUnavailable() {
        var policy = CuePolicy()
        let withoutPace = policy.evaluate(
            step: step(),
            usesPaceTargets: false,
            zones: nil,
            metrics: LiveMetrics(elapsed: 360, distanceMeters: 1_000, currentPaceSecPerKm: nil),
            events: [],
            splitUnit: .kilometers
        )
        #expect(!withoutPace.contains { if case .split = $0 { return true }; return false })

        let withPace = policy.evaluate(
            step: step(),
            usesPaceTargets: false,
            zones: nil,
            metrics: LiveMetrics(elapsed: 370, distanceMeters: 1_020, currentPaceSecPerKm: 360),
            events: [],
            splitUnit: .kilometers
        )
        #expect(withPace.contains { if case .split(1, .kilometers, _) = $0 { return true }; return false })
    }

    @Test func cueAndSplitBuilderShareKilometerToleranceBoundaries() {
        cueAndSplitBuilderStayAligned(unit: .kilometers, unitMeters: Units.metersPerKilometer)
    }

    @Test func cueAndSplitBuilderShareMileToleranceBoundaries() {
        cueAndSplitBuilderStayAligned(unit: .miles, unitMeters: Units.metersPerMile)
    }

    private func cueAndSplitBuilderStayAligned(unit: DistanceUnit, unitMeters: Double) {
        let threshold = unitMeters * SplitBoundary.tolerance
        let samples: [Double] = [
            threshold - 1,
            threshold,
            unitMeters,
            unitMeters + threshold - 1,
            unitMeters + threshold,
            unitMeters * 2,
        ]

        var policy = CuePolicy()
        var splitState = (count: 0, distance: 0.0, elapsed: 0.0)
        var announced: [Int] = []
        var recorded: [Int] = []

        for (offset, distance) in samples.enumerated() {
            let elapsed = TimeInterval(offset + 1) * 300
            let pace = 360.0
            let cues = policy.evaluate(
                step: step(),
                usesPaceTargets: false,
                zones: nil,
                metrics: LiveMetrics(elapsed: elapsed, distanceMeters: distance, currentPaceSecPerKm: pace),
                events: [],
                splitUnit: unit
            )
            announced.append(contentsOf: cues.compactMap { cue in
                if case .split(let index, _, _) = cue { return index }
                return nil
            })

            let captured = SplitBuilder.nextSplits(
                previousCount: splitState.count,
                previousDistance: splitState.distance,
                previousElapsed: splitState.elapsed,
                currentDistance: distance,
                currentElapsed: elapsed,
                unit: unit
            )
            recorded.append(contentsOf: captured.splits.map(\.index))
            splitState = (splitState.count + captured.splits.count, captured.distance, captured.elapsed)
        }

        #expect(announced == recorded)
        #expect(announced == [1, 2])
    }
}

struct SplitBuilderFromRouteTests {
    @Test func sparseSegmentCrossingTwoKilometerBoundariesEmitsConsecutiveSplits() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 1_600)
        let points = [
            RoutePoint(latitude: 0, longitude: 0, timestamp: start),
            RoutePoint(latitude: 0.025, longitude: 0, timestamp: end),
        ]
        let splits = SplitBuilder.fromRoute(points, unit: .kilometers)
        #expect(splits.map(\.index) == [1, 2])
        #expect(splits.count == 2)
        #expect(splits.allSatisfy { $0.duration > 0 })
        let allocated = splits.reduce(0.0) { $0 + $1.duration }
        let segmentElapsed = end.timeIntervalSince(start)
        #expect(allocated <= segmentElapsed)
        #expect(splits[0].duration + splits[1].duration == allocated)
    }
}

struct CueStyleSplitPhraseTests {
    @Test func singularAndPluralKilometerPhrases() {
        #expect(CueStyle.standard.phrase(for: .split(index: 1, unit: .kilometers, paceSecPerKm: 360)) == "Kilometer 1.")
        #expect(CueStyle.standard.phrase(for: .split(index: 2, unit: .kilometers, paceSecPerKm: 360)) == "Kilometers 2.")
    }

    @Test func singularAndPluralMilePhrases() {
        #expect(CueStyle.standard.phrase(for: .split(index: 1, unit: .miles, paceSecPerKm: 390)) == "Mile 1.")
        #expect(CueStyle.standard.phrase(for: .split(index: 2, unit: .miles, paceSecPerKm: 390)) == "Miles 2.")
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
