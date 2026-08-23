import SwiftUI
import WrathspeedCore

struct SessionRecoveryView: View {
    @Environment(AppStore.self) private var store
    let snapshot: ActiveSessionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SESSION\nRECOVERY")
                .wsType(.displayS)
                .foregroundStyle(WSColor.text)
                .accessibilityAddTraits(.isHeader)
            Text(recoveryMessage)
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text50)
                .padding(.top, 12)
            if let blueprint = decodedBlueprint {
                Text(blueprint.title.uppercased())
                    .wsType(.metric)
                    .foregroundStyle(WSColor.accent)
                    .padding(.top, 10)
                Text("\(WSFormat.duration(snapshot.elapsedSeconds)) · \(WSFormat.distance(snapshot.distanceMeters, unit: store.unit))")
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text45)
                    .padding(.top, 6)
            }
            Spacer(minLength: 24)
            WSPrimaryButton(title: "SAVE PARTIAL") {
                store.savePartialRecovery(from: snapshot)
            }
            .accessibilityLabel("Save partial workout")
            WSOutlineButton(title: "DISCARD") {
                store.discardRecovery()
            }
            .padding(.top, 10)
            .accessibilityLabel("Discard recovered session")
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 52)
        .background(WSColor.bg.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private var recoveryMessage: String {
        switch snapshot.state {
        case .healthSyncPending:
            "Your last workout was saved locally but Apple Health sync did not finish."
        case .recording, .paused, .finishing:
            "A workout was interrupted. Save what you recorded or discard it."
        default:
            "An unfinished workout was found on this device."
        }
    }

    private var decodedBlueprint: WorkoutBlueprint? {
        try? JSONDecoder().decode(WorkoutBlueprint.self, from: snapshot.blueprintData)
    }
}
