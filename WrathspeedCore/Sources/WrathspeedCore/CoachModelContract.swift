import CryptoKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// The contract between the app and the on-device model: what the model is told, what it must
// return, and how that return becomes a typed intent. It lived in the app target, which meant
// nothing outside an XCTest run on a simulator could exercise it -- and every XCTest run sees the
// model as unavailable. Here it is reachable from a plain macOS executable, so the evaluation
// harness measures the prompt that ships rather than a copy of it.
//
// Nothing about persistence changes. The app's provider keeps the availability guard and
// delegates to `CoachModelClient`.

// MARK: - What the model returns, before mapping

/// Kept outside Foundation Models so typed-response mapping can be tested with a fake provider.
public struct CoachTypedResponse: Equatable, Sendable {
    public var reply: String
    public var intent: String
    public var workoutReference: String?
    public var targetWeekday: String?
    public var targetVDOT: Double?
    public var travelStart: String?
    public var travelEnd: String?

    public init(
        reply: String,
        intent: String,
        workoutReference: String? = nil,
        targetWeekday: String? = nil,
        targetVDOT: Double? = nil,
        travelStart: String? = nil,
        travelEnd: String? = nil
    ) {
        self.reply = reply
        self.intent = intent
        self.workoutReference = workoutReference
        self.targetWeekday = targetWeekday
        self.targetVDOT = targetVDOT
        self.travelStart = travelStart
        self.travelEnd = travelEnd
    }
}

// MARK: - The prompt

public enum CoachPromptBuilder {
    public static let instructions = """
    You are the Wrathspeed running coach. Return exactly one typed intent per response.
    Use only the supplied runner context. Never diagnose a medical condition, never claim pain
    is harmless, and never invent facts. If the request needs a missing date, weekday, or named
    workout, ask one concise clarification question and set intent to clarificationRequired.
    Intent mapping is explicit: a request that says the runner is sore, has soreness, or is not
    feeling 100% and asks to make the week safer maps to cutIntensity and needs no extra field;
    travel maps to reshapeForTravel only when both exact dates are present; faster paces maps to
    retargetVDOT only when a finite target VDOT is supplied; moving a long run requires a weekday;
    moving a workout indoors requires its stable workout reference. Never return answerOnly for a
    supported plan-edit request. For cutIntensity, say that you will preview turning the next
    quality workout into an easy run at 80% of its distance and reducing the next long run by 20%.
    Do not propose a plan when a validation-critical field is missing. Use a short stable workout
    reference such as w1, w2, or w3; never use UUIDs. Only these intent values are valid:
    cutIntensity, reshapeForTravel, retargetVDOT, moveLongRun, moveWorkoutIndoors,
    clarificationRequired, answerOnly. Return at most one plan proposal.
    """

    public static func prompt(message: String, context: CoachContext) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        // The context is already capped to `CoachPlanRules.modelReferenceLimit`; a second cap
        // here is where the prompt and the card drifted apart before.
        let workouts = context.workouts.map { workout in
            "\(workout.reference): \(formatter.string(from: workout.date)) \(workout.title) [\(workout.kind.rawValue), \(workout.status.rawValue), \(Int(workout.plannedDistanceMeters.rounded()))m, \(workout.location.rawValue)]"
        }.joined(separator: "\n")
        let results = context.recentResults.map { result in
            let pace = result.averagePaceSecPerKm.map { String(format: "%.0fs/km", $0) } ?? "unknown pace"
            let heartRate = result.heartRateAverage.map { String(format: "%.0f bpm", $0) } ?? "unknown HR"
            return "\(formatter.string(from: result.date)): \(Int(result.distanceMeters.rounded()))m, \(pace), \(heartRate)"
        }.joined(separator: "\n")
        // `today` was missing, so the model could not resolve "tomorrow" or "next Tuesday" to a
        // date -- every relative date it produced was a guess against workouts it could see.
        return """
        Runner context (derived summaries only):
        today=\(formatter.string(from: context.asOf)), currentWeekStart=\(formatter.string(from: context.currentWeekStart)),
        goal=\(context.goal.kind.displayName), vdot=\(String(format: "%.1f", context.profile.vdot)),
        availableDays=\(context.profile.resolvedRunWeekdays().map(\.displayName).joined(separator: ", ")),
        longRunDay=\(context.profile.longRunWeekday.displayName), adherence=\(String(format: "%.0f%%", context.adherence * 100))

        Upcoming workouts:
        \(workouts)

        Recent run summaries:
        \(results.isEmpty ? "none" : results)

        User message: \(message)
        """
    }

    /// Identifies the prompt a scorecard was produced against, so a later change to the
    /// instructions or the template shows up as a different key rather than a mystery drift.
    /// Rendered on a fixed context so it depends only on the text, never on a plan.
    public static var promptHash: String {
        let fixed = CoachContext(
            asOf: Date(timeIntervalSinceReferenceDate: 0),
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 3, longRunWeekday: .sunday, unit: .kilometers),
            currentWeekStart: Date(timeIntervalSinceReferenceDate: 0),
            workouts: [],
            recentResults: [],
            adherence: 1
        )
        let text = instructions + "\n---\n" + prompt(message: "", context: fixed)
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12).description
    }
}

