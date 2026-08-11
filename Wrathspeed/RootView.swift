import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if store.hasOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .onAppear { store.attach(context: modelContext) }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                TodayView()
            }
            Tab("Plan", systemImage: "calendar") {
                PlanView()
            }
            Tab("History", systemImage: "clock") {
                HistoryView()
            }
            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
    }
}
