import SwiftUI
import WrathspeedCore

struct PendingTreadmillDistance: Identifiable, Equatable {
    let id: UUID
    var result: WorkoutResult
    let estimateMeters: Double

    init(result: WorkoutResult, estimateMeters: Double) {
        self.id = result.workoutID
        self.result = result
        self.estimateMeters = estimateMeters
    }
}

struct TreadmillDistanceSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let pending: PendingTreadmillDistance
    @State private var actualDisplay: Double

    init(pending: PendingTreadmillDistance) {
        self.pending = pending
        let unit = DistanceUnit.default()
        _actualDisplay = State(initialValue: Units.display(fromMeters: pending.estimateMeters, unit: unit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TREADMILL\nDISTANCE")
                .font(WSFont.display(34))
                .foregroundStyle(WSColor.text)
                .accessibilityAddTraits(.isHeader)
            Text("Enter the distance your treadmill reported. We'll replace the speed × time estimate before saving.")
                .font(WSFont.ui(14, weight: .medium))
                .foregroundStyle(WSColor.text50)
                .padding(.top, 12)
            HStack {
                Text("ESTIMATE")
                    .font(WSFont.ui(12, weight: .heavy))
                    .foregroundStyle(WSColor.text45)
                Spacer()
                Text(WSFormat.distance(pending.estimateMeters, unit: store.unit))
                    .font(WSFont.mono(13))
            }
            .padding(.top, 20)
            HStack {
                Text("ACTUAL")
                    .font(WSFont.ui(14, weight: .heavy))
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
                dismiss()
            }
            .accessibilityLabel("Save workout with actual treadmill distance")
            Button("USE ESTIMATE") {
                store.confirmTreadmillDistance(Units.display(fromMeters: pending.estimateMeters, unit: store.unit))
                dismiss()
            }
            .font(WSFont.ui(12, weight: .heavy))
            .foregroundStyle(WSColor.text50)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 40)
        .background(WSColor.bgSheet.ignoresSafeArea())
        .interactiveDismissDisabled()
        .onAppear {
            actualDisplay = Units.display(fromMeters: pending.estimateMeters, unit: store.unit)
        }
    }
}
