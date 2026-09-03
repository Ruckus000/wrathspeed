import SwiftUI
import WrathspeedCore

/// Which quick action is asking for its parameter.
enum CoachQuickPicker: String, Identifiable {
    case longRun, treadmill, travel
    var id: String { rawValue }
}

/// One tappable row in a picker sheet. Frame and hit shape on the label, not the button --
/// on the button XCUITest measures the label's text height.
private struct CoachPickRow: View {
    var title: String
    var subtitle: String? = nil
    var identifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .wsType(.label, weight: .heavy, tracking: 1)
                    .foregroundStyle(WSColor.text)
                Spacer(minLength: 12)
                if let subtitle {
                    Text(subtitle)
                        .wsType(.metric)
                        .foregroundStyle(WSColor.text45)
                }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

private struct CoachPickerFrame<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .wsType(.displayS)
                    .foregroundStyle(WSColor.text)
                Text(subtitle)
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text45)
                    .padding(.top, 8)
                content
                    .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 40)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(WSColor.bgSheet.ignoresSafeArea())
    }
}

@MainActor
private func emptyNotice(_ text: String) -> some View {
    Text(text)
        .wsType(.body, weight: .medium)
        .foregroundStyle(WSColor.text70)
        .lineSpacing(3)
        .padding(.top, 8)
        .accessibilityIdentifier("coach_pick_empty")
}

struct WeekdayPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let options: [Weekday]
    let onPick: (Weekday) -> Void

    var body: some View {
        CoachPickerFrame(title: "MOVE LONG RUN", subtitle: "Pick one of your run days. The rest of the plan is regenerated around it.") {
            if options.isEmpty {
                emptyNotice("No other run day is available. Change your available days in Settings first.")
            }
            ForEach(options, id: \.self) { day in
                CoachPickRow(title: day.displayName.uppercased(), identifier: "coach_pick_weekday_\(day.displayName.lowercased())") {
                    dismiss()
                    onPick(day)
                }
            }
        }
    }
}

struct WorkoutPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let options: [ScheduledWorkout]
    let unit: DistanceUnit
    let onPick: (ScheduledWorkout) -> Void

    var body: some View {
        CoachPickerFrame(title: "TREADMILL", subtitle: "Pick the run to move indoors. Only its location changes.") {
            if options.isEmpty {
                emptyNotice("No outdoor run in the next two weeks.")
            }
            ForEach(Array(options.enumerated()), id: \.element.id) { index, workout in
                CoachPickRow(
                    title: WSFormat.weekdayDate(workout.date).uppercased(),
                    subtitle: "\(workout.blueprint.title.uppercased()) · \(WSFormat.distance(workout.blueprint.plannedDistanceMeters, unit: unit))",
                    identifier: "coach_pick_workout_\(index)"
                ) {
                    dismiss()
                    onPick(workout)
                }
            }
        }
    }
}

struct TravelDatesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: ([Date]) -> Void
    @State private var first: Date
    @State private var last: Date
    private let today = Calendar.current.startOfDay(for: Date())

    init(onPick: @escaping ([Date]) -> Void) {
        self.onPick = onPick
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        _first = State(initialValue: tomorrow)
        _last = State(initialValue: Calendar.current.date(byAdding: .day, value: 2, to: tomorrow) ?? tomorrow)
    }

    var body: some View {
        CoachPickerFrame(title: "TRAVEL DATES", subtitle: "First and last day away. Future runs are reshaped around them; the long run is kept.") {
            DatePicker("First day", selection: $first, in: today..., displayedComponents: .date)
                .datePickerStyle(.compact)
                .tint(WSColor.accent)
                .accessibilityIdentifier("coach_pick_travel_start")
            DatePicker("Last day", selection: $last, in: first..., displayedComponents: .date)
                .datePickerStyle(.compact)
                .tint(WSColor.accent)
                .padding(.top, 8)
                .accessibilityIdentifier("coach_pick_travel_end")
            WSPrimaryButton(title: "PREVIEW CHANGES", height: 54, role: .control) {
                dismiss()
                onPick(days())
            }
            .padding(.top, 20)
            .accessibilityIdentifier("coach_pick_travel_confirm")
        }
        .onChange(of: first) { _, newValue in
            if last < newValue { last = newValue }
        }
    }

    /// Every day from the first to the last, capped at sixty so a mis-set year cannot ask the
    /// rule to reshape a whole plan.
    private func days() -> [Date] {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: max(first, last))
        var dates: [Date] = []
        while day <= end, dates.count < 60 {
            dates.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return dates
    }
}
