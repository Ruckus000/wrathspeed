import SwiftUI
import WrathspeedCore

/// One row of the library. Strength exercises and mobility movements carry the same fields
/// under different names, so they are normalised here rather than building the row and its
/// destination twice.
struct MovementLibraryEntry: Identifiable {
    let id: String
    let name: String
    let symbolName: String
    let cue: String
    let meta: String
}

/// Browsable index of every movement the app knows, so a demo clip is reachable even
/// when the movement is not in today's routine.
struct MovementLibraryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WSScreen {
            Button {
                dismiss()
            } label: {
                Text("← SETTINGS")
                    .wsType(.body, weight: .heavy, tracking: 1)
                    .foregroundStyle(WSColor.text50)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)
            .accessibilityLabel("Back to settings")

            Text("MOVEMENT\nLIBRARY")
                .wsType(.displayM)
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
                .accessibilityIdentifier("movement_library_title")
                .accessibilityAddTraits(.isHeader)

            ForEach(sections, id: \.title) { section in
                Text(section.title.uppercased())
                    .wsType(.metricS, tracking: 1.5)
                    .foregroundStyle(WSColor.text40)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 22)
                VStack(spacing: 0) {
                    ForEach(section.entries) { entry in
                        NavigationLink {
                            MovementDetailView(entry: entry)
                        } label: {
                            row(entry)
                        }
                        .accessibilityIdentifier("movement_row_\(entry.id)")
                    }
                }
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 8)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func row(_ entry: MovementLibraryEntry) -> some View {
        HStack {
            Text(entry.name.uppercased())
                .wsType(.body, weight: .heavy)
                .foregroundStyle(WSColor.text)
            Spacer()
            Text("›")
                .wsType(.body, weight: .heavy)
                .foregroundStyle(WSColor.text40)
        }
        .padding(.vertical, 11)
        // Rows sit flush against each other, so anything under 44pt means an edge tap
        // opens the neighbouring movement. The stock List gave this for free.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
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
                meta: "\($0.defaultReps) reps"
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
                    meta: "\($0.durationSeconds)s · \($0.bodyArea)"
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
            Button {
                dismiss()
            } label: {
                Text("← LIBRARY")
                    .wsType(.body, weight: .heavy, tracking: 1)
                    .foregroundStyle(WSColor.text50)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)
            .accessibilityLabel("Back to movement library")

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

            Text(entry.cue)
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text70)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 20)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
