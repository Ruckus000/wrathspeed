import SwiftUI
import WrathspeedCore

/// One row of the library. Strength exercises and mobility movements carry the same fields
/// under different names, so they are normalised here rather than building the row and its
/// destination twice.
struct MovementLibraryEntry: Identifiable, MovementInstructions {
    let id: String
    let name: String
    let symbolName: String
    let cue: String
    let meta: String
    var howToDoIt: [String]?
    var shouldFeel: String?
    var commonMistake: String?
    var easier: String?
}

/// Browsable index of every movement the app knows, so a demo clip is reachable even
/// when the movement is not in today's routine.
struct MovementLibraryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WSScreen {
            WSBackButton(title: "← SETTINGS", accessibilityLabel: "Back to settings") { dismiss() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 8)

            Text("MOVEMENT\nLIBRARY")
                .wsType(.displayM)
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
                .accessibilityIdentifier("movement_library_title")
                .accessibilityAddTraits(.isHeader)

            Text(countHint)
                .wsType(.metric)
                .foregroundStyle(WSColor.text50)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 8)

            ForEach(sections, id: \.title) { section in
                Text(section.title.uppercased())
                    .wsType(.metricS, tracking: 2)
                    .foregroundStyle(WSColor.text35)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 24)
                // The design groups these rows in a card rather than letting them run flat
                // against the screen, which is what tells you where one section ends.
                WSListCard {
                    ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink {
                            MovementDetailView(entry: entry)
                        } label: {
                            WSListRow(
                                title: entry.name.uppercased(),
                                hint: entry.meta.uppercased(),
                                showDivider: index < section.entries.count - 1
                            ) {
                                Text("›")
                                    .wsType(.control, weight: .heavy)
                                    .foregroundStyle(WSColor.text40)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("movement_row_\(entry.id)")
                    }
                }
                .padding(.top, 8)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var countHint: String { Self.countHint(for: store) }

    /// The one place this sentence is built. Settings shows the same count on the row that
    /// leads here, and computing it separately from the catalogues let the two disagree the
    /// moment the library gained any filtering -- it counts what this screen will actually
    /// list, not what the catalogues hold.
    static func countHint(for store: AppStore) -> String {
        let strength = store.strengthCatalog.exercises.count
        let movements = MovementPhase.allCases.reduce(0) { $0 + store.movementCatalog.inPhase($1).count }
        return "\(strength + movements) MOVEMENTS, WITH DEMOS"
    }

    /// Strength first, then the mobility phases in their catalog order. Empty groups are
    /// dropped so an unreadable catalog shows nothing rather than a bare heading.
    private var sections: [(title: String, entries: [MovementLibraryEntry])] {
        var result: [(title: String, entries: [MovementLibraryEntry])] = []

        let strength = store.strengthCatalog.exercises.map {
            MovementLibraryEntry(
                id: $0.id,
                name: $0.name,
                symbolName: $0.symbolName,
                cue: $0.cue,
                meta: "\($0.defaultReps) reps",
                howToDoIt: $0.howToDoIt,
                shouldFeel: $0.shouldFeel,
                commonMistake: $0.commonMistake,
                easier: $0.easier
            )
        }
        if !strength.isEmpty {
            result.append((title: "Strength", entries: strength))
        }

        for phase in MovementPhase.allCases {
            let entries = store.movementCatalog.inPhase(phase).map {
                MovementLibraryEntry(
                    id: $0.id,
                    name: $0.name,
                    symbolName: $0.symbolName,
                    cue: $0.cue,
                    meta: "\($0.durationSeconds)s · \($0.bodyArea)",
                    howToDoIt: $0.howToDoIt,
                    shouldFeel: $0.shouldFeel,
                    commonMistake: $0.commonMistake,
                    easier: $0.easier
                )
            }
            if !entries.isEmpty {
                result.append((title: phase.title, entries: entries))
            }
        }
        return result
    }
}

struct MovementDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: MovementLibraryEntry

    var body: some View {
        WSScreen {
            WSBackButton(title: "← LIBRARY", accessibilityLabel: "Back to movement library") { dismiss() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 8)

            Text(entry.name.uppercased())
                .wsType(.displayM)
                .foregroundStyle(WSColor.text)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
                .accessibilityIdentifier("movement_detail_\(entry.id)")
                .accessibilityAddTraits(.isHeader)

            Text(entry.meta.uppercased())
                .wsType(.metric, weight: .medium)
                .foregroundStyle(WSColor.text45)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 10)

            MovementMediaView(
                movementID: entry.id,
                symbolName: entry.symbolName,
                height: 280
            )
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 20)

            // The cue gets card chrome here, matching the instruction block beneath it, so
            // the screen reads as a stack of answers rather than a caption and then a card.
            WSLabeledCard(label: "CUE", text: entry.cue)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 20)

            // Renders nothing until this movement has copy, so the screen is correct while
            // the catalog is still being filled in.
            WSInstructionCard(entry)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 14)

            Spacer(minLength: 34)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
