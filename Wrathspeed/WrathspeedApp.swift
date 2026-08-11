import SwiftData
import SwiftUI

@main
struct WrathspeedApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .modelContainer(for: SnapshotEntity.self)
    }
}
