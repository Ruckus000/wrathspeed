import SwiftUI
import WrathspeedCore

/// Plays a warm-up, drill or cool-down routine: one movement at a time, with its demo
/// loop, cue, and a countdown that advances automatically.
struct MobilityRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    let routine: MobilityRoutine

    @State private var index = 0
    @State private var remaining: Int
    @State private var running = false
    private let speech = SpeechCuePlayer()

    init(routine: MobilityRoutine) {
        self.routine = routine
        _remaining = State(initialValue: routine.items.first?.durationSeconds ?? 0)
    }

    private var current: RoutineItem? {
        routine.items.indices.contains(index) ? routine.items[index] : nil
    }

    var body: some View {
        // Scrollable for the same reason the strength player is: a 180pt clip, a display
        // countdown and a 58pt control row overrun a small phone once the cue wraps, and
        // the controls are what goes off the bottom.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let current {
                    activeView(current)
                } else {
                    finishView
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(WSColor.bgSheet.ignoresSafeArea())
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard running, remaining > 0 else { return }
            remaining -= 1
            if remaining == 0 { advance() }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(routine.title.uppercased())
                .wsType(.displayS)
                .foregroundStyle(WSColor.text)
                .accessibilityIdentifier("routine_player_title")
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                dismiss()
            } label: {
                // The glyph alone is about 9x13pt, and the frame only counts when it is on
                // the label: outside the Button it grows the layout but leaves the
                // button's own hit and accessibility frame tiny.
                Text("✕")
                    .wsType(.body, weight: .heavy)
                    .foregroundStyle(WSColor.text40)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            // The row is baseline-aligned against a 32pt display title, which clips the
            // 44pt box. Align its centre to that baseline instead.
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("routine_player_close")
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 22)
    }

    private func activeView(_ current: RoutineItem) -> some View {
        Group {
            Text("MOVEMENT \(index + 1) / \(routine.items.count)")
                .wsType(.metric)
                .foregroundStyle(WSColor.accent)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 14)
            Text(current.movement.name.uppercased())
                .wsType(.displayS)
                .foregroundStyle(WSColor.text)
                // The line limit first: minimumScaleFactor is inert without one.
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 4)
            MovementMediaView(
                movementID: current.movement.id,
                symbolName: current.movement.symbolName,
                height: 180
            )
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 12)
            Text(current.movement.cue)
                .wsType(.body)
                .foregroundStyle(WSColor.text70)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
            // Anton, not a tabular mono. Its digits are proportional -- `1` is 677/2048 em
            // against 1012 for every other digit -- so centred, the countdown pulses 7.2pt
            // per side for the one second it reads "21" and again at "11". Mono would fix
            // that but not the 10 -> 9 step, which is a digit-count change no font stops,
            // and it puts the only system face on a screen that is otherwise all Anton.
            // The strength player's rest timer is display(100) for the same reason.
            Text("\(remaining)")
                .wsType(.hero)
                .foregroundStyle(WSColor.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .accessibilityIdentifier("routine_player_timer")
                .accessibilityLabel("\(remaining) seconds remaining")
            Text("SECONDS")
                .wsType(.label, weight: .bold, tracking: 2)
                .foregroundStyle(WSColor.text50)
                .frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                WSPrimaryButton(title: running ? "PAUSE" : "START", height: 58, role: .control) {
                    running.toggle()
                    if running {
                        speech.speak(.stepStarted(current.movement.name))
                    }
                }
                .accessibilityIdentifier("routine_player_start")
                Button("NEXT →") { advance() }
                    .wsType(.label, weight: .heavy)
                    .foregroundStyle(WSColor.text50)
                    .frame(width: 110, height: 58)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("routine_player_next")
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 16)
            .padding(.bottom, WSSpace.sheetBottom)
        }
    }

    private var finishView: some View {
        VStack(alignment: .leading, spacing: 8) {
            WSEyebrow(text: "ROUTINE COMPLETE")
            Text("NICE.")
                .wsType(.displayXL)
                .foregroundStyle(WSColor.text)
                .accessibilityIdentifier("routine_player_complete")
            Text("THAT WAS THE WHOLE ROUTINE.")
                .wsType(.body, weight: .semibold)
                .foregroundStyle(WSColor.text50)
            WSOutlineButton(title: "DONE") { dismiss() }
                .padding(.top, 28)
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 44)
        .padding(.bottom, WSSpace.sheetBottom)
    }

    private func advance() {
        index += 1
        if let next = routine.items.indices.contains(index) ? routine.items[index] : nil {
            remaining = next.durationSeconds
            speech.speak(.stepStarted(next.movement.name))
        } else {
            remaining = 0
            running = false
        }
    }
}
