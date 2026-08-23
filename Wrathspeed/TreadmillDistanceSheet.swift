import SwiftUI
import WrathspeedCore

struct PendingTreadmillDistance: Identifiable, Equatable {
    let id: UUID
    var result: WorkoutResult
    let estimateMeters: Double
    let displayUnit: DistanceUnit

    init(result: WorkoutResult, estimateMeters: Double, displayUnit: DistanceUnit = .kilometers) {
        self.id = result.workoutID
        self.result = result
        self.estimateMeters = estimateMeters
        self.displayUnit = displayUnit
    }
}

struct TreadmillDistanceSheet: View {
    @Environment(AppStore.self) private var store
    let pending: PendingTreadmillDistance
    @State private var actualDisplay: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TREADMILL\nDISTANCE")
                .wsType(.displayS)
                .foregroundStyle(WSColor.text)
                .accessibilityAddTraits(.isHeader)
            Text("Enter the distance your treadmill reported. We'll replace the speed × time estimate before saving.")
                .wsType(.body, weight: .medium)
                .foregroundStyle(WSColor.text50)
                .padding(.top, 12)
            HStack {
                Text("ESTIMATE")
                    .wsType(.label, weight: .heavy)
                    .foregroundStyle(WSColor.text45)
                Spacer()
                Text(WSFormat.distance(pending.estimateMeters, unit: store.unit))
                    .wsType(.metric)
            }
            .padding(.top, 20)
            HStack {
                Text("ACTUAL")
                    .wsType(.body, weight: .heavy)
                Spacer()
                WSStepperControl(
                    valueText: String(format: "%.2f %@", actualDisplay, WSFormat.unitLabel(store.unit)),
                    decrement: { actualDisplay = max(0.1, actualDisplay - 0.1) },
                    increment: { actualDisplay = min(100, actualDisplay + 0.1) }
                )
            }
            .padding(.top, 16)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 24)
            WSPrimaryButton(title: "SAVE WORKOUT") {
                store.confirmTreadmillDistance(actualDisplay)
            }
            .accessibilityLabel("Save workout with actual treadmill distance")
            Button("USE ESTIMATE") {
                store.confirmTreadmillDistance(Units.display(fromMeters: pending.estimateMeters, unit: store.unit))
            }
            .wsType(.label, weight: .heavy)
            .foregroundStyle(WSColor.text50)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 40)
        .background(WSColor.bgSheet.ignoresSafeArea())
        .interactiveDismissDisabled()
        .overlay {
            if let message = store.errorMessage {
                WSAlert(message: message) { store.errorMessage = nil }
            }
        }
        .onAppear {
            let unit = store.unit
            actualDisplay = Units.display(fromMeters: pending.estimateMeters, unit: unit)
        }
    }
}
