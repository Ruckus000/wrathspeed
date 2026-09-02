import Foundation
import WrathspeedCore

#if canImport(FoundationModels)
import FoundationModels
#endif

enum CoachAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var explanation: String {
        switch self {
        case .available: ""
        case let .unavailable(message): message
        }
    }
}

struct CoachProviderResponse: Equatable, Sendable {
    var reply: String
    var intent: CoachIntent

    init(reply: String, intent: CoachIntent) {
        self.reply = reply
        self.intent = intent
    }
}

enum CoachProviderError: LocalizedError, Equatable {
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message), let .failed(message): message
        }
    }
}

@MainActor
protocol CoachProviding: AnyObject {
    var availability: CoachAvailability { get }
    func respond(to message: String, context: CoachContext) async throws -> CoachProviderResponse
    func reset()
}

/// Apple Foundation Models adapter. The session is intentionally in memory and this type has
/// no reference to AppStore, so a model response cannot mutate a plan without approval.
@MainActor
final class AppleCoachProvider: CoachProviding {
    private var session: Any?

    var availability: CoachAvailability {
#if DEBUG
        if UITestingSupport.isUITesting {
            return .unavailable("Conversational coaching is disabled for deterministic UI testing.")
        }
#endif
#if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            return .unavailable("Conversational coaching requires a compatible Apple Intelligence device.")
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case let .unavailable(reason):
            return .unavailable("Conversational coaching is unavailable on this device right now (\(reason)).")
        }
#else
        return .unavailable("Conversational coaching requires a compatible Apple Intelligence device.")
#endif
    }

    func respond(to message: String, context: CoachContext) async throws -> CoachProviderResponse {
#if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw CoachProviderError.unavailable(availability.explanation)
        }
        guard availability.isAvailable else {
            throw CoachProviderError.unavailable(availability.explanation)
        }

        let modelSession: LanguageModelSession
        if let existing = session as? LanguageModelSession {
            modelSession = existing
        } else {
            let created = LanguageModelSession(instructions: Self.instructions)
            session = created
            modelSession = created
        }

        do {
            let response = try await modelSession.respond(
                to: Self.prompt(message: message, context: context),
                generating: AppleCoachResponse.self
            )
            return Self.map(response.content, context: context)
        } catch let error as CoachProviderError {
            throw error
        } catch {
            throw CoachProviderError.failed("The coach couldn’t finish that response. Try again.")
        }
#else
        throw CoachProviderError.unavailable(availability.explanation)
#endif
    }

    func reset() {
        session = nil
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct AppleCoachResponse {
        var reply: String
        var intent: String
        var workoutReference: String?
        var targetWeekday: String?
        var targetVDOT: Double?
        var travelStart: String?
        var travelEnd: String?
    }

    @available(iOS 26.0, *)
    private static let instructions = """
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
    unstarted quality workout easy and reducing the current week’s unstarted long run by 20%.
    Do not propose a plan when a validation-critical field is missing. Use a short stable workout
    reference such as w1, w2, or w3; never use UUIDs. Only these intent values are valid:
    cutIntensity, reshapeForTravel, retargetVDOT, moveLongRun, moveWorkoutIndoors,
    clarificationRequired, answerOnly. Return at most one plan proposal.
    """

    @available(iOS 26.0, *)
    private static func prompt(message: String, context: CoachContext) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        let workouts = context.workouts.prefix(28).map { workout in
            "\(workout.reference): \(formatter.string(from: workout.date)) \(workout.title) [\(workout.kind.rawValue), \(workout.status.rawValue), \(Int(workout.plannedDistanceMeters.rounded()))m, \(workout.location.rawValue)]"
        }.joined(separator: "\n")
        let results = context.recentResults.map { result in
            let pace = result.averagePaceSecPerKm.map { String(format: "%.0fs/km", $0) } ?? "unknown pace"
            let heartRate = result.heartRateAverage.map { String(format: "%.0f bpm", $0) } ?? "unknown HR"
            return "\(formatter.string(from: result.date)): \(Int(result.distanceMeters.rounded()))m, \(pace), \(heartRate)"
        }.joined(separator: "\n")
        return """
        Runner context (derived summaries only):
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

    @available(iOS 26.0, *)
    private static func map(
        _ response: AppleCoachResponse,
        context: CoachContext
    ) -> CoachProviderResponse {
        let draft = CoachTypedResponse(
            reply: response.reply,
            intent: response.intent,
            workoutReference: response.workoutReference,
            targetWeekday: response.targetWeekday,
            targetVDOT: response.targetVDOT,
            travelStart: response.travelStart,
            travelEnd: response.travelEnd
        )
        return CoachProviderResponse(
            reply: response.reply,
            intent: CoachIntentMapper.map(draft, context: context)
        )
    }
#endif
}

/// Kept outside Foundation Models so typed-response mapping can be tested with a fake provider.
struct CoachTypedResponse: Equatable, Sendable {
    var reply: String
    var intent: String
    var workoutReference: String?
    var targetWeekday: String?
    var targetVDOT: Double?
    var travelStart: String?
    var travelEnd: String?

    init(
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

/// Repairs the narrow case where a model answers an explicit supported edit request as ordinary
/// conversation. This is intentionally conservative: it only recovers the no-parameter soreness
/// intent and never invents dates, weekdays, VDOTs, or workout references. The compiler remains the
/// authority for whether the recovered intent can actually produce a proposal.
enum CoachIntentRecovery {
    static func resolve(modelIntent: CoachIntent, message: String) -> CoachIntent {
        switch modelIntent {
        case .cutIntensity:
            // A model must not turn a soreness mention into an edit unless the user explicitly
            // asks for a training adjustment. Quick prompts bypass this recovery path and already
            // provide an explicit deterministic intent.
            guard hasSorenessMarker(in: message) else { return .answerOnly }
            return explicitIntent(in: message) ?? .answerOnly
        case .answerOnly, .clarificationRequired:
            return explicitIntent(in: message) ?? modelIntent
        default:
            return modelIntent
        }
    }

    static func reply(for intent: CoachIntent, modelReply: String) -> String {
        switch intent {
        case .cutIntensity:
            return "I’ll make this week safer by turning the next unstarted quality workout easy and reducing this week’s unstarted long run by 20%. Review the exact changes below; nothing is applied until you approve them."
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

    static func followUpReply(for message: String, proposal: CoachProposal) -> String? {
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

enum CoachIntentMapper {
    static func map(_ response: CoachTypedResponse, context: CoachContext) -> CoachIntent {
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
            let first = start
            let last = end
            var dates: [Date] = []
            var calendar = Calendar.current
            calendar.timeZone = .current
            var day = calendar.startOfDay(for: first)
            let endDay = calendar.startOfDay(for: last)
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
