import SwiftUI
import WrathspeedCore

/// Strength preferences, on their own screen.
///
/// These five groups used to sit inline in Settings as five consecutive chip rows. The design
/// moves them behind a single `PREFERENCES` row, which is what stops Settings being one long
/// scroll where the strength block outweighed everything else on the screen.
///
/// Behaviour is unchanged -- the same `store.strengthPrefs` mutations, through the same
/// `updateStrength` path. Only the container and the controls differ.
struct StrengthPreferencesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Equipment is nine options, too many for a track and too many to leave open by default.
    /// The design collapses it behind its own summary.
    @State private var showEquipment = false

    var body: some View {
        WSScreen {
            WSBackButton(title: "← SETTINGS", accessibilityLabel: "Back to settings") { dismiss() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 8)

            Text("STRENGTH")
                .wsType(.displayL)
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)

            Text(summary)
                .wsType(.metric)
                .foregroundStyle(WSColor.text50)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 6)

            field("ABILITY", note: abilityNote) {
                track(
                    StrengthAbility.allCases,
                    label: { $0.title.uppercased() },
                    isSelected: { store.strengthPrefs.ability == $0 },
                    select: { item in updateStrength { $0.ability = item } }
                )
            }

            field("FOCUS") {
                track(
                    StrengthGoal.allCases,
                    label: { $0.title.uppercased() },
                    isSelected: { store.strengthPrefs.goal == $0 },
                    select: { item in updateStrength { $0.goal = item } }
                )
            }

            field("SESSION LENGTH", note: "Longer sessions add exercises, not sets.") {
                track(
                    [30, 45, 60],
                    label: { "\($0) MIN" },
                    isSelected: { store.strengthPrefs.durationMinutes == $0 },
                    select: { minutes in updateStrength { $0.durationMinutes = minutes } }
                )
            }

            field("TRAINING DAYS", note: "Sessions land on these days when the plan is built.") {
                track(
                    Weekday.allCases,
                    label: { $0.chipLabel.uppercased() },
                    isSelected: { store.strengthPrefs.preferredDays.contains($0) },
                    select: { day in
                        updateStrength { prefs in
                            if prefs.preferredDays.contains(day) {
                                // Never leave the plan with nowhere to put a session.
                                if prefs.preferredDays.count > 1 {
                                    prefs.preferredDays.removeAll { $0 == day }
                                }
                            } else {
                                prefs.preferredDays.append(day)
                            }
                        }
                    }
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { showEquipment.toggle() }
                } label: {
                    WSRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("EQUIPMENT")
                                .wsType(.body, weight: .bold)
                                .foregroundStyle(WSColor.text)
                            Text(equipmentSummary)
                                .wsType(.caption, weight: .medium)
                                .foregroundStyle(WSColor.text40)
                        }
                    } trailing: {
                        Text(showEquipment ? "DONE" : "CHANGE")
                            .wsType(.label, weight: .heavy, tracking: 1)
                            .foregroundStyle(WSColor.accent)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showEquipment ? "Done choosing equipment" : "Change equipment")

                if showEquipment {
                    WSChipRow(spacing: 8) {
                        ForEach(StrengthEquipment.allCases, id: \.self) { item in
                            WSChip(title: item.title, selected: store.strengthPrefs.equipment.contains(item)) {
                                updateStrength { prefs in
                                    if prefs.equipment.contains(item) {
                                        // At least one, or the planner has nothing to build from.
                                        if prefs.equipment.count > 1 { prefs.equipment.remove(item) }
                                    } else {
                                        prefs.equipment.insert(item)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 24)

            Spacer(minLength: 34)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Pieces

    private func field<Content: View>(
        _ title: String,
        note: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .wsType(.body, weight: .bold)
                .foregroundStyle(WSColor.text)
                // Hidden here and restated on the control, so VoiceOver names the group once
                // and attaches it to the thing it names.
                .accessibilityHidden(true)
            content()
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title.capitalized)
            if let note {
                Text(note)
                    .wsType(.caption, weight: .medium)
                    .foregroundStyle(WSColor.text40)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 24)
    }

    private func track<Value: Hashable>(
        _ options: [Value],
        label: @escaping (Value) -> String,
        isSelected: @escaping (Value) -> Bool,
        select: @escaping (Value) -> Void
    ) -> some View {
        WSSegmentedControl(
            options: options,
            label: label,
            isSelected: isSelected,
            select: select,
            ground: WSColor.bgSheet,
            cornerRadius: 8,
            bordered: true
        )
    }

    private var summary: String {
        let prefs = store.strengthPrefs
        return "\(prefs.sessionsPerWeek) SESSIONS / WEEK · \(prefs.durationMinutes) MIN"
    }

    private var abilityNote: String {
        "Sets how many exercises a session carries and how it progresses."
    }

    private var equipmentSummary: String {
        let titles = StrengthEquipment.allCases
            .filter { store.strengthPrefs.equipment.contains($0) }
            .map { $0.title.uppercased() }
        return titles.isEmpty ? "NONE SELECTED" : titles.joined(separator: " · ")
    }

    private func updateStrength(_ mutate: (inout StrengthPreferences) -> Void) {
        var prefs = store.strengthPrefs
        mutate(&prefs)
        store.updateStrengthPreferences(prefs)
    }
}
