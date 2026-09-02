import XCTest
@testable import WrathspeedCore

/// The contract between the model's typed answer and the intent the app acts on.
final class CoachContractTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func context() -> CoachContext {
        let profile = RunnerProfile(ability: .intermediate, daysPerWeek: 5, longRunWeekday: .sunday, unit: .kilometers)
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!
        let plan = PlanGenerator.generate(PlanRequest(goal: TrainingGoal(kind: .tenK), profile: profile, startDate: start, calendar: calendar))
        return CoachContext.make(plan: plan, profile: profile, results: [], asOf: start, calendar: calendar)!
    }

    // The evaluation harness recorded the on-device model filling optionals it does not need on
    // seven of its first eight correct intents -- `targetVDOT: 30`, `targetWeekday: "Tuesday"`,
    // `workoutReference: "w1"` on a travel request with perfect dates. Rejecting those turned
    // nearly every right answer into a clarification. Fields an intent does not read must not
    // change what it maps to; they cannot change what it does.
    func testStrayFieldsDoNotDemoteACorrectIntent() {
        let context = context()
        let travel = CoachTypedResponse(
            reply: "", intent: "reshapeForTravel",
            workoutReference: "w1", targetWeekday: "Tuesday", targetVDOT: 45,
            travelStart: "2026-09-14", travelEnd: "2026-09-18"
        )
        guard case let .reshapeForTravel(dates) = CoachIntentMapper.map(travel, context: context) else {
            return XCTFail("a travel intent with both dates must map to reshapeForTravel whatever else is filled")
        }
        XCTAssertEqual(dates.count, 5)

        let sore = CoachTypedResponse(reply: "", intent: "cutIntensity", workoutReference: "w1", targetWeekday: "Tuesday", targetVDOT: 30)
        XCTAssertEqual(CoachIntentMapper.map(sore, context: context), .cutIntensity)

        let longRun = CoachTypedResponse(reply: "", intent: "moveLongRun", workoutReference: "w4", targetWeekday: "Saturday", targetVDOT: 14641, travelStart: "2026-09-07", travelEnd: "2026-09-07")
        XCTAssertEqual(CoachIntentMapper.map(longRun, context: context), .moveLongRun(to: .saturday))

        let answer = CoachTypedResponse(reply: "VDOT is...", intent: "answerOnly", targetVDOT: 45)
        XCTAssertEqual(CoachIntentMapper.map(answer, context: context), .answerOnly)
    }

    // Missing *required* fields still clarify: that guard is what keeps the model from inventing
    // a date, a weekday, or a workout.
    func testMissingRequiredFieldsStillClarify() {
        let context = context()
        XCTAssertEqual(CoachIntentMapper.map(CoachTypedResponse(reply: "", intent: "reshapeForTravel", travelStart: "2026-09-14"), context: context), .clarificationRequired)
        XCTAssertEqual(CoachIntentMapper.map(CoachTypedResponse(reply: "", intent: "moveLongRun"), context: context), .clarificationRequired)
        XCTAssertEqual(CoachIntentMapper.map(CoachTypedResponse(reply: "", intent: "moveWorkoutIndoors", workoutReference: "w999"), context: context), .clarificationRequired)
        XCTAssertEqual(CoachIntentMapper.map(CoachTypedResponse(reply: "", intent: "retargetVDOT", targetVDOT: -5), context: context), .clarificationRequired)
    }

    // The harness flagged four replies that promised an edit the mapper had just refused ("I'll
    // reshape your week for September 20 to 12"). The runner reads a promise; no card follows.
    func testAnEditNamedWithoutItsFieldGetsACannedAskNotThePromise() {
        let reversed = CoachTypedResponse(
            reply: "I'll reshape your week for your trip from September 20 to September 12.",
            intent: "reshapeForTravel", travelStart: "2026-09-20", travelEnd: "2026-09-12"
        )
        XCTAssertEqual(CoachIntentMapper.map(reversed, context: context()), .clarificationRequired)
        XCTAssertEqual(
            CoachIntentMapper.clarificationAsk(for: reversed),
            "Which dates are you away? Give me the first and last day, and I’ll preview the changes."
        )
        XCTAssertEqual(CoachIntentMapper.clarificationAsk(for: CoachTypedResponse(reply: "", intent: "moveLongRun")), "Which weekday should the long run move to?")
        XCTAssertNil(CoachIntentMapper.clarificationAsk(for: CoachTypedResponse(reply: "hi", intent: "answerOnly")))
        if #available(iOS 26.0, macOS 26.0, *) {
            XCTAssertFalse(CoachModelClient.refusalReply.isEmpty)
            XCTAssertTrue(CoachModelClient.refusalReply.contains("unchanged"), "a refusal must say the plan was not touched")
        }
    }

    // With the mapper no longer demoting, the harness showed the model naming an edit the runner
    // never asked for: "add a sixth run day" → moveLongRun, "make every run a tempo" →
    // retargetVDOT, "I need to move some things around" → an applicable travel reshape. The
    // message must corroborate the intent, the way the soreness gate already required.
    func testAnEditIntentTheMessageDoesNotCorroborateIsDemotedWithAnAsk() {
        let cases: [(CoachIntent, String)] = [
            (.moveLongRun(to: .sunday), "add a sixth run day"),
            (.retargetVDOT(target: 45), "make every run a tempo run"),
            (.reshapeForTravel(travelDates: [Date()]), "I need to move some things around"),
            (.moveWorkoutIndoors(workoutID: UUID()), "what's on Thursday?"),
        ]
        for (intent, message) in cases {
            let resolution = CoachIntentRecovery.resolution(modelIntent: intent, message: message)
            XCTAssertEqual(resolution.intent, .clarificationRequired, message)
            XCTAssertNotNil(resolution.demotedAsk, "a demotion must carry its own ask, never the model's promise: \(message)")
        }
    }

    func testACorroboratedEditIntentPassesThrough() {
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .moveLongRun(to: .sunday), message: "can we do the long run on Sundays instead?"), .moveLongRun(to: .sunday))
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .retargetVDOT(target: 46), message: "My VDOT test came back at 46. Update my paces."), .retargetVDOT(target: 46))
        let dates = (14...18).map { calendar.date(from: DateComponents(year: 2026, month: 9, day: $0))! }
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .reshapeForTravel(travelDates: dates), message: "I'll be in Denver for work September 14 to 18", calendar: calendar), .reshapeForTravel(travelDates: dates))
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .reshapeForTravel(travelDates: dates), message: "away 9/14-9/18", calendar: calendar), .reshapeForTravel(travelDates: dates))
        let id = UUID()
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .moveWorkoutIndoors(workoutID: id), message: "it's going to pour tomorrow, can I do that run on the treadmill?"), .moveWorkoutIndoors(workoutID: id))
    }

    // "I'm travelling." / "September 14 to 18." — the corroboration lives in the earlier turn.
    func testPriorTurnsCorroborateAMultiTurnEdit() {
        let dates = (14...18).map { calendar.date(from: DateComponents(year: 2026, month: 9, day: $0))! }
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .reshapeForTravel(travelDates: dates), message: "September 14 to 18.", priorTurns: ["I'm travelling."], calendar: calendar), .reshapeForTravel(travelDates: dates))
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .moveLongRun(to: .sunday), message: "Sunday", priorTurns: ["Can you move my long run?"]), .moveLongRun(to: .sunday))
    }

    // The soreness demotion used to fall through to the model's reply, which was routinely the
    // parroted "I'll preview turning the next quality workout..." — a promise with no card.
    func testASorenessDemotionCarriesAnAskNotThePromise() {
        let resolution = CoachIntentRecovery.resolution(modelIntent: .cutIntensity, message: "put Tuesday's run on the treadmill")
        XCTAssertEqual(resolution.intent, .answerOnly)
        XCTAssertNotNil(resolution.demotedAsk)
        XCTAssertEqual(CoachIntentRecovery.reply(for: resolution.intent, modelReply: "I'll preview turning the next quality workout into an easy run.", demotedAsk: resolution.demotedAsk), resolution.demotedAsk)
    }

    // The harness recorded the model inventing Sept 14-16 for "September 20 to 12", getting every
    // relative date wrong, picking the wrong workout in all five day-named indoor requests, and
    // returning 47 for "VDOT 46". A bounded parameter must be traceable to the runner's words.
    func testTravelDatesMustBeBracketedByDayNumbersTheRunnerStated() {
        let sept = { (day: Int) in self.calendar.date(from: DateComponents(year: 2026, month: 9, day: day))! }
        let fourteenToEighteen = (14...18).map(sept)
        let ok = CoachIntentRecovery.resolution(modelIntent: .reshapeForTravel(travelDates: fourteenToEighteen), message: "I'll be in Denver for work September 14 to 18", calendar: calendar)
        XCTAssertEqual(ok.intent, .reshapeForTravel(travelDates: fourteenToEighteen))
        let invented = CoachIntentRecovery.resolution(modelIntent: .reshapeForTravel(travelDates: (14...16).map(sept)), message: "trip from September 20 to September 12", calendar: calendar)
        XCTAssertEqual(invented.intent, .clarificationRequired)
        XCTAssertNotNil(invented.demotedAsk)
        let relative = CoachIntentRecovery.resolution(modelIntent: .reshapeForTravel(travelDates: [sept(4), sept(5)]), message: "away this weekend", calendar: calendar)
        XCTAssertEqual(relative.intent, .clarificationRequired, "relative dates are asked for as exact dates, never guessed")
        XCTAssertTrue(relative.demotedAsk?.contains("first and last day") == true)
    }

    func testLongRunWeekdayMustBeTheOneNamed() {
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .moveLongRun(to: .saturday), message: "move my long run to Sunday"), .clarificationRequired)
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .moveLongRun(to: .sunday), message: "can we do the long run on Sundays?"), .moveLongRun(to: .sunday))
    }

    func testIndoorWorkoutMustFallOnTheDayNamed() throws {
        let context = context()   // plan from Sunday 2026-08-30, runs Tue/Wed/Fri/Sat/Sun; asOf = Aug 30
        let saturday = try XCTUnwrap(context.workouts.first { calendar.component(.weekday, from: $0.date) == 7 })
        let tuesday = try XCTUnwrap(context.workouts.first { calendar.component(.weekday, from: $0.date) == 3 })
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .moveWorkoutIndoors(workoutID: saturday.id), message: "make Saturday's run a treadmill run", context: context, calendar: calendar), .moveWorkoutIndoors(workoutID: saturday.id))
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .moveWorkoutIndoors(workoutID: tuesday.id), message: "make Saturday's run a treadmill run", context: context, calendar: calendar), .clarificationRequired)
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .moveWorkoutIndoors(workoutID: tuesday.id), message: "put yesterday's run on the treadmill", context: context, calendar: calendar), .clarificationRequired)
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .moveWorkoutIndoors(workoutID: tuesday.id), message: "my next run indoors please", context: context, calendar: calendar), .clarificationRequired, "no day named: ask, do not accept the model's pick")
    }

    func testVDOTTargetMustAppearInTheMessage() {
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .retargetVDOT(target: 47), message: "My VDOT test came back at 46. Update my paces."), .clarificationRequired)
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .retargetVDOT(target: 46), message: "My VDOT test came back at 46. Update my paces."), .retargetVDOT(target: 46))
        XCTAssertEqual(CoachIntentRecovery.resolve(modelIntent: .retargetVDOT(target: 900), message: "set my VDOT to 900"), .retargetVDOT(target: 900))
    }

    func testPromptHashIsStableAcrossCalls() {
        XCTAssertEqual(CoachPromptBuilder.promptHash, CoachPromptBuilder.promptHash)
        XCTAssertEqual(CoachPromptBuilder.promptHash.count, 12)
    }
}
