import SwiftUI
import WrathspeedCore

struct MobilityPlayerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: MobilitySession
    @State private var index = 0
    @State private var remaining: TimeInterval
    @State private var timer: Timer?
    @State private var startedAt = Date()

    init(session: MobilitySession) {
        self.session = session
        _remaining = State(initialValue: session.movements.first?.durationSeconds ?? 30)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("← CLOSE") { dismiss() }
                    .font(WSFont.ui(13, weight: .heavy))
                    .foregroundStyle(WSColor.text50)
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
                Text(movement.name.uppercased())
                    .font(WSFont.ui(18, weight: .heavy))
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 12)
                    .accessibilityLabel("Current movement \(movement.name)")
                Text(movement.cue)
                    .font(WSFont.ui(15))
                    .foregroundStyle(WSColor.text50)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 8)
                Text(timerLabel)
                    .font(WSFont.mono(24, weight: .bold))
                    .foregroundStyle(WSColor.accent)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 20)
                    .accessibilityLabel("Time remaining \(timerLabel)")
            }
            Spacer()
            WSPrimaryButton(title: index + 1 >= session.movements.count ? "FINISH" : "NEXT") {
                advance()
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.bottom, 40)
        }
        .background(WSColor.bg.ignoresSafeArea())
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private var timerLabel: String {
        let total = Int(remaining.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            guard remaining > 0 else { return }
            remaining -= 1
            if remaining <= 0 { advance() }
        }
    }

    private func advance() {
        if index + 1 >= session.movements.count {
            let result = MobilitySessionResult(
                sessionID: session.id,
                startedAt: startedAt,
                endedAt: Date(),
                completedMovementIDs: session.movements.map(\.id)
            )
            store.recordMobilityResult(result)
            dismiss()
            return
        }
        index += 1
        remaining = session.movements[index].durationSeconds ?? 30
        startTimer()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
