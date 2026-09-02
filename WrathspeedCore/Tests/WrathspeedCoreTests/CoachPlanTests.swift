import XCTest
@testable import WrathspeedCore

final class CoachPlanTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }

    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 4))!
    }

    private func date(_ day: Int) -> Date {
        calendar.date(byAdding: .day, value: day - 4, to: asOf)!
    }

    private func profile(days: [Weekday] = [.monday, .wednesday, .friday, .sunday]) -> RunnerProfile {
        RunnerProfile(
            ability: .intermediate,
            weeklyMileageMeters: 35_000,
            longestRunMeters: 10_000,
            daysPerWeek: max(3, min(6, days.count)),
            longRunWeekday: .sunday,
            unit: .kilometers,
            vdot: 45,
            availableWeekdays: days
        )
    }

    private func workout(
        day: Int,
        kind: WorkoutKind,
        distance: Double = 8_000,
        status: WorkoutStatus = .scheduled,
        location: RunLocation = .outdoor
    ) -> ScheduledWorkout {
        let blueprint = WorkoutBlueprint(
            date: date(day),
            kind: kind,
            title: kind.rawValue,
            location: location,
            steps: [WorkoutStep(name: kind.rawValue, target: .distance(meters: distance), intensity: .zone(kind.isQuality ? .threshold : .easy))],
            plannedDistanceMeters: distance,
            usesPaceTargets: true
        )
        return ScheduledWorkout(blueprint: blueprint, status: status)
    }

    private func plan(
        _ workouts: [ScheduledWorkout],
        profile: RunnerProfile? = nil
    ) -> TrainingPlan {
        TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: profile ?? self.profile(),
            workouts: workouts
        )
    }

    func testSorenessConvertsNextQualityAndScalesLongRun() throws {
        let completed = workout(day: 3, kind: .easy, distance: 5_000, status: .completed)
        let easy = workout(day: 7, kind: .easy, distance: 5_000)
        let quality = workout(day: 9, kind: .tempo, distance: 8_000)
        let longRun = workout(day: 10, kind: .longRun, distance: 12_000)

        let result = try CoachPlanRules.preview(
            intent: .cutIntensity,
            plan: plan([completed, easy, quality, longRun]),
            profile: profile(),
            asOf: asOf,
            calendar: calendar
        )
        let converted = try XCTUnwrap(result.plan.workouts.first { $0.id == quality.id })
        let reduced = try XCTUnwrap(result.plan.workouts.first { $0.id == longRun.id })
        XCTAssertEqual(converted.status, .convertedToEasy)
        XCTAssertEqual(converted.blueprint.id, quality.blueprint.id)
        XCTAssertEqual(converted.blueprint.plannedDistanceMeters, 6_400, accuracy: 0.01)
        XCTAssertEqual(reduced.blueprint.plannedDistanceMeters, 9_600, accuracy: 0.01)
        XCTAssertEqual(result.plan.workouts.first { $0.id == completed.id }, completed)
    }

    func testMovedWorkoutDiffIncludesLocalDateAndStepDetails() throws {
        let original = workout(day: 9, kind: .tempo)
        var moved = original
        moved.blueprint.date = date(10)

        let changes = CoachPlanRules.changes(
            from: plan([original]),
            to: plan([moved]),
            asOf: asOf,
            calendar: calendar
        )
        let change = try XCTUnwrap(changes.first)
        XCTAssertTrue(change.before.contains("2026-01-09"), change.before)
        XCTAssertTrue(change.after.contains("2026-01-10"), change.after)
        XCTAssertTrue(change.before.contains("steps [tempo: 8000 m @ threshold]"), change.before)
    }

    func testTravelRequiresDatesAndMovesQualityWithoutMovingLongRun() throws {
        XCTAssertThrowsError(try CoachPlanRules.preview(
            intent: .reshapeForTravel(travelDates: []),
            plan: plan([workout(day: 9, kind: .tempo), workout(day: 11, kind: .longRun)]),
            profile: profile(),
            asOf: asOf,
            calendar: calendar
        )) { error in
            XCTAssertEqual(error as? CoachPlanRuleError, .travelDatesRequired)
        }

        let easy = workout(day: 7, kind: .easy)
        let quality = workout(day: 9, kind: .tempo)
        let race = workout(day: 9, kind: .race, distance: 5_000)
        let longRun = workout(day: 11, kind: .longRun, distance: 12_000)
        let result = try CoachPlanRules.preview(
            intent: .reshapeForTravel(travelDates: [date(9)]),
            plan: plan([easy, quality, race, longRun]),
            profile: profile(),
            asOf: asOf,
            calendar: calendar
        )
        XCTAssertTrue(result.plan.workouts.contains { $0.id == longRun.id && $0.date == longRun.date })
        XCTAssertTrue(result.plan.workouts.contains { $0.id == race.id && $0.date == race.date })
        XCTAssertFalse(result.plan.workouts.contains { $0.id == easy.id })
        XCTAssertNotEqual(result.plan.workouts.first { $0.id == quality.id }?.date, quality.date)
    }

    func testTravelRejectsReversedAndDuplicateDates() throws {
        let first = date(9)
        let second = date(10)
        for dates in [[second, first], [first, first], [first, date(9).addingTimeInterval(12 * 60 * 60)]] {
            XCTAssertThrowsError(try CoachPlanRules.preview(
                intent: .reshapeForTravel(travelDates: dates),
                plan: plan([workout(day: 9, kind: .tempo)]),
                profile: profile(),
                asOf: asOf,
                calendar: calendar
            )) { error in
                XCTAssertEqual(error as? CoachPlanRuleError, .invalidDateInput)
            }
        }
    }

    func testTravelRejectsBackToBackQualityWhenNoSafeDayExists() throws {
        var constrainedProfile = profile(days: [.monday, .wednesday, .friday])
        constrainedProfile.longRunWeekday = .friday
        let qualityDuringTravel = workout(day: 9, kind: .tempo)
        let qualityOnOnlyOtherDay = workout(day: 16, kind: .intervals)
        XCTAssertThrowsError(try CoachPlanRules.preview(
            intent: .reshapeForTravel(travelDates: (7...16).map(date)),
            plan: plan([qualityDuringTravel, qualityOnOnlyOtherDay], profile: constrainedProfile),
            profile: constrainedProfile,
            asOf: asOf,
            calendar: calendar
        )) { error in
            XCTAssertEqual(error as? CoachPlanRuleError, .noSafeTravelSchedule)
        }
    }

    func testVDOTIncreaseCapsAtThreePercentAndLargeDecreaseIsRejected() throws {
        let adjustment = try CoachPlanRules.validateVDOT(current: 45, requested: 60)
        XCTAssertEqual(adjustment.effectiveTarget, 46.35, accuracy: 0.001)
        XCTAssertEqual(adjustment.warnings.first?.severity, .soft)
        XCTAssertThrowsError(try CoachPlanRules.validateVDOT(current: 45, requested: 40)) { error in
            XCTAssertEqual(error as? CoachPlanRuleError, .vdotDecreaseExceedsLimit)
        }
    }

    func testLongRunWeekdayMustBeAvailableAndTreadmillOnlyChangesSelectedFutureWorkout() throws {
        XCTAssertNoThrow(try CoachPlanRules.validateLongRunWeekday(.friday, profile: profile()))
        XCTAssertThrowsError(try CoachPlanRules.validateLongRunWeekday(.tuesday, profile: profile()))

        let completed = workout(day: 3, kind: .easy, status: .completed)
        let selected = workout(day: 9, kind: .tempo)
        let other = workout(day: 11, kind: .longRun)
        let result = try CoachPlanRules.preview(
            intent: .moveWorkoutIndoors(workoutID: selected.id),
            plan: plan([completed, selected, other]),
            profile: profile(),
            asOf: asOf,
            calendar: calendar
        )
        XCTAssertEqual(result.plan.workouts.first { $0.id == selected.id }?.blueprint.location, .treadmill)
        XCTAssertEqual(result.plan.workouts.first { $0.id == other.id }, other)
        XCTAssertEqual(result.plan.workouts.first { $0.id == completed.id }, completed)
    }

    func testProtectedPastAndCompletedWorkoutsCannotBeChangedByAProposal() throws {
        let past = workout(day: 3, kind: .easy)
        let completed = workout(day: 5, kind: .tempo, status: .completed)
        var proposed = plan([past, completed])
        proposed.workouts[0].blueprint.title = "Changed past workout"

        XCTAssertThrowsError(try CoachPlanRules.validateProtectedWorkoutsUnchanged(
            current: plan([past, completed]),
            proposed: proposed,
            asOf: asOf,
            calendar: calendar
        )) { error in
            XCTAssertEqual(error as? CoachPlanRuleError, .protectedWorkoutChanged)
        }
    }

    func testMalformedPlansAndInputsFailClosedWithoutDiffCrashes() throws {
        let original = workout(day: 9, kind: .easy)
        var duplicateIDs = plan([original, original])
        XCTAssertThrowsError(try CoachPlanRules.preview(
            intent: .moveWorkoutIndoors(workoutID: original.id),
            plan: duplicateIDs,
            profile: profile(),
            asOf: asOf,
            calendar: calendar
        )) { error in
            guard case .invalidPlan = error as? CoachPlanRuleError else {
                return XCTFail("Expected duplicate IDs to be rejected")
            }
        }
        duplicateIDs.workouts.append(original)
        XCTAssertTrue(CoachPlanRules.changes(from: duplicateIDs, to: duplicateIDs, asOf: asOf, calendar: calendar).isEmpty)

        var invalidDistance = plan([workout(day: 9, kind: .easy)])
        invalidDistance.workouts[0].blueprint.plannedDistanceMeters = .nan
        XCTAssertThrowsError(try CoachPlanRules.preview(
            intent: .cutIntensity,
            plan: invalidDistance,
            profile: profile(),
            asOf: asOf,
            calendar: calendar
        )) { error in
            guard case .invalidPlan = error as? CoachPlanRuleError else {
                return XCTFail("Expected non-finite distance to be rejected")
            }
        }

        let invalidDate = Date(timeIntervalSinceReferenceDate: Double.nan)
        XCTAssertThrowsError(try CoachPlanRules.preview(
            intent: .reshapeForTravel(travelDates: [invalidDate]),
            plan: plan([workout(day: 9, kind: .easy)]),
            profile: profile(),
            asOf: asOf,
            calendar: calendar
        )) { error in
            XCTAssertEqual(error as? CoachPlanRuleError, .invalidDateInput)
        }
    }

    func testSorenessAndTreadmillRejectNonEditableWorkouts() throws {
        let race = workout(day: 9, kind: .race, distance: 5_000)
        let longRun = workout(day: 10, kind: .longRun, distance: 12_000)
        XCTAssertThrowsError(try CoachPlanRules.preview(
            intent: .cutIntensity,
            plan: plan([race, longRun]),
            profile: profile(),
            asOf: asOf,
            calendar: calendar
        )) { error in
            guard case .noEligibleWorkout = error as? CoachPlanRuleError else {
                return XCTFail("A race must not be converted as a soreness adjustment")
            }
        }

        let strength = workout(day: 9, kind: .strength)
        XCTAssertThrowsError(try CoachPlanRules.preview(
            intent: .moveWorkoutIndoors(workoutID: strength.id),
            plan: plan([strength]),
            profile: profile(),
            asOf: asOf,
            calendar: calendar
        )) { error in
            guard case .noEligibleWorkout = error as? CoachPlanRuleError else {
                return XCTFail("Strength sessions must not be moved to a treadmill")
            }
        }
    }

    func testInvalidProfileAndExtremeDateInputsAreRejected() throws {
        var invalidProfile = profile()
        invalidProfile.vdot = .nan
        XCTAssertThrowsError(try CoachPlanRules.preview(
            intent: .moveWorkoutIndoors(workoutID: UUID()),
            plan: plan([workout(day: 9, kind: .easy)]),
            profile: invalidProfile,
            asOf: asOf,
            calendar: calendar
        )) { error in
            guard case .invalidProfile = error as? CoachPlanRuleError else {
                return XCTFail("Expected invalid VDOT profile to be rejected")
            }
        }

        let extremeTravelDate = Date(timeIntervalSinceReferenceDate: 1_000_000_000)
        XCTAssertThrowsError(try CoachPlanRules.preview(
            intent: .reshapeForTravel(travelDates: [extremeTravelDate]),
            plan: plan([workout(day: 9, kind: .easy)]),
            profile: profile(),
            asOf: asOf,
            calendar: calendar
        )) { error in
            XCTAssertEqual(error as? CoachPlanRuleError, .noChanges)
        }
    }

    func testValidationRejectsMalformedProfilesAndProtectedPlanShapes() throws {
        var duplicateDays = profile()
        duplicateDays.availableWeekdays = [.monday, .monday, .friday]
        XCTAssertThrowsError(try CoachPlanRules.validateProfile(duplicateDays)) { error in
            guard case .invalidProfile = error as? CoachPlanRuleError else {
                return XCTFail("Duplicate available weekdays must be rejected")
            }
        }

        var invalidDays = profile()
        invalidDays.availableWeekdays = Weekday.allCases
        XCTAssertThrowsError(try CoachPlanRules.validateProfile(invalidDays)) { error in
            guard case .invalidProfile = error as? CoachPlanRuleError else {
                return XCTFail("Seven available weekdays must be rejected")
            }
        }

        var invalidMileage = profile()
        invalidMileage.longestRunMeters = invalidMileage.weeklyMileageMeters + 1
        XCTAssertThrowsError(try CoachPlanRules.validateProfile(invalidMileage)) { error in
            guard case .invalidProfile = error as? CoachPlanRuleError else {
                return XCTFail("A longest run above weekly mileage must be rejected")
            }
        }

        var invalidRace = profile()
        invalidRace.recentRace = RaceResult(distanceMeters: 5_000, duration: .infinity)
        XCTAssertThrowsError(try CoachPlanRules.validateProfile(invalidRace)) { error in
            guard case .invalidProfile = error as? CoachPlanRuleError else {
                return XCTFail("Non-finite race data must be rejected")
            }
        }

        let original = plan([workout(day: 9, kind: .easy)])
        var duplicateProposed = original
        duplicateProposed.workouts.append(original.workouts[0])
        XCTAssertThrowsError(try CoachPlanRules.validateProtectedWorkoutsUnchanged(
            current: original,
            proposed: duplicateProposed,
            asOf: asOf,
            calendar: calendar
        )) { error in
            guard case .invalidPlan = error as? CoachPlanRuleError else {
                return XCTFail("Duplicate proposed IDs must fail closed")
            }
        }

        XCTAssertThrowsError(try CoachPlanRules.validateProtectedWorkoutsUnchanged(
            current: original,
            proposed: original,
            asOf: Date(timeIntervalSinceReferenceDate: .nan),
            calendar: calendar
        )) { error in
            XCTAssertEqual(error as? CoachPlanRuleError, .invalidDateInput)
        }
    }

    func testVDOTRejectsNonFiniteValuesAndAcceptsBothThreePercentBoundaries() throws {
        for requested in [0.0, -1.0, .nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try CoachPlanRules.validateVDOT(current: 45, requested: requested)) { error in
                XCTAssertEqual(error as? CoachPlanRuleError, .invalidVDOT)
            }
        }
        XCTAssertEqual(
            try CoachPlanRules.validateVDOT(current: 45, requested: 45 * 0.97).effectiveTarget,
            43.65,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try CoachPlanRules.validateVDOT(current: 45, requested: 45 * 1.03).effectiveTarget,
            46.35,
            accuracy: 0.001
        )
    }

    func testVDOTNoOpDoesNotCreateAProposal() throws {
        let current = profile()
        XCTAssertThrowsError(try CoachPlanRules.preview(
            intent: .retargetVDOT(target: current.vdot),
            plan: plan([workout(day: 9, kind: .tempo)]),
            profile: current,
            asOf: asOf,
            calendar: calendar
        )) { error in
            XCTAssertEqual(error as? CoachPlanRuleError, .noChanges)
        }
    }

    func testFutureOnlyAndNoOpWorkoutEditsFailClosed() throws {
        let scheduled = workout(day: 9, kind: .tempo)
        let completed = workout(day: 9, kind: .tempo, status: .completed)
        let skipped = workout(day: 9, kind: .tempo, status: .skipped)
        let past = workout(day: 3, kind: .tempo)
        let treadmill = workout(day: 9, kind: .tempo, location: .treadmill)

        for candidate in [completed, skipped, past] {
            XCTAssertThrowsError(try CoachPlanRules.preview(
                intent: .moveWorkoutIndoors(workoutID: candidate.id),
                plan: plan([candidate]),
                profile: profile(),
                asOf: asOf,
                calendar: calendar
            )) { error in
                XCTAssertEqual(error as? CoachPlanRuleError, .workoutAlreadyStarted)
            }
        }

        XCTAssertThrowsError(try CoachPlanRules.preview(
            intent: .moveWorkoutIndoors(workoutID: UUID()),
            plan: plan([scheduled]),
            profile: profile(),
            asOf: asOf,
            calendar: calendar
        )) { error in
            XCTAssertEqual(error as? CoachPlanRuleError, .workoutNotFound)
        }

        XCTAssertThrowsError(try CoachPlanRules.preview(
            intent: .moveWorkoutIndoors(workoutID: treadmill.id),
            plan: plan([treadmill]),
            profile: profile(),
            asOf: asOf,
            calendar: calendar
        )) { error in
            XCTAssertEqual(error as? CoachPlanRuleError, .noChanges)
        }

        var changedPast = plan([past])
        changedPast.workouts[0].blueprint.title = "Tampered"
        XCTAssertTrue(CoachPlanRules.changes(from: plan([past]), to: changedPast, asOf: asOf, calendar: calendar).isEmpty)
    }

    func testTypedIntentRoundTripsAndMalformedPayloadsFailClosed() throws {
        let intents: [CoachIntent] = [
            .cutIntensity,
            .reshapeForTravel(travelDates: [date(8), date(10)]),
            .retargetVDOT(target: 46.35),
            .moveLongRun(to: .friday),
            .moveWorkoutIndoors(workoutID: UUID()),
            .clarificationRequired,
            .answerOnly,
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for intent in intents {
            let encoded = try encoder.encode(intent)
            XCTAssertEqual(try decoder.decode(CoachIntent.self, from: encoded), intent)
        }

        for payload in [
            "{}",
            "{\"kind\":\"retargetVDOT\"}",
            "{\"kind\":\"moveLongRun\",\"weekday\":\"not-a-weekday\"}",
            "{\"kind\":\"moveWorkoutIndoors\",\"workoutID\":\"not-a-uuid\"}",
            "{\"kind\":\"unknown\"}",
        ] {
            XCTAssertThrowsError(try decoder.decode(CoachIntent.self, from: Data(payload.utf8)))
        }
    }

    // MARK: - Race week

    /// Every earlier test used a goal with no race date, so the one guard that knew race day
    /// existed had never executed. These are the first with a race on the calendar.
    private func racePlan(_ workouts: [ScheduledWorkout], raceDay: Int) -> TrainingPlan {
        TrainingPlan(
            goal: TrainingGoal(kind: .fiveK, raceDate: date(raceDay)),
            profile: profile(),
            workouts: workouts
        )
    }

    func testSorenessCutIsBlockedWhenItWouldChangeRaceWeek() throws {
        // Race on day 20; race week is days 14-20. Asked on day 14, the next seven days hold a
        // taper quality session and the last long run -- exactly what a soreness cut would take.
        let plan = racePlan([
            workout(day: 16, kind: .tempo),
            workout(day: 18, kind: .longRun),
            workout(day: 20, kind: .race)
        ], raceDay: 20)

        let result = try CoachPlanRules.preview(
            intent: .cutIntensity, plan: plan, profile: profile(), asOf: date(14), calendar: calendar
        )

        let blocking = result.warnings.filter { $0.severity == .blocking }
        XCTAssertEqual(blocking.count, 1, "a change landing in race week must block, not warn softly")
        XCTAssertTrue(blocking.first?.message.contains("race week") ?? false)
    }

    func testSorenessCutOutsideRaceWeekIsNotBlocked() throws {
        // Same plan, asked on day 4: the cut lands on days 6 and 8, well clear of the taper.
        let plan = racePlan([
            workout(day: 6, kind: .tempo),
            workout(day: 8, kind: .longRun),
            workout(day: 16, kind: .tempo),
            workout(day: 18, kind: .longRun),
            workout(day: 20, kind: .race)
        ], raceDay: 20)

        let result = try CoachPlanRules.preview(
            intent: .cutIntensity, plan: plan, profile: profile(), asOf: date(4), calendar: calendar
        )

        XCTAssertTrue(result.warnings.filter { $0.severity == .blocking }.isEmpty, "race week must only be guarded when it is actually touched")
        XCTAssertFalse(result.changes.isEmpty)
    }

    func testTravelOnRaceDayIsBlockedAndNamed() throws {
        // Travel spans days 19-20. Day 19's easy run is removed (a real change, so the rule does
        // not throw `.noChanges` first) and day 20 is race day.
        let plan = racePlan([
            workout(day: 19, kind: .easy),
            workout(day: 20, kind: .race)
        ], raceDay: 20)

        let result = try CoachPlanRules.preview(
            intent: .reshapeForTravel(travelDates: [date(19), date(20)]),
            plan: plan, profile: profile(), asOf: date(10), calendar: calendar
        )

        let messages = result.warnings.filter { $0.severity == .blocking }.map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("race day") }, "travel on race day must be called out by name")
        XCTAssertTrue(messages.contains { $0.contains("race week") }, "removing the day-19 run is a race-week change")
    }
}
