import SwiftUI
import UIKit
import WrathspeedCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            WSScreen {
                Text("SETTINGS")
                    .wsType(.displayL)
                    .foregroundStyle(WSColor.text)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 10)
                if let subtitle = planSubtitle {
                    Text(subtitle)
                        .wsType(.metric)
                        .foregroundStyle(WSColor.text50)
                        .padding(.horizontal, WSSpace.gutter)
                        .padding(.top, 6)
                }

                group("LIVE RUN") {
                    WSListCard {
                        WSListRow(title: "METRICS SHOWN") {
                            // Multi-select: several segments can read as chosen at once, which
                            // is why the control takes an `isSelected` closure rather than a
                            // single binding.
                            WSSegmentedControl(
                                options: LiveMetric.allCases,
                                label: \.chipLabel,
                                isSelected: { store.liveMetrics.contains($0) },
                                select: { store.toggleLiveMetric($0) }
                            )
                        }
                        WSListRow(title: "DATA DENSITY", showDivider: false) {
                            WSSegmentedControl(
                                options: DataDensity.allCases,
                                label: \.title,
                                isSelected: { store.dataDensity == $0 },
                                select: { store.setDataDensity($0) }
                            )
                        }
                    }
                }

                group("COACHING") {
                    WSListCard {
                        Button {
                            store.cuesEnabled.toggle()
                            store.session.cuesEnabled = store.cuesEnabled
                            store.save()
                        } label: {
                            WSListRow(
                                title: "AUDIO CUES",
                                hint: store.cuesEnabled ? "SPOKEN DURING A RUN" : "SILENT",
                                showDivider: store.cuesEnabled
                            ) {
                                Text(store.cuesEnabled ? "ON" : "OFF")
                                    .wsType(.label, weight: .heavy, tracking: 1)
                                    .foregroundStyle(store.cuesEnabled ? .white : WSColor.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(store.cuesEnabled ? WSColor.accent : Color.clear, in: Capsule())
                                    .overlay(Capsule().stroke(store.cuesEnabled ? WSColor.accent : WSColor.border, lineWidth: 1.5))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // The design hides the style picker while cues are off, which is
                        // honest: it controls nothing in that state.
                        if store.cuesEnabled {
                            WSListRow(title: "CUE STYLE", showDivider: false) {
                                WSSegmentedControl(
                                    options: CueStyle.allCases,
                                    label: \.title,
                                    isSelected: { store.cueStyle == $0 },
                                    select: { store.setCueStyle($0) }
                                )
                            }
                        }
                    }
                }

                group("RUNNING PROFILE") {
                    WSListCard {
                        // Divider only when rows follow it. Everything below is behind
                        // `if let profile`, so a nil profile would otherwise leave a hairline
                        // hanging at the bottom of the card with nothing under it.
                        WSListRow(title: "UNITS", showDivider: store.profile != nil) {
                            WSSegmentedControl(
                                options: DistanceUnit.allCases,
                                label: { $0 == .miles ? "MILES" : "KM" },
                                isSelected: { store.unit == $0 },
                                select: { setUnit($0) }
                            )
                        }
                        if let profile = store.profile {
                            NavigationLink {
                                PaceZonesView()
                            } label: {
                                WSListRow(title: "PACE ZONES", hint: "VDOT SETS EVERY TARGET PACE") {
                                    Text("\(WSFormat.vdot(profile.vdot)) ›")
                                        .wsType(.metric, weight: .bold)
                                        .foregroundStyle(WSColor.accent)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            WSListRow(title: "ABILITY") {
                                Text(profile.ability.title.uppercased())
                                    .wsType(.metric, weight: .bold)
                                    .foregroundStyle(WSColor.text70)
                            }
                            WSListRow(title: "DAYS / WEEK", showDivider: false) {
                                Text("\(profile.daysPerWeek)")
                                    .wsType(.metric, weight: .bold)
                                    .foregroundStyle(WSColor.text70)
                            }
                        }
                    }
                }

                group("STRENGTH") {
                    WSListCard {
                        NavigationLink {
                            StrengthPreferencesView()
                        } label: {
                            WSListNavRow(title: "PREFERENCES", hint: strengthSummary, showDivider: false)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.strengthPreferences")
                    }
                }

                group("CONTENT") {
                    WSListCard {
                        NavigationLink {
                            MovementLibraryView()
                        } label: {
                            WSListNavRow(title: "MOVEMENT LIBRARY", hint: libraryHint)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.movementLibrary")
                        NavigationLink {
                            ContentLicensesView()
                        } label: {
                            WSListNavRow(
                                title: "CONTENT LICENSES",
                                hint: "WHERE THE BUNDLED MEDIA COMES FROM",
                                showDivider: false
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if store.n100 != nil {
                    group("PLAN ADJUSTMENT") {
                        WSListCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("An adjustment is active. Ending it returns every future week to the plan as generated.")
                                    .wsType(.body, weight: .medium)
                                    .foregroundStyle(WSColor.text70)
                                    .fixedSize(horizontal: false, vertical: true)
                                WSOutlineButton(title: "END NOT FEELING 100%", height: 44) {
                                    store.endNotFeeling100()
                                }
                            }
                            .padding(16)
                        }
                    }
                }

                group("DIAGNOSTICS") {
                    WSListCard {
                        VStack(alignment: .leading, spacing: 10) {
                            WSOutlineButton(title: "EXPORT REDACTED DIAGNOSTICS", height: 44, borderColor: WSColor.border) {
                                if let data = try? DiagnosticsExporter.exportJSON(from: store),
                                   let json = String(data: data, encoding: .utf8) {
                                    UIPasteboard.general.string = json
                                    store.showToast("DIAGNOSTICS COPIED")
                                }
                            }
                            .accessibilityLabel("Export redacted diagnostics to clipboard")
                            Text("Includes app version, schema version, and non-sensitive counts only.")
                                .wsType(.caption, weight: .medium)
                                .foregroundStyle(WSColor.text40)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                    }
                }

                WSOutlineButton(title: "REBUILD FUTURE WEEKS") {
                    store.regeneratePlan()
                    store.showToast("FUTURE WEEKS REBUILT")
                }
                .padding(.horizontal, WSSpace.cardGutter)
                .padding(.top, 22)
                Text("Rebuilds every future week from your current VDOT. Completed work is never changed.")
                    .wsType(.caption, weight: .medium)
                    .foregroundStyle(WSColor.text35)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 8)
                WSLockup(.caged, style: .monoLight)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36)
                    .padding(.bottom, 30)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// "HALF MARATHON · WEEK 5 OF 12" -- the design puts the plan under the screen title so
    /// Settings says what it is settings *for*.
    private var planSubtitle: String? {
        guard let plan = store.plan else { return nil }
        let week = store.currentWeekIndex()
        return "\(plan.goal.kind.displayName.uppercased()) · WEEK \(week.current) OF \(week.total)"
    }

    private var strengthSummary: String {
        let prefs = store.strengthPrefs
        return "\(prefs.ability.title.uppercased()) · \(prefs.durationMinutes) MIN · \(prefs.sessionsPerWeek)/WK"
    }

    /// Deferred to the library rather than recomputed, so the row cannot advertise a count
    /// the screen behind it does not list.
    private var libraryHint: String { MovementLibraryView.countHint(for: store) }

    /// Group heading. The design renders these in white at 35% with 2pt tracking, not in the
    /// accent the app used -- accent headings competed with the values inside the cards.
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .wsType(.metricS, tracking: 2)
                .foregroundStyle(WSColor.text35)
                .padding(.horizontal, WSSpace.gutter)
            content()
        }
        .padding(.top, 24)
    }


    private func setUnit(_ unit: DistanceUnit) {
        guard var profile = store.profile else { return }
        profile.unit = unit
        store.profile = profile
        store.regeneratePlan(profile: profile)
    }

}

struct PaceZonesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let zoneOrder: [PaceZone] = [.easy, .recovery, .marathon, .threshold, .interval, .repetition]

    var body: some View {
        WSScreen {
            WSBackButton(title: "← SETTINGS") { dismiss() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 8)
            WSEyebrow(text: "VDOT \(WSFormat.vdot(store.profile?.vdot ?? 0))")
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 18)
            Text("PACE ZONES")
                .wsType(.displayL)
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 4)
            Text("DANIELS %VO2MAX · PER \(WSFormat.unitLabel(store.unit))")
                .wsType(.metric, weight: .medium)
                .foregroundStyle(WSColor.text40)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
            VStack(spacing: 0) {
                ForEach(zoneOrder, id: \.self) { zone in
                    WSRow(spacing: 14) {
                        // Kept together so the stacked arrangement does not break this
                        // group onto separate lines of its own.
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(swatch(zone))
                                .frame(width: 6, height: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(zone.rawValue.uppercased())
                                    .wsType(.body, weight: .heavy, tracking: 0.5)
                                Text(purpose(zone))
                                    .wsType(.label, weight: .medium)
                                    .foregroundStyle(WSColor.text45)
                            }
                        }
                    } trailing: {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(pace(zone))
                                .wsType(.displayXS)
                            Text(percent(zone))
                                .wsType(.metricS)
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
                .wsType(.metricS, tracking: 1.5)
                .foregroundStyle(WSColor.text40)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 22)
            VStack(spacing: 0) {
                ForEach(predictions, id: \.name) { row in
                    WSRow {
                        Text(row.name)
                            .wsType(.body, weight: .heavy)
                    } trailing: {
                        Text(row.time)
                            .wsType(.metric, weight: .bold)
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
