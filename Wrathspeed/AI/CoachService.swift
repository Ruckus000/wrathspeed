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

/// Apple Foundation Models adapter. It owns availability and a `CoachModelClient`, nothing
/// else: the instructions, the prompt, the response schema and the intent mapping live in Core
/// (`CoachModelContract.swift`) so the evaluation harness measures the contract that ships
/// rather than a copy of it. This type has no reference to AppStore, so a model response cannot
/// mutate a plan without approval.
@MainActor
final class AppleCoachProvider: CoachProviding {
    private var client: Any?

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
        switch CoachModelClient.availability {
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

        let modelClient: CoachModelClient
        if let existing = client as? CoachModelClient {
            modelClient = existing
        } else {
            let created = CoachModelClient()
            client = created
            modelClient = created
        }

        do {
            let answer = try await modelClient.respond(to: message, context: context)
            return CoachProviderResponse(reply: answer.raw.reply, intent: answer.mapped)
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
        client = nil
    }
}
