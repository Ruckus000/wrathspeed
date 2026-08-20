import SwiftUI
import WrathspeedCore

struct NotFeeling100View: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var startDate: Date
    @State private var days: Int
    @State private var mode: N100Mode
    @State private var returnPace: N100Return
    @State private var errorMessage: String?

    init() {
        let existing = PersistedState.initial.n100
        _startDate = State(initialValue: existing?.start ?? Date())
        _days = State(initialValue: existing?.dayCount ?? 7)
        _mode = State(initialValue: existing?.mode ?? .reducedDifficulty)
        _returnPace = State(initialValue: existing?.returnPace ?? .balanced)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOT FEELING 100%")
                .font(WSFont.display(30))
                .foregroundStyle(WSColor.text)
            if store.n100 != nil {
                Text("ACTIVE ADJUSTMENT")
                    .font(WSFont.mono(10))
                    .tracking(1.5)
                    .foregroundStyle(WSColor.accent)
                    .padding(.top, 12)
                WSOutlineButton(title: "END ADJUSTMENT") {
                    if store.endNotFeeling100() {
                        dismiss()
                    } else {
                        errorMessage = store.errorMessage
                        store.errorMessage = nil
                    }
                }
                .padding(.top, 10)
                .accessibilityIdentifier("n100_end_adjustment")
            }
            DatePicker(
                "Start date",
                selection: $startDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .tint(WSColor.accent)
            .padding(.top, 16)
            .accessibilityIdentifier("n100_start_date")
            HStack {
                Text("DAYS")
                    .font(WSFont.ui(14, weight: .heavy))
                Spacer()
                WSStepperControl(
                    valueText: "\(days)",
                    decrement: { days = max(3, days - 1) },
                    increment: { days = min(14, days + 1) }
                )
            }
            .padding(.top, 18)
            Text("MODE")
                .font(WSFont.mono(10))
                .tracking(1.5)
                .foregroundStyle(WSColor.accent)
                .padding(.top, 16)
            VStack(spacing: 8) {
                ForEach(N100Mode.allCases, id: \.self) { item in
                    WSSelectRow(title: item.title, selected: mode == item) { mode = item } accessory: { EmptyView() }
                }
            }
            .padding(.top, 10)
            Text("RETURN PACE")
                .font(WSFont.mono(10))
                .tracking(1.5)
                .foregroundStyle(WSColor.accent)
                .padding(.top, 16)
            HStack(spacing: 8) {
                ForEach(N100Return.allCases, id: \.self) { item in
                    WSChip(title: item.title, selected: returnPace == item) { returnPace = item }
                }
            }
            .padding(.top, 10)
            if let errorMessage {
                Text(errorMessage)
                    .font(WSFont.mono(12))
                    .foregroundStyle(WSColor.accent)
                    .padding(.top, 8)
            }
            WSPrimaryButton(title: store.n100 == nil ? "APPLY" : "UPDATE", height: 54, fontSize: 19) {
                let adjustment = N100Adjustment(start: startDate, dayCount: days, mode: mode, returnPace: returnPace)
                guard NotFeeling100Rules.isValidStart(start: startDate, dayCount: days) else {
                    errorMessage = "That start date isn't valid for this adjustment."
                    return
                }
                store.applyNotFeeling100(adjustment)
                if store.errorMessage == nil { dismiss() }
                else { errorMessage = store.errorMessage; store.errorMessage = nil }
            }
            .padding(.top, 20)
            .accessibilityIdentifier("n100_apply")
            if store.n100 != nil,
               let adjustment = store.n100,
               NotFeeling100Rules.canDiscardOnCreationDay(adjustment: adjustment, createdOn: Date()) {
                Button("DISCARD TODAY") {
                    if store.discardNotFeeling100IfCreationDay() {
                        dismiss()
                    } else {
                        errorMessage = store.errorMessage
                        store.errorMessage = nil
                    }
                }
                .font(WSFont.ui(12, weight: .heavy))
                .foregroundStyle(WSColor.destructive)
                .padding(.top, 12)
                .accessibilityIdentifier("n100_discard_today")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 52)
        .background(WSColor.bgSheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(WSColor.bgSheet)
        .onAppear {
            if let active = store.n100 {
                startDate = active.start
                days = active.dayCount
                mode = active.mode
                returnPace = active.returnPace
            }
        }
    }
}
