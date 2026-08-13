import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext

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
