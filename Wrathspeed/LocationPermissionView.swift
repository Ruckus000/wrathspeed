import CoreLocation
import SwiftUI
import WrathspeedCore

/// Thin wrapper over `CLLocationManager` for the one thing the app needs from it: asking for
/// while-in-use access and watching the answer.
///
/// Until this existed the app never requested location at all -- the only `CLLocationManager`
/// in the codebase was a status *read* in `WorkoutPreflightView`, so the status stayed
/// `.notDetermined` forever, preflight reported "NOT YET ALLOWED" on every run, and outdoor
/// route recording could never be switched on.
@MainActor
@Observable
final class LocationAuthorization: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var status: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
    }

    /// Raises the system prompt. Only ever answered once per install: iOS ignores the call
    /// after the first decision, which is why the denied screen offers Settings instead.
    func request() {
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let updated = manager.authorizationStatus
        Task { @MainActor in self.status = updated }
    }
}

/// Explains why the app wants location before the system asks, and gives the run somewhere to
/// go when the answer is no.
///
/// The second half matters more than the first: a denied permission used to leave outdoor
/// runs silently degraded, with nothing on screen saying so and no way to switch to an
/// approach that works. Both paths here save a full workout.
struct LocationPermissionView: View {
    /// Called when the person chooses the treadmill instead, so the caller can change the
    /// workout it is about to start.
    var onSwitchToTreadmill: () -> Void
    var onDismiss: () -> Void

    @State private var authorization = LocationAuthorization()
    /// Set when they decline our own primer. Kept apart from the system status because
    /// declining here never raises the system prompt, so the status stays `.notDetermined`.
    @State private var declinedPrimer = false

    private var showsDenied: Bool {
        if UITestingSupport.isUITesting && UITestingSupport.shouldPresentLocationPrimer {
            return declinedPrimer
        }
        return declinedPrimer || authorization.status == .denied || authorization.status == .restricted
    }

    var body: some View {
        Group {
            if showsDenied {
                deniedView
            } else {
                primerView
            }
        }
        .background(WSColor.bgSheet.ignoresSafeArea())
        .onChange(of: authorization.status) { _, status in
            // Granting is the only outcome that closes this by itself; a refusal has a
            // decision still to make on the denied screen.
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                onDismiss()
            }
        }
    }

    private var primerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(WSColor.accent)
                .frame(width: 52, height: 52)
                .background(WSColor.accentTint, in: RoundedRectangle(cornerRadius: WSRadius.alert, style: .continuous))
                .accessibilityHidden(true)
            Text("RECORD YOUR\nROUTE?")
                .wsType(.displayS)
                .foregroundStyle(WSColor.text)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
            Text("Wrathspeed uses your location while you run to measure distance and pace and to draw your route on the map.")
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text70)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            VStack(alignment: .leading, spacing: 10) {
                bullet("Only while a workout is running — never in the background.")
                bullet("You can run without it. Distance comes from your watch or the treadmill instead.")
            }
            .padding(.top, 20)
            Spacer(minLength: 16)
            WSPrimaryButton(title: "ALLOW WHILE RUNNING") {
                authorization.request()
            }
            .accessibilityIdentifier("location_primer_allow")
            Button { declinedPrimer = true } label: {
                // The frame belongs on the label. Applied outside the Button it leaves the
                // button's bounds the size of the glyph run -- tappable by a test, which
                // aims at the accessibility centre, but a thin strip to an actual finger.
                // TodayView carries the same note; this repeated the mistake.
                Text("DON'T ALLOW")
                    .wsType(.body, weight: .heavy, tracking: 1.2)
                    .foregroundStyle(WSColor.text50)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .accessibilityIdentifier("location_primer_decline")
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 96)
        .padding(.bottom, 44)
    }

    private var deniedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LOCATION NOT ALLOWED")
                .wsType(.metricS, tracking: 1.5)
                .foregroundStyle(WSColor.accent)
            Text("YOU CAN STILL\nDO THIS RUN.")
                .wsType(.displayS)
                .foregroundStyle(WSColor.text)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            Text("Without location we cannot draw your route or measure outdoor distance ourselves. Pick whichever suits you — both save a full workout.")
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text70)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            VStack(spacing: 10) {
                choice(
                    title: "SWITCH TO TREADMILL",
                    detail: "No GPS needed. You confirm the belt distance when you finish.",
                    accent: true,
                    identifier: "location_denied_treadmill"
                ) {
                    onSwitchToTreadmill()
                    onDismiss()
                }
                choice(
                    title: "RUN OUTSIDE ANYWAY",
                    detail: "Pace and time still record from your watch. No map, and distance may be less accurate.",
                    accent: false,
                    identifier: "location_denied_outside"
                ) {
                    onDismiss()
                }
            }
            .padding(.top, 22)
            Spacer(minLength: 16)
            // iOS will not raise the prompt a second time, so the only route back is Settings.
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                Text("CHANGE MY MIND")
                    .wsType(.body, weight: .heavy, tracking: 1.2)
                    .foregroundStyle(WSColor.text50)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("location_denied_change_mind")
            .accessibilityHint("Opens the Settings app")
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 96)
        .padding(.bottom, 44)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("✓")
                .wsType(.body, weight: .heavy)
                .foregroundStyle(WSColor.accent)
            Text(text)
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text70)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func choice(
        title: String,
        detail: String,
        accent: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .wsType(.body, weight: .heavy)
                    .foregroundStyle(WSColor.text)
                Text(detail)
                    .wsType(.body, weight: .medium)
                    .foregroundStyle(WSColor.text70)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            .wsCard(accent: accent)
            .contentShape(RoundedRectangle(cornerRadius: WSRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityElement(children: .combine)
    }
}