// MARK: - Context builder

extension CoachContext {
    /// What the model is shown. One function, so the app and the harness hand the model the
    /// same view of the same plan.
    ///
    /// Pass the plan the runner *sees* -- the N100 overlay when one is active -- so an answer
    /// matches the screen. References are numbered over unstarted workouts only and capped to the
    /// model's window; see `CoachPlanRules.references`.
    public static func make(
        plan: TrainingPlan,
        profile: RunnerProfile,
        results: [WorkoutResult],
        asOf: Date,
        calendar: Calendar
    ) -> CoachContext? {
        guard asOf.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let references = CoachPlanRules.references(
            in: plan, asOf: asOf, calendar: calendar, limit: CoachPlanRules.modelReferenceLimit
        ).map { entry in
            CoachContext.WorkoutReference(
                id: entry.workout.id,
                reference: entry.reference,
                date: entry.workout.date,
                kind: entry.workout.blueprint.kind,
                title: entry.workout.blueprint.title,
                status: entry.workout.status,
                plannedDistanceMeters: entry.workout.blueprint.plannedDistanceMeters,
                location: entry.workout.blueprint.location
            )
        }
        let resultSummaries = results
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(8)
            .map {
                CoachContext.ResultSummary(
                    id: UUID(),
                    date: $0.startedAt,
                    distanceMeters: $0.distanceMeters,
                    averagePaceSecPerKm: $0.averagePaceSecPerKm,
                    heartRateAverage: $0.heartRateAverage
                )
            }
        let due = plan.workouts.filter {
            $0.blueprint.kind.isRunning && $0.date <= calendar.startOfDay(for: asOf)
        }
        let completed = due.filter { $0.status == .completed }.count
        let adherence = due.isEmpty ? 1 : Double(completed) / Double(due.count)
        return CoachContext(
            asOf: asOf,
            goal: plan.goal,
            profile: profile,
            currentWeekStart: calendar.dateInterval(of: .weekOfYear, for: asOf)?.start ?? asOf,
            workouts: references,
            recentResults: Array(resultSummaries),
            adherence: adherence
        )
    }
}

// MARK: - Mapping the model's answer to a typed intent

