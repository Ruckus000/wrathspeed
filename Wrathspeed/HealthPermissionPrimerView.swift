import SwiftUI

struct HealthPermissionPrimerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            WSEyebrow(text: "ONE MORE THING")
            Text("CONNECT\nAPPLE HEALTH")
                .font(WSFont.display(46))
                .foregroundStyle(WSColor.text)
                .padding(.top, 10)
            Text("Wrathspeed reads workouts and heart rate to keep your plan honest. Location stays off until your first outdoor run.")
                .font(WSFont.ui(15))
                .foregroundStyle(WSColor.text50)
                .padding(.top, 16)
            Spacer()
            WSPrimaryButton(title: "ALLOW HEALTH ACCESS") {
                Task {
                    try? await store.session.requestAuthorization()
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
