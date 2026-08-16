import SwiftUI
import WrathspeedCore

struct WatchTodayView: View {
    @Environment(WatchStore.self) private var store
    @State private var active: WatchStartRequest?

    var body: some View {
        NavigationStack {
            Group {
                if store.upcoming.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let first = store.upcoming.first {
                                heroCard(first)
                            }
                            ForEach(Array(store.upcoming.dropFirst())) { blueprint in
                                upcomingRow(blueprint)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .background(WSColor.bg.ignoresSafeArea())
            .navigationDestination(item: $active) { request in
                WatchLiveView(request: request)
            }
            .onChange(of: store.bridge.pendingStartRequest?.blueprint.id) { _, _ in
                if let request = store.bridge.pendingStartRequest {
                    store.receive(request)
                }
            }
            .onChange(of: store.resolvedStart?.blueprint.id) { _, _ in
                if let request = store.resolvedStart { active = request }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TODAY")
                .font(WSFont.ui(10, weight: .bold))
                .foregroundStyle(WSColor.accent)
            Text("No upcoming runs. Open iPhone to sync your plan.")
                .font(WSFont.ui(12, weight: .medium))
                .foregroundStyle(WSColor.text50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func heroCard(_ blueprint: WorkoutBlueprint) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(dateEyebrow(blueprint))
                    .font(WSFont.mono(10, weight: .bold))
                    .foregroundStyle(WSColor.accent)
                    .accessibilityLabel(dateAccessibility(blueprint))
                Spacer()
                Text(Date.now, style: .time)
                    .font(WSFont.mono(10))
                    .foregroundStyle(WSColor.text50)
            }
            Text(blueprint.title.uppercased())
                .font(WSFont.display(28))
                .foregroundStyle(WSColor.text)
                .padding(.top, 12)
            Text(meta(blueprint))
                .font(WSFont.mono(11))
                .foregroundStyle(WSColor.text50)
                .padding(.top, 8)
            Text(steps(blueprint))
                .font(WSFont.mono(10))
                .foregroundStyle(WSColor.text35)
                .padding(.top, 4)
            Button("START") {
                active = startRequest(for: blueprint)
            }
            .font(WSFont.ui(13, weight: .heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(WSColor.accent, in: Capsule())
            .buttonStyle(.plain)
            .padding(.top, 12)
            .accessibilityLabel("Start \(blueprint.title)")
            .accessibilityHint("Starts this workout on Apple Watch")
        }
    }

    private func upcomingRow(_ blueprint: WorkoutBlueprint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateEyebrow(blueprint))
                .font(WSFont.mono(10, weight: .bold))
                .foregroundStyle(WSColor.accent)
            Text(blueprint.title.uppercased())
                .font(WSFont.ui(13, weight: .heavy))
                .foregroundStyle(WSColor.text)
            Text(meta(blueprint))
                .font(WSFont.mono(10))
                .foregroundStyle(WSColor.text50)
            Button("START") {
                active = startRequest(for: blueprint)
            }
            .font(WSFont.ui(12, weight: .heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(WSColor.accent, in: Capsule())
            .buttonStyle(.plain)
            .accessibilityLabel("Start \(blueprint.title)")
            .accessibilityValue(dateAccessibility(blueprint))
            .accessibilityHint("Starts this upcoming workout on Apple Watch")
        }
        .accessibilityElement(children: .contain)
    }

    private func startRequest(for blueprint: WorkoutBlueprint) -> WatchStartRequest {
        WatchStartRequest(blueprint: blueprint, vdot: store.bridge.upcoming?.vdot, unit: store.distanceUnit)
    }

    private func dateEyebrow(_ blueprint: WorkoutBlueprint, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(blueprint.date) { return "TODAY" }
        return blueprint.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
    }

    private func dateAccessibility(_ blueprint: WorkoutBlueprint, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(blueprint.date) { return "Today" }
        return blueprint.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func meta(_ blueprint: WorkoutBlueprint) -> String {
        let unit = store.distanceUnit
        let distance = Units.compactDistance(blueprint.plannedDistanceMeters, unit: unit)
        return "\(distance) · \(targetPace(blueprint, unit: unit))"
    }

    private func steps(_ blueprint: WorkoutBlueprint) -> String {
        blueprint.steps.prefix(3).map(\.name).joined(separator: " → ").uppercased()
    }

    private func targetPace(_ blueprint: WorkoutBlueprint, unit: DistanceUnit) -> String {
        guard let vdot = store.bridge.upcoming?.vdot else { return "—" }
        let zones = PaceCalculator.zones(vdot: vdot)
        guard let seconds = WorkoutPaceTarget.targetPaceSecPerKm(blueprint: blueprint, zones: zones) else { return "—" }
        return Units.compactPace(secondsPerKilometer: seconds, unit: unit)
    }
}

struct WatchLiveView: View {
    @Environment(WatchStore.self) private var store
    let request: WatchStartRequest
    @State private var confirmEnd = false

    private var blueprint: WorkoutBlueprint { request.blueprint }

    private var unit: DistanceUnit {
        request.unit ?? store.bridge.upcoming?.unit ?? .default()
    }

    private var paceStatus: PaceBandStatus {
        PaceBandStatus.evaluate(
            currentPaceSecPerKm: store.session.metrics.currentPaceSecPerKm,
            targetSecPerKm: targetPace,
            paused: store.session.isPaused
        )
    }

    var body: some View {
        let session = store.session
        VStack(alignment: .leading, spacing: 0) {
            Text((session.stepper?.currentStep?.name ?? blueprint.title).uppercased())
                .font(WSFont.ui(10, weight: .bold))
                .tracking(1)
                .foregroundStyle(WSColor.accent)
            Text(pace)
                .font(WSFont.display(58))
                .foregroundStyle(WSColor.accent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.top, 10)
                .accessibilityLabel("Current pace")
                .accessibilityValue("\(pace) \(Units.compactUnitSuffix(unit)) per \(unit == .miles ? "mile" : "kilometre"). \(paceStatus.watchLabel)")
            Text("PACE /\(Units.compactUnitSuffix(unit)) · \(paceStatus.watchLabel)")
                .font(WSFont.ui(9, weight: .bold))
                .tracking(2)
                .foregroundStyle(WSColor.text50)
                .padding(.top, 4)
                .accessibilityLabel("Pace status")
                .accessibilityValue(paceStatus.watchLabel)
            zoneBand
                .padding(.top, 12)
                .accessibilityHidden(true)
            Spacer()
            HStack {
                Text(Units.formatDuration(session.metrics.elapsed))
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(Units.formatDuration(session.metrics.elapsed))
                Spacer()
                Text(Units.compactDistance(session.metrics.distanceMeters, unit: unit))
                    .foregroundStyle(WSColor.text50)
                    .accessibilityLabel("Distance")
                    .accessibilityValue(Units.compactDistance(session.metrics.distanceMeters, unit: unit))
                Spacer()
                Text(session.metrics.heartRate.map { "\(Int($0.rounded()))" } ?? "—")
                    .foregroundStyle(WSColor.text50)
                    .accessibilityLabel("Heart rate")
                    .accessibilityValue(session.metrics.heartRate.map { "\(Int($0.rounded())) beats per minute" } ?? "Unavailable")
            }
            .font(WSFont.mono(13))
            controls
                .padding(.top, 8)
        }
        .padding(.horizontal, 2)
        .background(WSColor.bg.ignoresSafeArea())
        .confirmationDialog("End this workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Workout", role: .destructive) {
                Task { await store.endWorkout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This ends the Watch workout. It cannot be undone from here.")
        }
        .task {
            store.beginWorkout(request)
        }
        .onDisappear {
            store.cancelStartupIfPending()
        }
    }

    private var pace: String {
        guard let value = store.session.metrics.currentPaceSecPerKm else { return "–:––" }
        return Units.paceClock(secondsPerKilometer: value, unit: unit)
    }

    private var advanceTitle: String {
        store.session.usesManualTreadmillDistance || blueprint.location == .treadmill ? "NEXT" : "LAP"
    }

    private var controls: some View {
        let session = store.session
        return HStack(spacing: 6) {
            controlButton(session.isPaused ? "RESUME" : "PAUSE") {
                session.isPaused ? session.resume() : session.pause()
            }
            .disabled(!store.canPauseOrLap)
            .opacity(store.canPauseOrLap ? 1 : 0.35)
            .accessibilityLabel(session.isPaused ? "Resume workout" : "Pause workout")
            .accessibilityHint(session.isPaused ? "Continues recording" : "Pauses recording without ending")
            .accessibilityValue(store.canPauseOrLap ? (session.isPaused ? "Paused" : "Recording") : "Unavailable until recording")

            controlButton(advanceTitle) {
                session.skipStep()
            }
            .disabled(!store.canPauseOrLap)
            .opacity(store.canPauseOrLap ? 1 : 0.35)
            .accessibilityLabel(advanceTitle == "NEXT" ? "Next step" : "Lap")
            .accessibilityHint("Advances to the next workout step")

            controlButton("END") {
                confirmEnd = true
            }
            .accessibilityLabel("End workout")
            .accessibilityHint("Asks for confirmation before ending")
        }
    }

    private func controlButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WSFont.ui(10, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(WSColor.text)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var zoneBand: some View {
        let target = targetPace ?? 360
        let current = store.session.metrics.currentPaceSecPerKm ?? target
        let low = target * 0.85
        let high = target * 1.20
        let span = max(high - low, 1)
        let fast = target * (1 - PaceBandStatus.defaultTolerance)
        let slow = target * (1 + PaceBandStatus.defaultTolerance)
        return WSZoneBand(
            lowLabel: "",
            midLabel: "",
            highLabel: "",
            bandStart: CGFloat((fast - low) / span),
            bandWidth: CGFloat((slow - fast) / span),
            needle: CGFloat(min(1, max(0, (current - low) / span))),
            height: 7
        )
    }

    private var targetPace: TimeInterval? {
        WorkoutPaceTarget.targetPaceSecPerKm(blueprint: blueprint, zones: store.session.zones)
    }
}
