import SwiftUI

struct HealthPermissionPrimerView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            WSEyebrow(text: "ONE MORE THING")
            Text("CONNECT\nAPPLE HEALTH")
                .wsType(.displayL)
                .foregroundStyle(WSColor.text)
                .padding(.top, 10)
            Text("Wrathspeed reads workouts and heart rate to keep your plan honest. Location stays off until your first outdoor run.")
                .wsType(.body)
                .foregroundStyle(WSColor.text50)
                .padding(.top, 16)
            Spacer()
            WSPrimaryButton(title: "ALLOW HEALTH ACCESS") {
                Task {
                    await store.importHealthWorkouts()
                    store.showHealthPermissionPrimer = false
                }
            }
            WSOutlineButton(title: "NOT NOW") {
                store.showHealthPermissionPrimer = false
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.bottom, 40)
        .background(WSColor.bg.ignoresSafeArea())
    }
}
