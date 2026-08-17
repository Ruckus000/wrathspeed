import SwiftUI
import WrathspeedCore

struct WorkoutMoveDateSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workout: ScheduledWorkout
    @State private var selectedDate: Date
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var allowOverride = false
    @State private var validationMessage: String?

    init(workout: ScheduledWorkout) {
        self.workout = workout
        _selectedDate = State(initialValue: workout.date)
        _reminderEnabled = State(initialValue: workout.reminderEnabled)
        let minutes = workout.scheduledTimeMinutes ?? (7 * 60)
        let base = Calendar.current.startOfDay(for: workout.date)
        _reminderTime = State(initialValue: Calendar.current.date(byAdding: .minute, value: minutes, to: base) ?? workout.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MOVE WORKOUT")
                .font(WSFont.display(30))
                .foregroundStyle(WSColor.text)
            Text(workout.blueprint.title.uppercased())
                .font(WSFont.mono(12))
                .foregroundStyle(WSColor.text45)
                .padding(.top, 8)
            DatePicker(
                "New date",
                selection: $selectedDate,
                in: Date()...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(WSColor.accent)
            .padding(.top, 12)
            .accessibilityIdentifier("move_workout_date_picker")
            .accessibilityLabel("Select new workout date")
            Toggle(isOn: $reminderEnabled) {
                Text("REMIND ME")
                    .font(WSFont.ui(12, weight: .heavy))
            }
            .tint(WSColor.accent)
            .padding(.top, 12)
            .accessibilityIdentifier("move_workout_reminder_toggle")
            if reminderEnabled {
                DatePicker(
                    "Reminder time",
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .tint(WSColor.accent)
                .padding(.top, 8)
                .accessibilityIdentifier("move_workout_time_picker")
            }
            if let validationMessage {
                Text(validationMessage)
                    .font(WSFont.mono(12))
                    .foregroundStyle(WSColor.accent)
                    .padding(.top, 8)
            }
            if let notice = store.reminderNotice {
                Text(notice)
                    .font(WSFont.mono(12))
                    .foregroundStyle(WSColor.text70)
                    .padding(.top, 8)
            }
            Toggle(isOn: $allowOverride) {
                Text("ALLOW QUALITY / LOAD WARNINGS")
                    .font(WSFont.ui(12, weight: .heavy))
            }
            .tint(WSColor.accent)
            .padding(.top, 12)
            .accessibilityIdentifier("move_workout_warning_override")
            WSPrimaryButton(title: "MOVE HERE") {
                let minutes = reminderEnabled ? reminderMinutes() : nil
                store.move(
                    workout,
                    to: selectedDate,
                    allowWarnings: allowOverride,
                    scheduledTimeMinutes: minutes,
                    reminderEnabled: reminderEnabled
                )
                if store.errorMessage == nil { dismiss() }
                else { validationMessage = store.errorMessage; store.errorMessage = nil }
            }
            .padding(.top, 16)
            .accessibilityIdentifier("move_workout_confirm")
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 40)
        .background(WSColor.bgSheet.ignoresSafeArea())
    }

    private func reminderMinutes() -> Int {
        let day = Calendar.current.startOfDay(for: selectedDate)
        let delta = reminderTime.timeIntervalSince(day)
        return max(0, min(Int(delta / 60), (24 * 60) - 1))
    }
}

struct ManagePlanView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var days: Set<Weekday>
    @State private var daysPerWeek: Int
    @State private var longRun: Weekday
    @State private var previewDiff: PlanScheduleDiff?
    @State private var errorMessage: String?

    init(profile: RunnerProfile) {
        _days = State(initialValue: Set(profile.availableWeekdays ?? [.tuesday, .thursday, .saturday, .sunday]))
        _daysPerWeek = State(initialValue: profile.daysPerWeek)
        _longRun = State(initialValue: profile.longRunWeekday)
    }

    var body: some View {
        WSScreen {
            HStack {
                Button("← BACK") { dismiss() }
                    .font(WSFont.ui(13, weight: .heavy))
                    .foregroundStyle(WSColor.text50)
                Spacer()
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)
            Text("MANAGE\nPLAN")
                .font(WSFont.display(42))
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
            Text("AVAILABLE RUN DAYS")
                .font(WSFont.ui(14, weight: .heavy))
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 20)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    WSChip(title: day.chipLabel, selected: days.contains(day)) {
                        toggle(day)
                    }
                    .accessibilityLabel("\(day.chipLabel) run day")
                }
            }
            .padding(.horizontal, WSSpace.gutter)
            HStack {
                Text("RUNS / WEEK")
                    .font(WSFont.ui(14, weight: .heavy))
                Spacer()
                WSStepperControl(
                    valueText: "\(daysPerWeek)",
                    decrement: { daysPerWeek = max(3, daysPerWeek - 1) },
                    increment: { daysPerWeek = min(6, daysPerWeek + 1) }
                )
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 16)
            Text("LONG RUN DAY")
                .font(WSFont.ui(14, weight: .heavy))
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(days.sorted(), id: \.self) { day in
                    WSChip(title: day.chipLabel, selected: longRun == day) { longRun = day }
                }
            }
            .padding(.horizontal, WSSpace.gutter)
            if let previewDiff, !previewDiff.isEmpty {
                Text("FUTURE CHANGES")
                    .font(WSFont.mono(10))
                    .tracking(1.5)
                    .foregroundStyle(WSColor.text40)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 18)
                VStack(alignment: .leading, spacing: 6) {
                    if !previewDiff.moved.isEmpty {
                        Text("\(previewDiff.moved.count) moved")
                    }
                    if !previewDiff.added.isEmpty {
                        Text("\(previewDiff.added.count) added")
                    }
                    if !previewDiff.removed.isEmpty {
                        Text("\(previewDiff.removed.count) removed")
                    }
                }
                .font(WSFont.mono(12))
                .foregroundStyle(WSColor.text45)
                .padding(.horizontal, WSSpace.gutter)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(WSFont.mono(12))
                    .foregroundStyle(WSColor.accent)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 8)
            }
            WSOutlineButton(title: "PREVIEW CHANGES") {
                do {
                    previewDiff = try store.managePlanSchedule(days: days, daysPerWeek: daysPerWeek, longRunDay: longRun)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 20)
            .accessibilityIdentifier("manage_plan_preview")
            WSPrimaryButton(title: "APPLY SCHEDULE") {
                guard previewDiff != nil else {
                    errorMessage = "Preview schedule changes before applying."
                    return
                }
                do {
                    try store.applyManagePlanSchedule(days: days, daysPerWeek: daysPerWeek, longRunDay: longRun)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 10)
            .padding(.bottom, 40)
            .accessibilityIdentifier("manage_plan_apply")
        }
    }

    private func toggle(_ day: Weekday) {
        if days.contains(day) {
            guard days.count > 3 else { return }
            days.remove(day)
            if longRun == day { longRun = days.sorted().last ?? .saturday }
        } else {
            days.insert(day)
        }
    }
}