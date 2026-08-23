import SwiftUI
import WrathspeedCore

struct WeeklyCalendarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var weekOffset = 0
    @State private var selectedWorkout: ScheduledWorkout?
    @State private var pendingStart: WorkoutBlueprint?

    private var calendar: Calendar { Calendar.current }

    private var allowedOffsets: ClosedRange<Int> { -1...1 }

    private var weekStart: Date {
        let current = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: current) ?? current
    }

    var body: some View {
        WSScreen {
            HStack {
                Button("← PLAN") { dismiss() }
                    .wsType(.body, weight: .heavy)
                    .foregroundStyle(WSColor.text50)
                    .accessibilityLabel("Back to plan")
                Spacer()
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)

            Text("WEEKLY\nCALENDAR")
                .wsType(.displayM)
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)

            weekNavigation
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 16)

            weekStrip
                .padding(.top, 12)

            VStack(spacing: 0) {
                ForEach(weekWorkouts) { workout in
                    Button {
                        selectedWorkout = workout
                    } label: {
                        // The row is mostly Spacer, which is not hit-testable on its own,
                        // so the tap target has to be declared explicitly.
                        weekWorkoutRow(workout)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("weekly_calendar_workout_\(workout.id.uuidString)")
                }
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 18)
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(WSColor.bg.ignoresSafeArea())
        .sheet(item: $selectedWorkout, onDismiss: startPendingWorkout) { workout in
            WorkoutDetailSheet(workout: workout) { pendingStart = $0 }
        }
    }

    /// Runs once the detail sheet has actually gone, so RootView is free to present
    /// preflight.
    private func startPendingWorkout() {
        guard let blueprint = pendingStart else { return }
        pendingStart = nil
        store.presentPreflight(blueprint: blueprint)
    }

    private var weekNavigation: some View {
        // Three slots, so ViewThatFits directly rather than WSRow, which takes two. Stacked, the
        // week label goes above and the two buttons stay paired beneath it -- splitting PREV and
        // NEXT onto separate lines would read as two unrelated controls.
        ViewThatFits(in: .horizontal) {
            HStack {
                previousWeekButton
                Spacer(minLength: 12)
                weekLabelText
                Spacer(minLength: 12)
                nextWeekButton
            }
            VStack(spacing: 10) {
                weekLabelText
                HStack {
                    previousWeekButton
                    Spacer(minLength: 12)
                    nextWeekButton
                }
            }
        }
        .foregroundStyle(WSColor.accent)
        .frame(minHeight: 44)
    }

    private var previousWeekButton: some View {
        Button {
            weekOffset = max(allowedOffsets.lowerBound, weekOffset - 1)
        } label: {
            // The frame has to sit on the label: applied outside the Button it grows
            // the layout but leaves the button's own bounds, and so its hit and
            // accessibility frame, the size of the glyph run.
            Text("PREV WEEK")
                .wsType(.label, weight: .heavy)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(weekOffset <= allowedOffsets.lowerBound)
        .accessibilityIdentifier("weekly_calendar_prev_week")
        .accessibilityLabel("Previous week")
    }

    private var weekLabelText: some View {
        Text(weekLabel)
            .wsType(.metric)
            .foregroundStyle(WSColor.text45)
            .accessibilityLabel("Week \(weekLabel)")
    }

    private var nextWeekButton: some View {
        Button {
            weekOffset = min(allowedOffsets.upperBound, weekOffset + 1)
        } label: {
            Text("NEXT WEEK")
                .wsType(.label, weight: .heavy)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(weekOffset >= allowedOffsets.upperBound)
        .accessibilityIdentifier("weekly_calendar_next_week")
        .accessibilityLabel("Next week")
    }

    private var weekStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(dayStrip, id: \.date) { day in
                    VStack(spacing: 4) {
                        Text(day.label)
                            .wsType(.metricS)
                            .foregroundStyle(day.isToday ? WSColor.accent : WSColor.text40)
                        Circle()
                            .fill(day.hasWorkout ? WSColor.accent : WSColor.surface2)
                            .frame(width: 8, height: 8)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(day.isToday ? WSColor.accentTint : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("\(day.label) \(day.hasWorkout ? "has workout" : "rest")")
                }
            }
            .padding(.horizontal, WSSpace.gutter)
        }
    }

    private var weekWorkouts: [ScheduledWorkout] {
        let end = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return store.displayPlan?.workouts.filter { $0.date >= weekStart && $0.date < end } ?? []
            .sorted { $0.date < $1.date }
    }

    private var weekLabel: String {
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(WSFormat.monthDay(weekStart)) – \(WSFormat.monthDay(end))"
    }

    private var dayStrip: [(date: Date, label: String, hasWorkout: Bool, isToday: Bool)] {
        (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let hasWorkout = weekWorkouts.contains { calendar.isDate($0.date, inSameDayAs: date) }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE"
            return (date, formatter.string(from: date).uppercased(), hasWorkout, calendar.isDateInToday(date))
        }
    }

    private func weekWorkoutRow(_ workout: ScheduledWorkout) -> some View {
        WSRow(spacing: 10) {
            // Kept together so the stacked arrangement does not break this
            // group onto separate lines of its own.
            HStack(spacing: 10) {
                Text(String(WSFormat.weekdayDate(workout.date).prefix(3)))
                    .wsType(.metric, weight: .bold)
                    .foregroundStyle(WSColor.text45)
                    .frame(width: 34, alignment: .leading)
                Text(workout.blueprint.title.uppercased())
                    .wsType(.body, weight: .heavy)
                    .foregroundStyle(WSColor.text)
            }
        } trailing: {
            Text(WSFormat.distance(workout.blueprint.plannedDistanceMeters, unit: store.unit))
                .wsType(.metric)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
    }
}

struct MissedWorkSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let situation: MissedWorkSituation
    @State private var selectedChoice: MissedWorkChoice = .skipMissed
    @State private var preview: MissedWorkPreview?
    @State private var confirmedPreview: MissedWorkPreview?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MISSED WORK")
                .wsType(.displayS)
                .foregroundStyle(WSColor.text)
            Text("\(situation.missedWorkouts.count) session(s) need a decision.")
                .wsType(.metric)
                .foregroundStyle(WSColor.text45)
                .padding(.top, 8)

            VStack(spacing: 8) {
                choiceRow(.skipMissed, title: "SKIP MISSED WORK")
                choiceRow(.moveEligible, title: "MOVE ELIGIBLE WORK")
                if MissedWorkService.canExtend(plan: store.plan!) {
                    choiceRow(.extendPlan, title: "EXTEND PLAN")
                }
            }
            .padding(.top, 16)

            if let preview {
                Text(preview.description)
                    .wsType(.label, weight: .medium)
                    .foregroundStyle(WSColor.text70)
                    .padding(.top, 12)
            }
            if let errorMessage {
                Text(errorMessage)
                    .wsType(.metric)
                    .foregroundStyle(WSColor.accent)
                    .padding(.top, 8)
            }

            WSOutlineButton(title: "PREVIEW") {
                preview = store.previewMissedWork(choice: selectedChoice, situation: situation)
                confirmedPreview = preview
                errorMessage = nil
            }
            .padding(.top, 16)
            .accessibilityIdentifier("missed_work_preview")

            WSPrimaryButton(title: "APPLY") {
                do {
                    try store.applyMissedWork(choice: selectedChoice, situation: situation, preview: confirmedPreview)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .disabled(confirmedPreview == nil)
            .padding(.top, 10)
            .accessibilityIdentifier("missed_work_apply")
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 52)
        .background(WSColor.bgSheet.ignoresSafeArea())
    }

    private func choiceRow(_ choice: MissedWorkChoice, title: String) -> some View {
        WSSelectRow(title: title, selected: selectedChoice == choice) {
            selectedChoice = choice
            preview = nil
            confirmedPreview = nil
        } accessory: { EmptyView() }
        .accessibilityIdentifier("missed_work_choice_\(choiceAccessibilityID(choice))")
    }

    private func choiceAccessibilityID(_ choice: MissedWorkChoice) -> String {
        switch choice {
        case .skipMissed: "skip"
        case .moveEligible: "move"
        case .extendPlan: "extend"
        }
    }
}
