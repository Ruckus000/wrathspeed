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
    public static func map(_ response: CoachTypedResponse, context: CoachContext) -> CoachIntent {
        let intent = response.intent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch intent {
        case "cutintensity", "cut_intensity", "soreness":
            guard !hasUnexpectedFields(response, except: []) else { return .clarificationRequired }
            return .cutIntensity
        case "reshapefortravel", "reshape_for_travel", "travel":
            guard !hasUnexpectedFields(response, except: [.travel]) else { return .clarificationRequired }
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
            guard !hasUnexpectedFields(response, except: [.vdot]) else { return .clarificationRequired }
            guard let target = response.targetVDOT, target.isFinite, target > 0 else { return .clarificationRequired }
            return .retargetVDOT(target: target)
        case "movelongrun", "move_long_run":
            guard !hasUnexpectedFields(response, except: [.weekday]) else { return .clarificationRequired }
            guard let rawWeekday = response.targetWeekday,
                  let weekday = parseWeekday(rawWeekday)
            else { return .clarificationRequired }
            return .moveLongRun(to: weekday)
        case "moveworkoutindoors", "move_workout_indoors", "treadmill", "weather":
            guard !hasUnexpectedFields(response, except: [.workout]),
                  let rawReference = response.workoutReference
            else { return .clarificationRequired }
            let reference = rawReference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard reference.range(of: #"^w[1-9][0-9]*$"#, options: .regularExpression) != nil,
                  let workout = context.workouts.first(where: {
                      $0.reference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == reference
                  })
            else { return .clarificationRequired }
            return .moveWorkoutIndoors(workoutID: workout.id)
        case "answeronly", "answer_only":
            guard !hasUnexpectedFields(response, except: []) else { return .clarificationRequired }
            return .answerOnly
        default:
            return .clarificationRequired
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

    private enum Field: Hashable {
        case travel
        case vdot
        case weekday
        case workout
    }

    private static func hasUnexpectedFields(_ response: CoachTypedResponse, except allowed: Set<Field>) -> Bool {
        let populated: [(Field, Bool)] = [
            (.travel, hasValue(response.travelStart) || hasValue(response.travelEnd)),
            (.vdot, response.targetVDOT != nil),
            (.weekday, hasValue(response.targetWeekday)),
            (.workout, hasValue(response.workoutReference)),
        ]
        return populated.contains { field, isPresent in isPresent && !allowed.contains(field) }
    }

    private static func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Recovery and replies

/// Repairs the narrow case where a model answers an explicit supported edit request as ordinary
/// conversation. This is intentionally conservative: it only recovers the no-parameter soreness
/// intent and never invents dates, weekdays, VDOTs, or workout references. The compiler remains the
/// only thing that turns an intent into a plan change.
public enum CoachIntentRecovery {
    public static func resolve(modelIntent: CoachIntent, message: String) -> CoachIntent {
        switch modelIntent {
        case .cutIntensity:
            // A model must not turn a soreness mention into an edit unless the user explicitly
            // asked for one. Without both a marker and an explicit request, this is conversation.
            guard hasSorenessMarker(in: message), explicitIntent(in: message) == .cutIntensity else {
                return .answerOnly
            }
            return .cutIntensity
        case .answerOnly, .clarificationRequired:
            return explicitIntent(in: message) ?? modelIntent
        default:
            return modelIntent
        }
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
        return ["sore", "soreness", "not feeling 100%", "beat up"].contains(where: normalized.contains)
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
            "scale back", "dial back", "take it easy", "convert", "make it safer",
            "easier week"
        ].contains { message.contains($0) }
    }
}

// MARK: - The model client

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

    public func respond(
        to message: String,
        context: CoachContext
    ) async throws -> (raw: CoachTypedResponse, mapped: CoachIntent) {
        let modelSession: LanguageModelSession
        if let existing = session {
            modelSession = existing
        } else {
            let created = LanguageModelSession(instructions: CoachPromptBuilder.instructions)
            session = created
            modelSession = created
        }
        let response = try await modelSession.respond(
            to: CoachPromptBuilder.prompt(message: message, context: context),
            generating: AppleCoachResponse.self
        )
        let raw = CoachTypedResponse(
            reply: response.content.reply,
            intent: response.content.intent,
            workoutReference: response.content.workoutReference,
            targetWeekday: response.content.targetWeekday,
            targetVDOT: response.content.targetVDOT,
            travelStart: response.content.travelStart,
            travelEnd: response.content.travelEnd
        )
        return (raw, CoachIntentMapper.map(raw, context: context))
    }

    public func reset() {
        session = nil
    }
}
#endif