public enum CoachIntentMapper {
    /// Reads only the fields the named intent needs; see the note at the end of this type.
    public static func map(_ response: CoachTypedResponse, context: CoachContext) -> CoachIntent {
        let intent = response.intent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch intent {
        case "cutintensity", "cut_intensity", "soreness":
            return .cutIntensity
        case "reshapefortravel", "reshape_for_travel", "travel":
            guard let start = response.travelStart.flatMap(parseDate),
                  let end = response.travelEnd.flatMap(parseDate)
            else { return .clarificationRequired }
            guard start <= end else { return .clarificationRequired }
            var dates: [Date] = []
            var calendar = Calendar.current
            calendar.timeZone = .current
            var day = calendar.startOfDay(for: start)
            let endDay = calendar.startOfDay(for: end)
            while day <= endDay {
                dates.append(day)
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? endDay.addingTimeInterval(1)
            }
            return .reshapeForTravel(travelDates: dates)
        case "retargetvdot", "retarget_vdot", "fasterpaces", "faster_paces":
            guard let target = response.targetVDOT, target.isFinite, target > 0 else { return .clarificationRequired }
            return .retargetVDOT(target: target)
        case "movelongrun", "move_long_run":
            guard let rawWeekday = response.targetWeekday,
                  let weekday = parseWeekday(rawWeekday)
            else { return .clarificationRequired }
            return .moveLongRun(to: weekday)
        case "moveworkoutindoors", "move_workout_indoors", "treadmill", "weather":
            guard let rawReference = response.workoutReference else { return .clarificationRequired }
            let reference = rawReference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard reference.range(of: #"^w[1-9][0-9]*$"#, options: .regularExpression) != nil,
                  let workout = context.workouts.first(where: {
                      $0.reference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == reference
                  })
            else { return .clarificationRequired }
            return .moveWorkoutIndoors(workoutID: workout.id)
        case "answeronly", "answer_only":
            return .answerOnly
        default:
            return .clarificationRequired
        }
    }

    /// When the model names an edit but its required field is missing or malformed, the model's
    /// own reply usually still promises the edit ("I'll reshape your week for September 20 to
    /// 12"). The runner would read a promise and never see a card. This is the ask instead.
    public static func clarificationAsk(for response: CoachTypedResponse) -> String? {
        switch response.intent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "reshapefortravel", "reshape_for_travel", "travel":
            return "Which dates are you away? Give me the first and last day, and I’ll preview the changes."
        case "retargetvdot", "retarget_vdot", "fasterpaces", "faster_paces":
            return "What VDOT should I target? I can move paces up to 3% at a time."
        case "movelongrun", "move_long_run":
            return "Which weekday should the long run move to?"
        case "moveworkoutindoors", "move_workout_indoors", "treadmill", "weather":
            return "Which run should go indoors? Name the day."
        default:
            return nil
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: normalized) else { return nil }
        return formatter.string(from: date) == normalized ? date : nil
    }

    private static func parseWeekday(_ value: String) -> Weekday? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Weekday.allCases.first { weekday in
            weekday.displayName.lowercased() == normalized
                || String(weekday.displayName.prefix(3)).lowercased() == normalized
        }
    }

    // Nothing here rejects a response for the fields it did not need. The harness recorded the
    // on-device model filling unrelated optionals on seven of its first eight correct intents
    // (`targetVDOT: 30`, `targetWeekday: "Tuesday"`, `workoutReference: "w1"` on a travel request
    // with perfect dates); rejecting those turned nearly every right answer into a clarification.
    // A field an intent never reads cannot change what it does, so it cannot make it unsafe.
}

// MARK: - Recovery and replies

/// Repairs the narrow case where a model answers an explicit supported edit request as ordinary
/// conversation. This is intentionally conservative: it only recovers the no-parameter soreness
/// intent and never invents dates, weekdays, VDOTs, or workout references. The compiler remains the
/// only thing that turns an intent into a plan change.
public enum CoachIntentRecovery {
    public struct Resolution: Equatable {
        public var intent: CoachIntent
        /// Set when the model's edit intent was demoted: the reply to show instead of the
        /// model's text, which routinely still promises the edit.
        public var demotedAsk: String?
    }

    public static func resolve(
        modelIntent: CoachIntent, message: String, priorTurns: [String] = [],
        context: CoachContext? = nil, calendar: Calendar = .current
    ) -> CoachIntent {
        resolution(modelIntent: modelIntent, message: message, priorTurns: priorTurns, context: context, calendar: calendar).intent
    }

