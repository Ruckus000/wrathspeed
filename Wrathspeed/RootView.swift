import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @State private var pendingStart: PreflightRequest?

    var body: some View {
        // One reader at the root, because two things below need the same number: the tab bar
        // has to know how much safe area to drop through, and the toast has to land above where
        // that leaves it. Measured rather than declared -- a phone with a home indicator reports
        // 34pt here, one with a home button reports none, and both are supported.
        GeometryReader { proxy in
            content(safeAreaBottom: proxy.safeAreaInsets.bottom)
        }
        .background(WSColor.bg.ignoresSafeArea())
    }

    @ViewBuilder
    private func content(safeAreaBottom: CGFloat) -> some View {
        @Bindable var store = store
        Group {
            if store.hasOnboarded {
                MainTabView(safeAreaBottom: safeAreaBottom)
            } else {
                OnboardingView()
            }
        }
        .onAppear { store.attach(context: modelContext) }
        .overlay {
            if let message = store.errorMessage {
                WSAlert(message: message) { store.errorMessage = nil }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toastMessage {
                WSToast(text: toast)
                    .padding(.horizontal, 24)
                    // Derived from the bar's own metric rather than hand-tuned, so it cannot
                    // quietly stop matching if the bar moves. Laid out inside the safe area,
                    // like the scroll views, so it wants the same inset they do.
                    .padding(.bottom, WSTabBar.contentInset(safeAreaBottom: safeAreaBottom) + 16)
                    // The toast has an opaque background and nothing to tap, so without this it
                    // silently eats every touch that lands on it for as long as it is up. That
                    // was already true before the bar moved; the banner simply happened to sit
                    // over empty space. Lowering it put it across Today's "NOT FEELING 100%?"
                    // row, and the tap right after an adjustment went into the banner instead.
                    // Verified both ways on iPhone Air: removing this line fails
                    // Milestone4UITests.testWeeklyCalendarAndManagePlanFlows at the same line
                    // CI failed on.
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: WSMotion.sheet), value: store.toastMessage)
        .fullScreenCover(item: $store.celebration) { payload in
            CelebrationView(payload: payload)
        }
        .fullScreenCover(isPresented: $store.showHealthPermissionPrimer) {
            HealthPermissionPrimerView()
        }
        .sheet(item: $store.pendingPreflight, onDismiss: startPendingWorkout) { request in
            WorkoutPreflightView(blueprint: request.blueprint, source: request.source) { resolved in
                pendingStart = resolved
            }
        }
        .fullScreenCover(item: $store.pendingRecoverySnapshot) { snapshot in
            SessionRecoveryView(snapshot: snapshot)
        }
        .sheet(item: $store.pendingTreadmillDistance) { pending in
            TreadmillDistanceSheet(pending: pending)
                .presentationDetents([.medium, .large])
                .presentationBackground(WSColor.bgSheet)
        }
        .fullScreenCover(isPresented: liveWorkoutPresented) {
            if let blueprint = store.session.blueprint {
                LiveRunView(blueprint: blueprint)
                    // The cover already presents during `.countdown`; until now that meant
                    // three seconds of a live screen with nothing on it yet. The overlay
                    // sits on top and goes away on its own when the counter clears, which
                    // is immediately when Reduce Motion or a test has skipped it.
                    .overlay {
                        if let remaining = store.session.countdownRemaining {
                            WorkoutCountdownOverlay(
                                remaining: remaining,
                                title: blueprint.title
                            )
                        }
                    }
            }
        }
    }

    /// Runs once the preflight sheet has actually gone, so the live cover below is free to
    /// present. PlanView sequences its own hop into preflight the same way. Cancelling the
    /// preflight leaves `pendingStart` nil, so this is a no-op on that path.
    private func startPendingWorkout() {
        guard let request = pendingStart else { return }
        pendingStart = nil
        Task { await store.start(request.blueprint, source: request.source) }
    }

    private var liveWorkoutPresented: Binding<Bool> {
        Binding(
            get: {
                store.session.isRunning
                    || store.session.launchState == .waitingForWatch
                    || store.session.sessionState == .countdown
            },
            set: { _ in }
        )
    }
}

struct MainTabView: View {
    /// How deep the bottom safe area is, measured at the root. The bar drops through it.
    var safeAreaBottom: CGFloat

    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Group {
            switch store.selectedTab {
            case .today: TodayView()
            case .plan: PlanView()
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // An overlay rather than a VStack row: in a stack the bar subtracted its full height
        // from every screen whether or not the screen needed it. Floating, content runs under
        // and beside it, and screens that end in a Spacer get the height back outright.
        .overlay(alignment: .bottom) {
            WSTabBar(selection: $store.selectedTab)
                // An offset, not `.ignoresSafeArea`. An overlay is laid out against its host's
                // frame, and the host is already inset by the safe area, so there is nothing for
                // ignoresSafeArea to expand into -- tried it, the bar did not move. Offsetting
                // moves the drawn bar without touching layout, and overlays are not clipped.
                .offset(y: safeAreaBottom)
        }
        .environment(\.wsBottomBarInset, WSTabBar.contentInset(safeAreaBottom: safeAreaBottom))
        .background(WSColor.bg.ignoresSafeArea())
    }
}
