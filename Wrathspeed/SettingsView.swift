import SwiftUI
import UIKit
import WrathspeedCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            WSScreen {
                Text("SETTINGS")
                    .font(WSFont.display(44))
                    .foregroundStyle(WSColor.text)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 10)
                section("LIVE RUN METRICS") {
                    HStack(spacing: 8) {
                        ForEach(LiveMetric.allCases, id: \.self) { metric in
                            WSChip(title: metric.chipLabel, selected: store.liveMetrics.contains(metric)) {
                                store.toggleLiveMetric(metric)
                            }
                        }
                    }
                }
                section("DATA DENSITY") {
                    HStack(spacing: 8) {
                        ForEach(DataDensity.allCases, id: \.self) { density in
                            WSChip(title: density.title, selected: store.dataDensity == density) {
                                store.setDataDensity(density)
                            }
                        }
                    }
                }
                section("COACHING") {
                    Button {
                        store.cuesEnabled.toggle()
                        store.session.cuesEnabled = store.cuesEnabled
                        store.save()
                    } label: {
                        HStack {
                            Text("AUDIO CUES")
                                .font(WSFont.ui(14, weight: .heavy))
                                .foregroundStyle(WSColor.text)
                            Spacer()
                            Text(store.cuesEnabled ? "ON" : "OFF")
                                .font(WSFont.ui(12, weight: .heavy))
                                .tracking(1)
                                .foregroundStyle(store.cuesEnabled ? .white : WSColor.text)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(store.cuesEnabled ? WSColor.accent : Color.clear, in: Capsule())
                                .overlay(Capsule().stroke(store.cuesEnabled ? WSColor.accent : WSColor.border, lineWidth: 1.5))
                        }
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 8) {
                        ForEach(CueStyle.allCases, id: \.self) { style in
                            WSChip(title: style.title, selected: store.cueStyle == style) {
                                store.setCueStyle(style)
                            }
                        }
                    }
                    .padding(.top, 14)
                }
                section("UNITS") {
                    HStack(spacing: 8) {
                        WSChip(title: "Miles", selected: store.unit == .miles) { setUnit(.miles) }
                        WSChip(title: "Kilometers", selected: store.unit == .kilometers) { setUnit(.kilometers) }
                    }
                }
                section("CONTENT") {
                    NavigationLink {
                        MovementLibraryView()
                    } label: {
                        Text("MOVEMENT LIBRARY ›")
                            .font(WSFont.ui(14, weight: .heavy))
                            .foregroundStyle(WSColor.text)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("settings.movementLibrary")
                    NavigationLink {
                        ContentLicensesView()
                    } label: {
                        Text("CONTENT LICENSES ›")
                            .font(WSFont.ui(14, weight: .heavy))
                            .foregroundStyle(WSColor.text)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
                if store.n100 != nil {
                    section("PLAN ADJUSTMENT") {
                        Button("END NOT FEELING 100%") {
                            store.endNotFeeling100()
                        }
                        .font(WSFont.ui(14, weight: .heavy))
                        .foregroundStyle(WSColor.accent)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
                section("DIAGNOSTICS") {
                    Button("EXPORT REDACTED DIAGNOSTICS") {
                        if let data = try? DiagnosticsExporter.exportJSON(from: store),
                           let json = String(data: data, encoding: .utf8) {
                            UIPasteboard.general.string = json
                            store.showToast("DIAGNOSTICS COPIED")
                        }
                    }
                    .font(WSFont.ui(14, weight: .heavy))
                    .foregroundStyle(WSColor.accent)
                    .accessibilityLabel("Export redacted diagnostics to clipboard")
                    Text("Includes app version, schema version, and non-sensitive counts only.")
                        .font(WSFont.mono(11))
                        .foregroundStyle(WSColor.text40)
                        .padding(.top, 8)
                }
                section("RUNNING PROFILE") {
                    if let profile = store.profile {
                        WSHairlineRow(label: "ABILITY", value: profile.ability.title.uppercased())
                        NavigationLink {
                            PaceZonesView()
                        } label: {
                            HStack {
                                Text("VDOT · PACE ZONES")
                                    .font(WSFont.ui(13, weight: .bold))
                                    .foregroundStyle(Color.white.opacity(0.6))
                                Spacer()
                                Text("\(WSFormat.vdot(profile.vdot)) ›")
                                    .font(WSFont.mono(13, weight: .bold))
                                    .foregroundStyle(WSColor.accent)
                            }
                            .padding(.vertical, 12)
                        }
                        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
                        WSHairlineRow(label: "DAYS / WEEK", value: "\(profile.daysPerWeek)", showDivider: false)
                    }
                }
                section("STRENGTH") {
                    chipWrap(StrengthAbility.allCases.map(\.title), selected: store.strengthPrefs.ability.title) { title in
                        if let item = StrengthAbility.allCases.first(where: { $0.title == title }) {
                            updateStrength { $0.ability = item }
                        }
                    }
                    chipWrap(StrengthGoal.allCases.map(\.title), selected: store.strengthPrefs.goal.title) { title in
                        if let item = StrengthGoal.allCases.first(where: { $0.title == title }) {
                            updateStrength { $0.goal = item }
                        }
                    }
                    .padding(.top, 10)
                    HStack(spacing: 8) {
                        ForEach([30, 45, 60], id: \.self) { minutes in
                            WSChip(title: "\(minutes) min", selected: store.strengthPrefs.durationMinutes == minutes) {
                                updateStrength { $0.durationMinutes = minutes }
                            }
                        }
                    }
                    .padding(.top, 10)
                    HStack(spacing: 6) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            WSChip(title: day.chipLabel, selected: store.strengthPrefs.preferredDays.contains(day)) {
                                updateStrength { prefs in
                                    if prefs.preferredDays.contains(day) {
                                        if prefs.preferredDays.count > 1 {
                                            prefs.preferredDays.removeAll { $0 == day }
                                        }
                                    } else {
                                        prefs.preferredDays.append(day)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                    chipWrap(StrengthEquipment.allCases.map(\.title), selected: "") { title in
                        if let item = StrengthEquipment.allCases.first(where: { $0.title == title }) {
                            updateStrength { prefs in
                                if prefs.equipment.contains(item) {
                                    if prefs.equipment.count > 1 { prefs.equipment.remove(item) }
                                } else {
                                    prefs.equipment.insert(item)
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                WSOutlineButton(title: "REBUILD FUTURE WEEKS") {
                    store.regeneratePlan()
                    store.showToast("FUTURE WEEKS REBUILT")
                }
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(WSFont.mono(10))
                .tracking(1.5)
                .foregroundStyle(WSColor.accent)
            content()
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 22)
    }

    private func chipWrap(_ titles: [String], selected: String, action: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(titles, id: \.self) { title in
                let isOn: Bool = {
                    if selected.isEmpty {
                        return StrengthEquipment.allCases.first { $0.title == title }.map { store.strengthPrefs.equipment.contains($0) } ?? false
                    }
                    return title == selected
                }()
                WSChip(title: title, selected: isOn) { action(title) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setUnit(_ unit: DistanceUnit) {
        guard var profile = store.profile else { return }
        profile.unit = unit
        store.profile = profile
        store.regeneratePlan(profile: profile)
    }

    private func updateStrength(_ mutate: (inout StrengthPreferences) -> Void) {
        var preferences = store.strengthPrefs
        mutate(&preferences)
        store.updateStrengthPreferences(preferences)
    }
}

struct PaceZonesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let zoneOrder: [PaceZone] = [.easy, .recovery, .marathon, .threshold, .interval, .repetition]

    var body: some View {
        WSScreen {
            Button("← SETTINGS") { dismiss() }
                .font(WSFont.ui(13, weight: .heavy))
                .tracking(1)
                .foregroundStyle(WSColor.text50)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 8)
            WSEyebrow(text: "VDOT \(WSFormat.vdot(store.profile?.vdot ?? 0))")
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 18)
            Text("PACE ZONES")
                .font(WSFont.display(52))
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 4)
            Text("DANIELS %VO2MAX · PER \(WSFormat.unitLabel(store.unit))")
                .font(WSFont.mono(12, weight: .medium))
                .foregroundStyle(WSColor.text40)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
            VStack(spacing: 0) {
                ForEach(zoneOrder, id: \.self) { zone in
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(swatch(zone))
                            .frame(width: 6, height: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(zone.rawValue.uppercased())
                                .font(WSFont.ui(15, weight: .heavy))
                                .tracking(0.5)
                            Text(purpose(zone))
                                .font(WSFont.ui(11, weight: .medium))
                                .foregroundStyle(WSColor.text45)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(pace(zone))
                                .font(WSFont.display(24))
                            Text(percent(zone))
                                .font(WSFont.mono(9))
                                .foregroundStyle(WSColor.text35)
                        }
                    }
                    .padding(.vertical, 15)
                    .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
                }
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 20)
            Text("RACE PREDICTIONS · RIEGEL")
                .font(WSFont.mono(10))
                .tracking(1.5)
                .foregroundStyle(WSColor.text40)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 22)
            VStack(spacing: 0) {
                ForEach(predictions, id: \.name) { row in
                    HStack {
                        Text(row.name)
                            .font(WSFont.ui(14, weight: .heavy))
                        Spacer()
                        Text(row.time)
                            .font(WSFont.mono(14, weight: .bold))
                            .foregroundStyle(WSColor.accent)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
                }
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(WSColor.bg.ignoresSafeArea())
    }

    private func swatch(_ zone: PaceZone) -> Color {
        switch zone {
        case .interval, .repetition: WSColor.accent
        case .marathon, .threshold: WSColor.accent.opacity(0.6)
        default: Color.white.opacity(0.25)
        }
    }

    private func purpose(_ zone: PaceZone) -> String {
        switch zone {
        case .easy: "Conversational aerobic"
        case .recovery: "Easy shakeout"
        case .marathon: "Goal marathon pace"
        case .threshold: "Comfortably hard"
        case .interval: "VO2max repeats"
        case .repetition: "Speed and form"
        }
    }

    private func pace(_ zone: PaceZone) -> String {
        guard let seconds = store.zones?.secondsPerKilometer(for: zone) else { return "—" }
        return WSFormat.paceClock(seconds, unit: store.unit)
    }

    private func percent(_ zone: PaceZone) -> String {
        let value = Int((PaceCalculator.percentVO2(for: zone) * 100).rounded())
        return "\(value)% VO2MAX"
    }

    private var predictions: [(name: String, time: String)] {
        guard let vdot = store.profile?.vdot else { return [] }
        let races: [(String, Double)] = [
            ("5K", 5_000),
            ("10K", 10_000),
            ("HALF", 21_097.5),
            ("MARATHON", 42_195),
        ]
        return races.map { name, meters in
            (name, WSFormat.duration(PaceCalculator.predictedDuration(vdot: vdot, distanceMeters: meters)))
        }
    }
}
