import SwiftUI
import WrathspeedCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            Form {
                if let profile = store.profile {
                    Section("Units") {
                        Picker("Distance", selection: unitBinding) {
                            Text("Kilometers").tag(DistanceUnit.kilometers)
                            Text("Miles").tag(DistanceUnit.miles)
                        }
                    }
                    Section("Reference") {
                        NavigationLink {
                            MovementLibraryView()
                        } label: {
                            Label("Movement library", systemImage: "figure.flexibility")
                        }
                    }
                    Section("Coaching") {
                        Toggle("Audio cues", isOn: Binding(
                            get: { store.cuesEnabled },
                            set: {
                                store.cuesEnabled = $0
                                store.session.cuesEnabled = $0
                                store.save()
                            }
                        ))
                    }
                    Section("Running profile") {
                        LabeledContent("Ability", value: profile.ability.rawValue.capitalized)
                        LabeledContent("VDOT", value: profile.vdot.formatted(.number.precision(.fractionLength(1))))
                        LabeledContent("Days / week", value: "\(profile.daysPerWeek)")
                    }
                    Section("Strength") {
                        Picker("Goal", selection: strengthGoalBinding) {
                            ForEach(StrengthGoal.allCases, id: \.self) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        Stepper("Sessions: \(store.strengthPrefs.sessionsPerWeek)", value: strengthCountBinding, in: 1...4)
                        equipmentToggles
                    }
                    Section {
                        Button("Rebuild future weeks") {
                            store.regeneratePlan()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var unitBinding: Binding<DistanceUnit> {
        Binding(
            get: { store.profile?.unit ?? .kilometers },
            set: { newValue in
                guard var profile = store.profile else { return }
                profile.unit = newValue
                store.profile = profile
                store.regeneratePlan(profile: profile)
            }
        )
    }

    private var strengthGoalBinding: Binding<StrengthGoal> {
        Binding(
            get: { store.strengthPrefs.goal },
            set: { store.strengthPrefs.goal = $0 }
        )
    }

    private var strengthCountBinding: Binding<Int> {
        Binding(
            get: { store.strengthPrefs.sessionsPerWeek },
            set: { store.strengthPrefs.sessionsPerWeek = $0 }
        )
    }

    private var equipmentToggles: some View {
        ForEach(StrengthEquipment.allCases, id: \.self) { item in
            Toggle(item.title, isOn: Binding(
                get: { store.strengthPrefs.equipment.contains(item) },
                set: { on in
                    if on {
                        store.strengthPrefs.equipment.insert(item)
                    } else {
                        store.strengthPrefs.equipment.remove(item)
                    }
                }
            ))
        }
    }
}
