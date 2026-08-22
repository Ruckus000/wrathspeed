import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @State private var pendingStart: PreflightRequest?

    var body: some View {
        @Bindable var store = store
        Group {
            if store.hasOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .background(WSColor.bg.ignoresSafeArea())
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
                    .padding(.bottom, 110)
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
        .sheet(isPresented: $store.showWatchLaunchTimeout) {
            WatchLaunchTimeoutView()
                .presentationDetents([.medium])
                .presentationBackground(WSColor.bgSheet)
        }
        .sheet(item: $store.pendingTreadmillDistance) { pending in
            TreadmillDistanceSheet(pending: pending)
                .presentationDetents([.medium, .large])
                .presentationBackground(WSColor.bgSheet)
        }
        .fullScreenCover(isPresented: liveWorkoutPresented) {
            if let blueprint = store.session.blueprint {
                LiveRunView(blueprint: blueprint)
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
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            Group {
                switch store.selectedTab {
                case .today: TodayView()
                case .plan: PlanView()
                case .history: HistoryView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            WSTabBar(selection: $store.selectedTab)
        }
        .background(WSColor.bg.ignoresSafeArea())
    }
}
