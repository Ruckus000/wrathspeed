import SwiftUI
import WrathspeedCore

@MainActor
struct CoachView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let provider: any CoachProviding
    @State private var input = ""
    @State private var messages: [CoachMessage] = []
    @State private var proposal: CoachProposal?
    @State private var showHealthSafety = false
    @State private var isThinking = false
    @State private var actionError: String?

    init(provider: any CoachProviding) {
        self.provider = provider
    }

    init() {
        self.provider = AppleCoachProvider()
    }

    var body: some View {
        WSScreen {
            WSRow(alignment: .firstTextBaseline) {
                WSBackButton(title: "← PLAN", accessibilityLabel: "Back to plan") { dismiss() }
            } trailing: {
                Button(action: newChat) {
                    Text("NEW CHAT")
                        .wsType(.label, weight: .heavy, tracking: 1)
                        .foregroundStyle(WSColor.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach_new_chat")
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)

            WSEyebrow(text: "AI COACH")
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 18)
            Text("COACH")
                .wsType(.displayL)
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 4)
            Text("Ask for a change. Review the exact plan diff. Approve it when it looks right.")
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text45)
                .lineSpacing(3)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 8)

            quickPrompts
                .padding(.top, 18)

            if !provider.availability.isAvailable {
                unavailableCard
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 16)
            }

            conversation
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 18)

            if let proposal {
                proposalCard(proposal)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 18)
            }

            // The one screen where a runner types about pain to a model, and until now the one
            // screen with no health statement. `answerOnly` shows the model's own words.
            healthCaveat
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 16)

            composer
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(WSColor.bg.ignoresSafeArea())
        .sheet(isPresented: $showHealthSafety) {
            HealthSafetyView(backTitle: "← COACH", backAccessibilityLabel: "Back to coach")
        }
    }

    private var healthCaveat: some View {
        WSRow {
            Text("Not medical advice. If anything is sharp, stop.")
                .wsType(.caption, weight: .medium)
                .foregroundStyle(WSColor.text50)
                .fixedSize(horizontal: false, vertical: true)
        } trailing: {
            // Frame and hit shape on the label, not the button. On the button, XCUITest measured
            // this at 11pt -- the caption's text height -- because the button's accessibility
            // frame is its label's. Same trap TodayView documents.
            Button {
                showHealthSafety = true
            } label: {
                Text("HEALTH AND SAFETY")
                    .wsType(.caption, weight: .heavy, tracking: 1)
                    .foregroundStyle(WSColor.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coach_health_safety")
        }
    }

    private var quickPrompts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK PROMPTS")
                .wsType(.metricS, tracking: 1.5)
                .foregroundStyle(WSColor.text40)
            WSFlowLayout(spacing: 8, rowSpacing: 8) {
                quickButton(title: "I’M SORE", identifier: "coach_quick_soreness", message: "I’m sore. Adjust this week safely.") {
                    deterministicOrSend(.cutIntensity, message: "I’m sore. Adjust this week safely.")
                }
                quickButton(title: "TRAVEL DATES", identifier: "coach_quick_travel", message: "I’m traveling. Help reshape my plan around exact dates.") {
                    deterministicOrSend(.reshapeForTravel(travelDates: []), message: "I’m traveling. Help reshape my plan around exact dates.")
                }
                quickButton(title: "FASTER PACES", identifier: "coach_quick_faster", message: "My recent pace is faster. Update future paces.") {
                    let target = (store.profile?.vdot ?? 0) * (1 + CoachPlanRules.vdotChangeLimit)
                    deterministicOrSend(.retargetVDOT(target: target), message: "My recent pace is faster. Update future paces.")
                }
                quickButton(title: "MOVE LONG RUN", identifier: "coach_quick_long_run", message: "Move my long run to another available weekday.") {
                    sendMessage("Move my long run to another available weekday.")
                }
                quickButton(title: "TREADMILL", identifier: "coach_quick_treadmill", message: "Move a specific workout indoors.") {
                    sendMessage("Move a specific workout indoors.")
                }
            }
        }
        .padding(.horizontal, WSSpace.gutter)
    }

    private func quickButton(
        title: String,
        identifier: String,
        message: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            WSPillLabel(title: title)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(message)
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONVERSATIONAL COACHING UNAVAILABLE")
                .wsType(.label, weight: .heavy, tracking: 1)
                .foregroundStyle(WSColor.accent)
            Text(provider.availability.explanation)
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text70)
                .lineSpacing(3)
            Text("Use the deterministic quick actions above to preview supported edits.")
                .wsType(.metric)
                .foregroundStyle(WSColor.text40)
        }
        .padding(16)
        .background(WSColor.bgInset, in: RoundedRectangle(cornerRadius: WSRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: WSRadius.card, style: .continuous).stroke(WSColor.border, lineWidth: 1))
        .accessibilityIdentifier("coach_unavailable_card")
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(messages) { message in
                HStack {
                    if message.role == .coach { Spacer(minLength: 28) }
                    Text(message.text)
                        .wsType(.body, weight: .medium)
                        .foregroundStyle(message.role == .coach ? WSColor.text70 : WSColor.text)
                        .padding(12)
                        .background(message.role == .coach ? WSColor.surface2 : WSColor.accentTint, in: RoundedRectangle(cornerRadius: WSRadius.card, style: .continuous))
                    if message.role == .user { Spacer(minLength: 28) }
                }
            }
            if isThinking {
                HStack(spacing: 8) {
                    ProgressView().tint(WSColor.accent)
                    Text("COACH IS THINKING…")
                        .wsType(.metricS, tracking: 1)
                        .foregroundStyle(WSColor.text40)
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("coach_thinking")
            }
            if let actionError {
                Text(actionError)
                    .wsType(.metric)
                    .foregroundStyle(WSColor.accent)
                    .accessibilityIdentifier("coach_error")
            }
        }
    }

    private func proposalCard(_ proposal: CoachProposal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WSRow(alignment: .firstTextBaseline) {
                WSEyebrow(text: "PROPOSED CHANGE")
            } trailing: {
                Text("\(proposal.changes.count) EDITS")
                    .wsType(.metricS, tracking: 1)
                    .foregroundStyle(WSColor.text40)
            }
            Text(proposal.title.uppercased())
                .wsType(.displayS)
                .foregroundStyle(WSColor.text)
                .padding(.top, 8)
            if !proposal.rationale.isEmpty {
                Text(proposal.rationale)
                    .wsType(.body, weight: .medium)
                    .foregroundStyle(WSColor.text70)
                    .lineSpacing(3)
                    .padding(.top, 8)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(proposal.changes) { change in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(change.reference.uppercased())
                            .wsType(.metricS, tracking: 1)
                            .foregroundStyle(WSColor.accent)
                        Text(change.before)
                            .wsType(.metric)
                            .foregroundStyle(WSColor.text40)
                            .strikethrough(change.kind == .removed)
                        Text("→ \(change.after)")
                            .wsType(.body, weight: .heavy)
                            .foregroundStyle(WSColor.text)
                    }
                    .padding(.bottom, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
                }
            }
            .padding(.top, 18)

            if !proposal.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CHECK BEFORE APPLYING")
                        .wsType(.metricS, tracking: 1.2)
                        .foregroundStyle(WSColor.accent)
                    ForEach(proposal.warnings) { warning in
                        Text("• \(warning.message)")
                            .wsType(.metric)
                            .foregroundStyle(WSColor.text70)
                    }
                }
                .padding(.top, 16)
            }

            if proposal.isApplicable {
                WSPrimaryButton(
                    title: proposal.softWarnings.isEmpty ? "APPLY" : "APPLY WITH WARNING",
                    height: 54,
                    role: .control,
                    fill: proposal.softWarnings.isEmpty ? WSColor.accent : WSColor.destructive
                ) {
                    apply(proposal)
                }
                .padding(.top, 18)
                .accessibilityIdentifier(proposal.softWarnings.isEmpty ? "coach_apply" : "coach_apply_with_warning")
            }
            WSOutlineButton(title: "KEEP AS IS", height: 48) {
                self.proposal = nil
            }
            .padding(.top, 10)
            .accessibilityIdentifier("coach_keep_as_is")
        }
        .padding(16)
        .background(WSColor.bgSheet, in: RoundedRectangle(cornerRadius: WSRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: WSRadius.card, style: .continuous).stroke(WSColor.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach_proposal_card")
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("ASK THE COACH", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(WSColor.surface2, in: RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous))
                .disabled(!provider.availability.isAvailable)
                .accessibilityIdentifier("coach_input")
                .onSubmit { sendMessage(input) }
            Button {
                sendMessage(input)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(WSColor.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!provider.availability.isAvailable || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
            .accessibilityLabel("Send to coach")
            .accessibilityIdentifier("coach_send")
        }
        .padding(.bottom, 4)
    }

    private func sendMessage(_ raw: String) {
        let message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        guard provider.availability.isAvailable else {
            deterministicFallback(for: message)
            input = ""
            return
        }
        input = ""
        messages.append(CoachMessage(role: .user, text: message))

        if let proposal, let followUp = CoachIntentRecovery.followUpReply(for: message, proposal: proposal) {
            messages.append(CoachMessage(role: .coach, text: followUp))
            return
        }

        isThinking = true
        Task { @MainActor in
            defer { isThinking = false }
            guard let context = store.coachContext() else {
                messages.append(CoachMessage(role: .coach, text: "Finish setting up your plan before asking me to edit it."))
                return
            }
            do {
                let response = try await provider.respond(to: message, context: context)
                let intent = CoachIntentRecovery.resolve(modelIntent: response.intent, message: message)
                messages.append(CoachMessage(role: .coach, text: CoachIntentRecovery.reply(for: intent, modelReply: response.reply)))
                switch intent {
                case .clarificationRequired, .answerOnly:
                    break
                default:
                    proposal = store.previewCoachIntent(intent)
                }
            } catch {
                messages.append(CoachMessage(role: .coach, text: (error as? LocalizedError)?.errorDescription ?? "The coach couldn’t respond."))
            }
        }
    }

    private func deterministicOrSend(_ intent: CoachIntent, message: String) {
        // Quick prompts are explicit product actions, not open-ended questions. Keep them
        // deterministic even when Apple Intelligence is available so a generic model reply
        // cannot swallow the action the user just selected. Free-form text still uses the model
        // through sendMessage(_:), and every resulting intent is compiled and approved separately.
        input = ""
        messages.append(CoachMessage(role: .user, text: message))
        deterministicFallback(intent: intent)
    }

    private func deterministicFallback(for message: String) {
        input = ""
        messages.append(CoachMessage(role: .user, text: message))
        let normalized = message.lowercased()
        // Same gate the model path uses. A bare `contains("sore")` here turned "I'm not sore"
        // into a proposal while `CoachIntentRecovery` correctly refused it -- two fallbacks that
        // disagreed. `resolve` with `.answerOnly` yields `.cutIntensity` only when the message
        // carries a soreness marker, an explicit edit request, and no opt-out.
        if CoachIntentRecovery.resolve(modelIntent: .answerOnly, message: message) == .cutIntensity {
            deterministicFallback(intent: .cutIntensity)
        } else if normalized.contains("travel") {
            messages.append(CoachMessage(role: .coach, text: "Tell me the exact travel start and end dates first."))
        } else if normalized.contains("treadmill") || normalized.contains("indoors") || normalized.contains("weather") {
            messages.append(CoachMessage(role: .coach, text: "Which named workout should move indoors?"))
        } else if normalized.contains("long run") {
            messages.append(CoachMessage(role: .coach, text: "Tell me the available weekday for the long run."))
        } else {
            messages.append(CoachMessage(role: .coach, text: "Conversational coaching is unavailable here. Use one of the quick actions above."))
        }
    }

    private func deterministicFallback(intent: CoachIntent) {
        switch intent {
        case let .reshapeForTravel(dates) where dates.isEmpty:
            messages.append(CoachMessage(role: .coach, text: "Tell me the exact travel start and end dates first."))
        case .moveWorkoutIndoors:
            messages.append(CoachMessage(role: .coach, text: "Which named workout should move indoors?"))
        case .moveLongRun:
            messages.append(CoachMessage(role: .coach, text: "Tell me the available weekday for the long run."))
        default:
            messages.append(CoachMessage(
                role: .coach,
                text: CoachIntentRecovery.reply(for: intent, modelReply: "")
            ))
            let compiled = store.previewCoachIntent(intent)
            proposal = compiled
        }
    }

    private func apply(_ proposal: CoachProposal) {
        switch store.applyCoachProposal(proposal) {
        case .applied:
            dismiss()
        case let .rejected(reason):
            actionError = reason
            self.proposal = nil
        }
    }

    private func newChat() {
        provider.reset()
        input = ""
        messages = []
        proposal = nil
        actionError = nil
    }
}

private struct CoachMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case coach
    }

    let id = UUID()
    let role: Role
    let text: String
}
