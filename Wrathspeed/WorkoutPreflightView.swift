import CoreLocation
import SwiftUI
import WrathspeedCore

struct WorkoutPreflightView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let blueprint: WorkoutBlueprint
    let source: WorkoutSource
    var onStart: (PreflightRequest) -> Void

    @State private var draftLocation: RunLocation
    @State private var manualTreadmillSpeedDisplay: Double
    @State private var didStart = false

    init(blueprint: WorkoutBlueprint, source: WorkoutSource, onStart: @escaping (PreflightRequest) -> Void) {
        self.blueprint = blueprint
        self.source = source
        self.onStart = onStart
        _draftLocation = State(initialValue: blueprint.location)
        _manualTreadmillSpeedDisplay = State(initialValue: 10)
    }

    private var resolvedBlueprint: WorkoutBlueprint {
        var copy = blueprint
        copy.location = draftLocation
        return copy
    }

    private var representativePace: TimeInterval? {
        WorkoutPaceTarget.targetPaceSecPerKm(blueprint: resolvedBlueprint, zones: store.zones)
    }

    private var derivedTreadmillSpeed: Double? {
        WorkoutPaceTarget.treadmillSpeedMetersPerSecond(blueprint: resolvedBlueprint, zones: store.zones)
    }

    private var resolvedTreadmillSpeed: Double? {
        guard draftLocation == .treadmill else { return nil }
        if let derivedTreadmillSpeed { return derivedTreadmillSpeed }
        let manual = WorkoutPaceTarget.treadmillSpeedFromDisplay(manualTreadmillSpeedDisplay, unit: store.unit)
        return manual > 0 ? manual : nil
    }

    private var canStart: Bool {
        guard draftLocation != .treadmill else { return resolvedTreadmillSpeed != nil }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PREFLIGHT")
                .font(WSFont.display(34))
                .foregroundStyle(WSColor.text)
                .accessibilityAddTraits(.isHeader)
            Text(blueprint.title.uppercased())
                .font(WSFont.mono(12))
                .foregroundStyle(WSColor.text45)
                .padding(.top, 8)
            locationSection
            preflightRow("UNITS", store.unit == .miles ? "MILES" : "KILOMETRES")
            preflightRow("STEPS", "\(blueprint.steps.count)")
            preflightRow("PLANNED", WSFormat.distance(blueprint.plannedDistanceMeters, unit: store.unit))
            if let pace = representativePace {
                preflightRow("TARGET PACE", WSFormat.pace(pace, unit: store.unit))
            }
            if draftLocation == .treadmill {
                treadmillSpeedSection
            }
            readinessSection
            preflightRow("WATCH", WCSessionBridge.isWatchAppInstalled ? "AVAILABLE" : "NOT INSTALLED")
            structureSection
            Spacer(minLength: 20)
            WSPrimaryButton(title: "START WORKOUT") {
                startWorkout()
            }
            .disabled(!canStart || didStart)
            .accessibilityLabel("Start workout")
            .padding(.top, 12)
            Button("CANCEL") { dismiss() }
                .font(WSFont.ui(12, weight: .heavy))
                .foregroundStyle(WSColor.text50)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 8)
                .accessibilityLabel("Cancel preflight")
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 40)
        .background(WSColor.bgSheet.ignoresSafeArea())
        .onAppear {
            if let derived = derivedTreadmillSpeed {
                manualTreadmillSpeedDisplay = WorkoutPaceTarget.treadmillSpeedDisplay(
                    metersPerSecond: derived,
                    unit: store.unit
                )
            }
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LOCATION")
                .font(WSFont.mono(10))
                .tracking(1.5)
                .foregroundStyle(WSColor.accent)
                .padding(.top, 14)
            HStack(spacing: 8) {
                ForEach(RunLocation.allCases, id: \.self) { item in
                    WSChip(title: item.title, selected: draftLocation == item) {
                        draftLocation = item
                    }
                }
            }
        }
    }

  @ViewBuilder
    private var treadmillSpeedSection: some View {
        if let derivedTreadmillSpeed {
            preflightRow(
                "TREADMILL SPEED",
                formatTreadmillSpeedDisplay(derivedTreadmillSpeed)
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("TREADMILL SPEED")
                    .font(WSFont.ui(12, weight: .heavy))
                    .foregroundStyle(WSColor.text45)
                    .padding(.top, 10)
                Text("Set a target belt speed. We'll estimate distance until you confirm the treadmill total.")
                    .font(WSFont.ui(12, weight: .medium))
                    .foregroundStyle(WSColor.text50)
                HStack {
                    Text(store.unit == .miles ? "MPH" : "KM/H")
                        .font(WSFont.ui(14, weight: .heavy))
                    Spacer()
                    WSStepperControl(
                        valueText: String(format: "%.1f", manualTreadmillSpeedDisplay),
                        decrement: { manualTreadmillSpeedDisplay = max(1, manualTreadmillSpeedDisplay - 0.5) },
                        increment: { manualTreadmillSpeedDisplay = min(20, manualTreadmillSpeedDisplay + 0.5) }
                    )
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var readinessSection: some View {
        let gps = gpsReadiness
        return VStack(alignment: .leading, spacing: 4) {
            preflightRow("GPS ROUTE", gps.label)
            if !gps.detail.isEmpty {
                Text(gps.detail)
                    .font(WSFont.ui(12, weight: .medium))
                    .foregroundStyle(WSColor.text50)
            }
        }
    }

    private var structureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STRUCTURE")
                .font(WSFont.mono(10))
                .tracking(1.5)
                .foregroundStyle(WSColor.text40)
                .padding(.top, 16)
            ForEach(blueprint.steps.prefix(6)) { step in
                HStack {
                    Text(step.name)
                        .font(WSFont.ui(13, weight: .bold))
                    Spacer()
                    Text(stepSummary(step))
                        .font(WSFont.mono(11))
                        .foregroundStyle(WSColor.text50)
                }
                .accessibilityElement(children: .combine)
            }
            if blueprint.steps.count > 6 {
                Text("+\(blueprint.steps.count - 6) MORE")
                    .font(WSFont.mono(11))
                    .foregroundStyle(WSColor.text40)
            }
        }
    }

    private var gpsReadiness: (label: String, detail: String) {
        guard draftLocation == .outdoor else {
            return ("NOT NEEDED", "Treadmill workouts do not record a GPS route.")
        }
        let status = CLLocationManager().authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return ("AVAILABLE", "Outdoor route recording is enabled.")
        case .notDetermined:
            return (
                "NOT YET ALLOWED",
                "You can still finish the workout. Location permission enables route recording."
            )
        case .denied, .restricted:
            return (
                "DEGRADED",
                "Workout completes without a route. Enable location in Settings to record GPS."
            )
        @unknown default:
            return ("UNKNOWN", "Route recording may be limited.")
        }
    }

    private func formatTreadmillSpeedDisplay(_ metersPerSecond: Double) -> String {
        let display = WorkoutPaceTarget.treadmillSpeedDisplay(metersPerSecond: metersPerSecond, unit: store.unit)
        let suffix = store.unit == .miles ? "mph" : "km/h"
        return String(format: "%.1f %@", display, suffix)
    }

    private func preflightRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(WSFont.ui(12, weight: .heavy))
                .foregroundStyle(WSColor.text45)
            Spacer()
            Text(value)
                .font(WSFont.mono(12))
                .foregroundStyle(WSColor.text)
        }
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }

    private func stepSummary(_ step: WorkoutStep) -> String {
        switch step.target {
        case .distance(let meters): WSFormat.distance(meters, unit: store.unit)
        case .duration(let seconds): Units.formatDuration(seconds)
        }
    }

    private func startWorkout() {
        guard !didStart else { return }
        didStart = true
        let resolved = resolvedBlueprint
        store.session.preparePreflightTreadmill(
            blueprint: resolved,
            speedMetersPerSecond: resolvedTreadmillSpeed
        )
        // Handed to RootView to start once this sheet has actually gone. Starting it here
        // asked SwiftUI to present the live cover mid-dismissal, which UIKit refuses -- and
        // because the cover's binding never changes back, it is never retried.
        onStart(PreflightRequest(blueprint: resolved, source: source))
        store.pendingPreflight = nil
    }
}
