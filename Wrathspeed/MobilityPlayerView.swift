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
                .wsType(.body, weight: .heavy)
                .foregroundStyle(WSColor.text50)
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 12)
            // CLOSE above and the advance button below stay pinned; only the movement
            // scrolls. The instruction card can run to a few hundred points, and in a plain
            // VStack that overflow squeezed the header to nothing -- CLOSE still existed for
            // an accessibility query but had no hit area left, so tapping it did nothing.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.title.uppercased())
                        .wsType(.displayM)
                        .foregroundStyle(WSColor.text)
                        .padding(.horizontal, WSSpace.gutter)
                        .padding(.top, 16)
                    if let movement = session.movements[safe: index] {
                        // Order follows the design: position, name, clip, then the countdown,
                        // and only then the cue and the instructions. The timer sat last until
                        // a visual check caught it -- the instruction card had pushed it below
                        // the fold, and on a screen that advances by itself when the clock runs
                        // out, the clock is the one thing that must never need a scroll to see.
                        //
                        // Movements the clip library does not depict keep their symbol rather
                        // than borrowing a near-enough clip: MovementMediaView falls back on
                        // its own when the id is absent, and a nil id resolves the same way.
                        Text("\(index + 1) / \(session.movements.count)")
                            .wsType(.metric)
                            .foregroundStyle(WSColor.text40)
                            .padding(.horizontal, WSSpace.gutter)
                            .padding(.top, 14)
                        Text(movement.name.uppercased())
                            .wsType(.control, weight: .heavy)
                            .foregroundStyle(WSColor.text)
                            .padding(.horizontal, WSSpace.gutter)
                            .padding(.top, 6)
                            .accessibilityLabel("Current movement \(movement.name)")
                        MovementMediaView(
                            movementID: movement.mediaExerciseID ?? "",
                            symbolName: movement.symbolName,
                            height: 180
                        )
                        .padding(.horizontal, WSSpace.gutter)
                        .padding(.top, 14)
                        Text(timerLabel)
                            .wsType(.metricL, weight: .bold)
                            .foregroundStyle(WSColor.accent)
                            .padding(.horizontal, WSSpace.gutter)
                            .padding(.top, 14)
                            .accessibilityLabel("Time remaining \(timerLabel)")
                        Text(movement.cue)
                            .wsType(.body)
                            .foregroundStyle(WSColor.text50)
                            .padding(.horizontal, WSSpace.gutter)
                            .padding(.top, 10)
                        // A routine movement is a step that points at a catalog movement by
                        // id, and the catalog is where the instruction copy lives -- one home
                        // for the text rather than a copy per routine that references it.
                        if let described = catalogMovement(for: movement) {
                            WSInstructionCard(described)
                                .padding(.horizontal, WSSpace.gutter)
                                .padding(.top, 14)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
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

    private func catalogMovement(for movement: MobilityMovement) -> Movement? {
        guard let id = movement.mediaExerciseID else { return nil }
        return store.movementCatalog.movement(id: id)
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