    /// The model names an intent; the message has to back it up. Nothing here invents a date, a
    /// weekday, a VDOT or a workout -- it only decides whether the model's edit may go forward
    /// to a preview. The evaluation harness recorded the on-device model answering "add a
    /// sixth run day" with moveLongRun and "make every run a tempo" with retargetVDOT; the
    /// apply gate would have held, but the runner would have been shown a proposal for a change
    /// they never asked for.
    /// The bounded parameter, too, must be traceable to the runner's words. The harness recorded
    /// the model inventing dates for a reversed range, getting every relative date wrong, picking
    /// the wrong workout in every day-named indoor request, and returning 47 for "VDOT 46". The
    /// card would have shown all of it; the runner should not have to catch it there.
    public static func resolution(
        modelIntent: CoachIntent, message: String, priorTurns: [String] = [],
        context: CoachContext? = nil, calendar: Calendar = .current
    ) -> Resolution {
        let text = (priorTurns.suffix(2) + [message]).joined(separator: " ").lowercased()
        switch modelIntent {
        case .cutIntensity:
            // A soreness mention is not a request. Both a marker and an explicit ask are needed.
            guard hasSorenessMarker(in: message), explicitIntent(in: message) == .cutIntensity else {
                return Resolution(intent: .answerOnly, demotedAsk: "If you want this week made easier, say so and I’ll preview the exact changes.")
            }
            return Resolution(intent: .cutIntensity, demotedAsk: nil)
        case let .reshapeForTravel(dates):
            let markers = ["travel", "trip", "away", "out of town", "vacation", "holiday", "flying", "fly ", "visiting", "conference", "abroad", "hotel"]
            guard markers.contains(where: text.contains) || containsDateLike(text) else {
                return Resolution(intent: .clarificationRequired, demotedAsk: "It sounds like a travel change. Tell me the dates you’re away and I’ll preview the changes.")
            }
            // The model cannot do date arithmetic; "this weekend" came back as the 4th and 5th on
            // a Wednesday the 2nd. Exact dates are asked for, and the stated days must bracket
            // what the model returned.
            let stated = dayNumbers(in: text)
            guard !stated.isEmpty else {
                return Resolution(intent: .clarificationRequired, demotedAsk: "I can’t turn relative dates into exact ones reliably. Give me the first and last day you’re away, like “Sept 14 to 18”, and I’ll preview the changes.")
            }
            let days = dates.map { calendar.component(.day, from: $0) }
            guard let first = days.min(), let last = days.max(), stated.contains(first), stated.contains(last) else {
                return Resolution(intent: .clarificationRequired, demotedAsk: "Those dates don’t match what you said. Give me the first and last day you’re away and I’ll preview the changes.")
            }
            return Resolution(intent: modelIntent, demotedAsk: nil)
        case let .moveLongRun(weekday):
            guard text.contains("long run") || text.contains("long-run") || text.contains("longrun") else {
                return Resolution(intent: .clarificationRequired, demotedAsk: "If you want the long run moved, tell me which weekday.")
            }
            guard text.contains(weekday.displayName.lowercased()) else {
                return Resolution(intent: .clarificationRequired, demotedAsk: "Which weekday should the long run move to?")
            }
            return Resolution(intent: modelIntent, demotedAsk: nil)
        case let .moveWorkoutIndoors(workoutID):
            let markers = ["treadmill", "indoor", "inside", "rain", "pour", "weather", "snow", "storm", "cold", "heat", "gym", "ice"]
            guard markers.contains(where: text.contains) else {
                return Resolution(intent: .clarificationRequired, demotedAsk: "If you want a run moved indoors, tell me which day.")
            }
            guard let context else { return Resolution(intent: modelIntent, demotedAsk: nil) }
            // The model picked the wrong workout in every day-named request the harness ran. The
            // run it chose has to fall on the day the runner named, within the coming week.
            let ask = "Which day’s run should go indoors? Name the day and I’ll preview it."
            guard let workout = context.workouts.first(where: { $0.id == workoutID }) else {
                return Resolution(intent: .clarificationRequired, demotedAsk: ask)
            }
            let today = calendar.startOfDay(for: context.asOf)
            let named: Date?
            if text.contains("yesterday") {
                return Resolution(intent: .clarificationRequired, demotedAsk: "I can only change upcoming runs. Which day’s run should go indoors?")
            } else if text.contains("tomorrow") {
                named = calendar.date(byAdding: .day, value: 1, to: today)
            } else if text.contains("today") || text.contains("tonight") {
                named = today
            } else if let weekday = weekdayNamed(in: text) {
                named = (0..<7).lazy.compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
                    .first { calendar.component(.weekday, from: $0) == weekday }
            } else {
                named = nil
            }
            guard let named, calendar.isDate(workout.date, inSameDayAs: named) else {
                return Resolution(intent: .clarificationRequired, demotedAsk: ask)
            }
            return Resolution(intent: modelIntent, demotedAsk: nil)
        case let .retargetVDOT(target):
            let markers = ["vdot", "pace", "faster", "slower", "quicker", "speed"]
            guard markers.contains(where: text.contains), text.contains(where: \.isNumber) else {
                return Resolution(intent: .clarificationRequired, demotedAsk: "If you want your paces changed, give me the VDOT to target.")
            }
            // The number the model returns has to be the number the runner said.
            let rounded = String(Int(target.rounded()))
            let exact = target == target.rounded() ? rounded : String(target)
            guard numberTokens(in: text).contains(rounded) || numberTokens(in: text).contains(exact) else {
                return Resolution(intent: .clarificationRequired, demotedAsk: "What VDOT should I target? Give me the number and I’ll preview the paces.")
            }
            return Resolution(intent: modelIntent, demotedAsk: nil)
        case .answerOnly, .clarificationRequired:
            return Resolution(intent: explicitIntent(in: message) ?? modelIntent, demotedAsk: nil)
        }
    }

