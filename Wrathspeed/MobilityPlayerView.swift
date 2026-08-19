import SwiftUI
import WrathspeedCore

struct MobilityPlayerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let session: MobilitySession
    @State private var resultID = UUID()
    @State private var index = 0
    @State private var remaining: TimeInterval
    @State private var timer: Timer?
    @State private var startedAt = Date()
    @State private var completedMovementIDs: [String] = []

    init(session: MobilitySession) {
        self.session = session
        _remaining = State(initialValue: session.movements.first?.durationSeconds ?? 30)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("← CLOSE") {
                    do {
                        try persistProgress(force: true)
                        dismiss()
                    } catch {}
                }
                .font(WSFont.ui(13, weight: .heavy))
                .foregroundStyle(WSColor.text50)
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 12)
            Text(session.title.uppercased())
                .font(WSFont.display(40))
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 16)
            if let movement = session.movements[safe: index] {
                Image(systemName: movement.symbolName)
                    .font(.system(size: 56))
                    .foregroundStyle(WSColor.accent)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(movement.name.uppercased())
                        .font(WSFont.ui(18, weight: .heavy))
                    Text(movement.cue)
                        .font(WSFont.ui(15))
                        .foregroundStyle(WSColor.text50)
                }
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Current movement \(movement.name). \(movement.cue)")
                Text(timerLabel)
                    .font(WSFont.mono(24, weight: .bold))
                    .foregroundStyle(WSColor.accent)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 20)
                    .accessibilityLabel("Time remaining \(timerLabel)")
                Text("\(index + 1) / \(session.movements.count)")
                    .font(WSFont.mono(11))
                    .foregroundStyle(WSColor.text40)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 8)
            }
            Spacer()
            WSPrimaryButton(title: index + 1 >= session.movements.count ? "FINISH" : "NEXT") {
                advance()
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.bottom, 40)
        }
        .background(WSColor.bg.ignoresSafeArea())
        .onAppear {
            restoreOrStart()
            startTimer()
        }
        .onDisappear { timer?.invalidate() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                try? persistProgress(force: true)
            }
        }
        .overlay {
            if let message = store.errorMessage {
                WSAlert(message: message) { store.errorMessage = nil }
            }
        }
    }

    private var timerLabel: String {
        let total = Int(remaining.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func restoreOrStart() {
        if let existing = GuidedSessionPolicy.inProgressMobility(routineID: session.routineID, in: store.guidedMobilityResults) {
            resultID = existing.id
            startedAt = existing.startedAt
            completedMovementIDs = existing.completedMovementIDs
            if let progress = existing.progress {
                index = min(progress.movementIndex, max(session.movements.count - 1, 0))
                remaining = progress.remainingSeconds
            } else {
                index = min(completedMovementIDs.count, max(session.movements.count - 1, 0))
                remaining = session.movements[safe: index]?.durationSeconds ?? 30
            }
            return
        }
        startedAt = Date()
        resultID = UUID()
        completedMovementIDs = []
        index = 0
        remaining = session.movements.first?.durationSeconds ?? 30
        try? persistProgress(force: true)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                guard remaining > 0 else { return }
                remaining -= 1
                if remaining <= 0 { advance() }
            }
        }
    }

    private func advance() {
        guard let movement = session.movements[safe: index] else { return }
        if !completedMovementIDs.contains(movement.id) {
            completedMovementIDs.append(movement.id)
        }
        if index + 1 >= session.movements.count {
            completeSession()
            return
        }
        index += 1
        remaining = session.movements[index].durationSeconds ?? 30
        try? persistProgress(force: true)
        startTimer()
    }

    private func completeSession() {
        let result = MobilitySessionResult(
            id: resultID,
            sessionID: session.id,
            startedAt: startedAt,
            endedAt: Date(),
            completedMovementIDs: session.movements.map(\.id),
            routineID: session.routineID,
            lifecycle: .completed,
            progress: nil
        )
        do {
            try store.recordMobilityResult(result)
            dismiss()
        } catch {}
    }

    private func persistProgress(force: Bool = false) throws {
        guard force else { return }
        let result = MobilitySessionResult(
            id: resultID,
            sessionID: session.id,
            startedAt: startedAt,
            endedAt: Date(),
            completedMovementIDs: completedMovementIDs,
            routineID: session.routineID,
            lifecycle: .inProgress,
            progress: MobilitySessionProgress(movementIndex: index, remainingSeconds: remaining)
        )
        try store.recordMobilityResult(result)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