    private static func numberTokens(in text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"\b\d+(?:\.\d+)?\b"#)
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }.map { String(text[$0]) }
    }

    /// Day-of-month numbers the runner typed: 1 through 31.
    private static func dayNumbers(in text: String) -> Set<Int> {
        Set(numberTokens(in: text).compactMap(Int.init).filter { (1...31).contains($0) })
    }

    /// Calendar weekday (1 = Sunday) of the first weekday name in the text, matched in English
    /// regardless of the device locale; the markers around it are English too.
    private static func weekdayNamed(in text: String) -> Int? {
        var english = Calendar(identifier: .gregorian)
        english.locale = Locale(identifier: "en_US_POSIX")
        for (index, symbol) in english.weekdaySymbols.enumerated() where text.contains(symbol.lowercased()) {
            return index + 1
        }
        return nil
    }

    /// A day-of-month with a month name, an ordinal, or a numeric m/d — any of these means the
    /// runner named a date.
    private static func containsDateLike(_ text: String) -> Bool {
        let patterns = [
            #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2}"#,
            #"\b\d{1,2}(st|nd|rd|th)\b"#,
            #"\b\d{1,2}/\d{1,2}"#,
            #"\b\d{4}-\d{2}-\d{2}\b"#,
            #"\b(tomorrow|weekend|next (mon|tue|wed|thu|fri|sat|sun)|this (mon|tue|wed|thu|fri|sat|sun))"#,
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// The reply the runner reads for a resolved intent. A demoted edit gets its own ask.
    public static func reply(for intent: CoachIntent, modelReply: String, demotedAsk: String?) -> String {
        if let demotedAsk { return demotedAsk }
        return reply(for: intent, modelReply: modelReply)
    }

    public static func reply(for intent: CoachIntent, modelReply: String) -> String {
        switch intent {
        case .cutIntensity:
            // Says what the rule does. It used to say the quality workout was "turned easy" and
            // only the long run reduced; the conversion also cuts it to 80% of its distance.
            return "I’ll make the next seven days safer: the next quality workout becomes an easy run at 80% of its distance, and the next long run is reduced by 20%. Review the exact changes below; nothing is applied until you approve them."
        case .reshapeForTravel:
            return "I’ll reshape only future workouts around those travel dates, preserve the long run, and show the exact changes below. Nothing is applied until you approve them."
        case .retargetVDOT:
            return "I’ll update future target paces within the 3% adaptation limit and leave completed work unchanged. Review the exact changes below before approving."
        case .moveLongRun:
            return "I’ll move the long run to that weekday and regenerate only the remaining weeks. Review the exact changes below before approving."
        case .moveWorkoutIndoors:
            return "I’ll change only that future workout’s location to treadmill. Review the exact change below before approving."
        case .clarificationRequired, .answerOnly:
            let trimmed = modelReply.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Tell me a little more so I can help safely." : trimmed
        }
    }

    public static func followUpReply(for message: String, proposal: CoachProposal) -> String? {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let asksForExplanation = [
            "how",
            "how will",
            "what do you mean",
            "what will",
            "why",
            "explain",
            "details"
        ].contains { normalized == $0 || normalized.hasPrefix($0 + " ") || normalized.hasPrefix($0 + "?") }
        guard asksForExplanation else { return nil }
        return "The proposal below shows the exact before-and-after changes for \(proposal.title.lowercased()). \(proposal.rationale) Nothing changes until you approve it."
    }

    private static func explicitIntent(in message: String) -> CoachIntent? {
        let normalized = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        guard hasSorenessMarker(in: normalized),
              !containsOptOut(in: normalized),
              containsExplicitAdjustmentRequest(in: normalized)
        else { return nil }

        let competingMarkers = [
            "travel", "trip", "pace", "vdot", "faster", "long run", "treadmill", "indoors",
            "inside", "weather"
        ]
        guard !competingMarkers.contains(where: normalized.contains)
        else { return nil }
        return .cutIntensity
    }

    private static func hasSorenessMarker(in message: String) -> Bool {
        let normalized = message.lowercased()
        return ["sore", "soreness", "not feeling 100%", "beat up", "wrecked", "trashed", "dead legs", "heavy legs", "tired legs"].contains(where: normalized.contains)
    }

    private static func containsOptOut(in message: String) -> Bool {
        [
            "not sore", "no soreness", "don't change", "do not change", "dont change",
            "keep as is", "leave it as is", "no adjustment", "don't adjust", "do not adjust",
            "just explain", "just asking", "what does", "what is", "meaning of", "define",
            "explain"
        ].contains { message.contains($0) }
    }

    private static func containsExplicitAdjustmentRequest(in message: String) -> Bool {
        [
            "adjust this week", "adjust my week", "adjust my plan", "change this week",
            "change my week", "change my plan", "modify this week", "modify my plan",
            "make this week", "make my week", "make my plan", "reduce", "cut back",
            "scale back", "dial back", "dial it back", "dial this week back", "dial my week back",
            "take it easy", "convert", "make it safer", "easier week", "easier", "back off"
        ].contains { message.contains($0) }
    }
}

// MARK: - The model client

/// One answer from the model, at every stage the app or the harness needs.
public struct CoachModelAnswer {
    /// Exactly what the model returned, before mapping.
    public var raw: CoachTypedResponse
    public var mapped: CoachIntent
    /// What the runner reads: the model's reply; a canned ask when the model named an edit it
    /// could not complete; or the fixed refusal reply.
    public var reply: String
    public var refused: Bool

    public init(raw: CoachTypedResponse, mapped: CoachIntent, reply: String, refused: Bool) {
        self.raw = raw
        self.mapped = mapped
        self.reply = reply
        self.refused = refused
    }
}

#if canImport(FoundationModels)
/// The structure the model is asked to fill. Field names are part of the contract: the mapper
/// reads them by name, and the harness records them raw before mapping.
@available(iOS 26.0, macOS 26.0, *)
@Generable
public struct AppleCoachResponse {
    public var reply: String
    public var intent: String
    public var workoutReference: String?
    public var targetWeekday: String?
    public var targetVDOT: Double?
    public var travelStart: String?
    public var travelEnd: String?
}

/// Owns one `LanguageModelSession` and returns the model's answer at two stages -- raw, and
/// mapped to a typed intent -- so a failure can be attributed to the model or to the schema.
/// Holds no reference to any store: a model response cannot mutate a plan from here.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
public final class CoachModelClient {
    private var session: LanguageModelSession?

    public init() {}

    public static var availability: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    /// What the runner reads when the model declines to answer. The on-device model refuses
    /// injury language outright ("May contain sensitive content" on shin pain, chest pain, a
    /// swollen knee); surfacing that as "try again" would be the worst reply at the one moment
    /// the health statement matters. No model text, no edit, and it says what to do.
    public nonisolated static let refusalReply = "I can’t help with that one here. If it’s about pain, illness or injury, stop if anything is sharp and check with a professional. Your plan is unchanged."

    public func respond(
        to message: String,
        context: CoachContext
    ) async throws -> CoachModelAnswer {
        let modelSession: LanguageModelSession
        if let existing = session {
            modelSession = existing
        } else {
            let created = LanguageModelSession(instructions: CoachPromptBuilder.instructions)
            session = created
            modelSession = created
        }
        let response: LanguageModelSession.Response<AppleCoachResponse>
        do {
            response = try await modelSession.respond(
                to: CoachPromptBuilder.prompt(message: message, context: context),
                generating: AppleCoachResponse.self
            )
        } catch let error as LanguageModelSession.GenerationError {
            guard case .refusal = error else { throw error }
            let raw = CoachTypedResponse(reply: Self.refusalReply, intent: "answerOnly")
            return CoachModelAnswer(raw: raw, mapped: .answerOnly, reply: Self.refusalReply, refused: true)
        }
        let raw = CoachTypedResponse(
            reply: response.content.reply,
            intent: response.content.intent,
            workoutReference: response.content.workoutReference,
            targetWeekday: response.content.targetWeekday,
            targetVDOT: response.content.targetVDOT,
            travelStart: response.content.travelStart,
            travelEnd: response.content.travelEnd
        )
        let mapped = CoachIntentMapper.map(raw, context: context)
        let reply = mapped == .clarificationRequired
            ? (CoachIntentMapper.clarificationAsk(for: raw) ?? raw.reply)
            : raw.reply
        return CoachModelAnswer(raw: raw, mapped: mapped, reply: reply, refused: false)
    }

    public func reset() {
        session = nil
    }
}
#endif
