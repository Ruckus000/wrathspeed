import SwiftUI
import WrathspeedCore

struct PlanView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedWorkout: ScheduledWorkout?
    @State private var selectedWeek: Date?
    @State private var showMissedWork = false

    var body: some View {
        NavigationStack {
            WSScreen {
                if let goal = store.plan?.goal {
                    WSEyebrow(text: goal.kind.displayName.uppercased())
                        .padding(.horizontal, WSSpace.gutter)
                        .padding(.top, 10)
                }
                weekHeadline
                if store.lastUndoDescription != nil {
                    Button("UNDO LAST CHANGE") { store.undoLastPlanChange() }
                        .font(WSFont.ui(12, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(WSColor.accent)
                        .padding(.horizontal, WSSpace.gutter)
                        .padding(.top, 8)
                        .accessibilityLabel("Undo last plan change")
                }
                NavigationLink {
                    WeeklyCalendarView()
                } label: {
                    Text("WEEKLY CALENDAR")
                        .font(WSFont.ui(12, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(WSColor.text50)
                }
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, store.lastUndoDescription != nil ? 4 : 8)
                .frame(minHeight: 44)
                .accessibilityIdentifier("plan_weekly_calendar")
                .accessibilityLabel("Open weekly calendar")
                NavigationLink {
                    if let profile = store.profile {
                        ManagePlanView(profile: profile)
                    }
                } label: {
                    Text("MANAGE PLAN")
                        .font(WSFont.ui(12, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(WSColor.text50)
                }
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, store.lastUndoDescription != nil ? 4 : 8)
                .frame(minHeight: 44)
                .accessibilityLabel("Manage plan schedule")
                weekCalendar
                if let situation = store.missedWorkSituation {
                    Button("REVIEW MISSED WORK (\(situation.missedWorkouts.count))") {
                        showMissedWork = true
                    }
                    .font(WSFont.ui(12, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(WSColor.accent)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 10)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("plan_missed_work")
                }
                WSProgressBar(progress: weekProgress)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 14)
                Text(planMeta)
                    .font(WSFont.mono(12))
                    .foregroundStyle(WSColor.text45)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 10)
                VStack(spacing: 0) {
                    ForEach(currentWeekWorkouts) { workout in
                        Button {
                            selectedWorkout = workout
                        } label: {
                            // The row is mostly Spacer, which is not hit-testable on its
                            // own, so the tap target has to be declared explicitly.
                            dayRow(workout)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("plan_workout_\(workout.blueprint.kind.rawValue)")
                    }
                }
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 18)
                if upcomingWeeks.count > 1 {
                    Text("UPCOMING")
                        .font(WSFont.mono(10))
                        .tracking(1)
                        .foregroundStyle(WSColor.text40)
                        .padding(.horizontal, WSSpace.gutter)
                        .padding(.top, 18)
                    VStack(spacing: 0) {
                        ForEach(upcomingWeeks.dropFirst(), id: \.start) { week in
                            Button {
                                selectedWeek = week.start
                            } label: {
                                HStack {
                                    Text(weekLabel(week.start, workouts: week.workouts))
                                        .font(WSFont.ui(13, weight: .bold))
                                        .foregroundStyle(Color.white.opacity(0.65))
                                    Spacer()
                                    Text("\(WSFormat.distance(week.workouts.reduce(0) { $0 + $1.blueprint.plannedDistanceMeters }, unit: store.unit)) ›")
                                        .font(WSFont.mono(12))
                                        .foregroundStyle(WSColor.text)
                                }
                                .padding(.vertical, 11)
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
                        }
                    }
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedWeek) { start in
                WeekDetailView(weekStart: start)
            }
            .sheet(item: $selectedWorkout) { workout in
                WorkoutDetailSheet(workout: workout)
            }
            .sheet(isPresented: $showMissedWork) {
                if let situation = store.missedWorkSituation {
                    MissedWorkSheet(situation: situation)
                }
            }
        }
    }

    private var weekCalendar: some View {
        let days = weekDayStrip()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.date) { day in
                    VStack(spacing: 4) {
                        Text(day.label)
                            .font(WSFont.mono(10))
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
        .padding(.top, 12)
    }

    private func weekDayStrip() -> [(date: Date, label: String, hasWorkout: Bool, isToday: Bool)] {
        let cal = Calendar.current
        let start = groups.first { week in
            let end = cal.date(byAdding: .day, value: 7, to: week.start) ?? week.start
            let today = Date()
            return today >= week.start && today < end
        }?.start ?? cal.startOfDay(for: Date())
        return (0..<7).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            let hasWorkout = currentWeekWorkouts.contains { cal.isDate($0.date, inSameDayAs: date) }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE"
            return (date, formatter.string(from: date).uppercased(), hasWorkout, cal.isDateInToday(date))
        }
    }

    private var weekHeadline: some View {
        let pair = store.currentWeekIndex()
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("WEEK \(pair.current)")
                .foregroundStyle(WSColor.text)
            Text("/\(pair.total)")
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .font(WSFont.display(60))
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 4)
    }

    private var weekProgress: Double {
        let pair = store.currentWeekIndex()
        return Double(pair.current) / Double(max(pair.total, 1))
    }

    private var planMeta: String {
        guard let goal = store.plan?.goal else { return "" }
        var parts: [String] = []
        if let race = goal.raceDate {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: race)).day ?? 0
            parts.append("RACE \(WSFormat.monthDay(race))")
            parts.append("\(max(0, days)) DAYS OUT")
        } else {
            parts.append("\(goal.weekCount) WEEKS")
        }
        let planned = currentWeekWorkouts.reduce(0) { $0 + $1.blueprint.plannedDistanceMeters }
        parts.append("\(WSFormat.distance(planned, unit: store.unit)) THIS WEEK")
        return parts.joined(separator: " · ")
    }

    private var groups: [(start: Date, workouts: [ScheduledWorkout])] { store.weekGroups() }

    private var currentWeekWorkouts: [ScheduledWorkout] {
        let today = Date()
        return groups.first { week in
            let end = Calendar.current.date(byAdding: .day, value: 7, to: week.start) ?? week.start
            return today >= week.start && today < end
        }?.workouts ?? groups.first?.workouts ?? []
    }

    private var upcomingWeeks: [(start: Date, workouts: [ScheduledWorkout])] {
        groups.filter { $0.start >= (Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()) }
    }

    private func dayRow(_ workout: ScheduledWorkout) -> some View {
        let isToday = Calendar.current.isDateInToday(workout.date)
        let completed = workout.status == .completed
        let skipped = workout.status == .skipped
        let converted = workout.status == .convertedToEasy
        let title: String = {
            if skipped { return "\(workout.blueprint.title.uppercased()) — SKIPPED" }
            if converted { return "\(workout.blueprint.title.uppercased()) (CONVERTED)" }
            return workout.blueprint.title.uppercased()
        }()
        return HStack(spacing: 10) {
            Text(weekday(workout.date))
                .font(WSFont.mono(11, weight: .bold))
                .foregroundStyle(isToday ? WSColor.accent : WSColor.text45)
                .frame(width: 34, alignment: .leading)
            Text(title)
                .font(WSFont.ui(15, weight: completed ? .bold : .heavy))
                .strikethrough(completed)
                .foregroundStyle(WSColor.text)
                .lineLimit(1)
            if workout.blueprint.kind.isQuality, !converted {
                Text("Q")
                    .font(WSFont.ui(10, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(WSColor.accent, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            Spacer()
            Text(WSFormat.distance(workout.blueprint.plannedDistanceMeters, unit: store.unit))
                .font(WSFont.mono(12))
                .foregroundStyle(WSColor.text)
        }
        .padding(.vertical, 13)
        .opacity(completed || skipped ? 0.45 : 1)
        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
    }

    private func weekday(_ date: Date) -> String {
        String(WSFormat.weekdayDate(date).prefix(3))
    }

    private func weekLabel(_ start: Date, workouts: [ScheduledWorkout]) -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(WSFormat.monthDay(start)) – \(WSFormat.monthDay(end))".uppercased()
    }
}

struct WeekDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let weekStart: Date

    var body: some View {
        WSScreen {
            Button("← PLAN") { dismiss() }
                .font(WSFont.ui(13, weight: .heavy))
                .tracking(1)
                .foregroundStyle(WSColor.text50)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 8)
            WSEyebrow(text: eyebrow)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 18)
            Text(title)
                .font(WSFont.display(52))
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 4)
            Text(meta)
                .font(WSFont.mono(12))
                .foregroundStyle(WSColor.text45)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
            VStack(spacing: 0) {
                ForEach(workouts) { workout in
                    HStack(alignment: .top, spacing: 14) {
                        Text(String(WSFormat.weekdayDate(workout.date).prefix(3)))
                            .font(WSFont.mono(11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .frame(width: 34, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.blueprint.title.uppercased())
                                .font(WSFont.ui(15, weight: .heavy))
                                .foregroundStyle(WSColor.text)
                            Text(subline(workout))
                                .font(WSFont.mono(11, weight: .medium))
                                .foregroundStyle(WSColor.text40)
                        }
                        Spacer()
                        Text(WSFormat.distance(workout.blueprint.plannedDistanceMeters, unit: store.unit))
                            .font(WSFont.mono(12))
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
                }
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 20)
            VStack(alignment: .leading, spacing: 6) {
                WSEyebrow(text: "PROGRESSION RULE")
                Text(rule)
                    .font(WSFont.ui(12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineSpacing(4)
            }
            .padding(16)
            .overlay(
                RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                    .stroke(WSColor.border, lineWidth: 1)
            )
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 22)
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(WSColor.bg.ignoresSafeArea())
    }

    private var workouts: [ScheduledWorkout] {
        store.weekGroups().first { Calendar.current.isDate($0.start, inSameDayAs: weekStart) }?.workouts ?? []
    }

    private var weekIndex: Int {
        store.weekGroups().firstIndex { Calendar.current.isDate($0.start, inSameDayAs: weekStart) } ?? 0
    }

    private var totalWeeks: Int { max(1, store.plan?.goal.weekCount ?? 1) }

    private var eyebrow: String {
        PlanGenerator.weekEyebrow(weekIndex: weekIndex, totalWeeks: totalWeeks)
    }

    private var title: String {
        "WEEK \(weekIndex + 1)"
    }

    private var meta: String {
        let miles = workouts.reduce(0) { $0 + $1.blueprint.plannedDistanceMeters }
        return "\(WSFormat.monthDay(weekStart)) · \(WSFormat.distance(miles, unit: store.unit))"
    }

    private var rule: String {
        PlanGenerator.progressionRule(weekIndex: weekIndex, totalWeeks: totalWeeks, kind: store.plan?.goal.kind ?? .fiveK)
    }

    private func subline(_ workout: ScheduledWorkout) -> String {
        workout.blueprint.steps.map(\.name).prefix(2).joined(separator: " · ").uppercased()
    }
}

struct WorkoutDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workout: ScheduledWorkout
    @State private var showMoveSheet = false
    @State private var selectedRoutine: MobilityRoutine?

    var body: some View {
        // Scrollable: the prep and recovery block can push this past the medium detent,
        // and everything below the fold would otherwise be unreachable.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(workout.blueprint.title.uppercased())
                        .font(WSFont.display(32))
                        .foregroundStyle(WSColor.text)
                    Spacer()
                    Button("✕") { dismiss() }
                        .font(WSFont.ui(13, weight: .heavy))
                        .foregroundStyle(WSColor.text40)
                }
                Text(meta)
                    .font(WSFont.mono(12))
                    .foregroundStyle(WSColor.text50)
                    .padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(workout.blueprint.steps) { step in
                        HStack {
                            Text(step.name)
                                .font(WSFont.ui(14, weight: .bold))
                            Spacer()
                            Text(stepLabel(step))
                                .font(WSFont.mono(11))
                                .foregroundStyle(WSColor.text50)
                        }
                        .padding(.vertical, 11)
                        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
                    }
                }
                .padding(.top, 16)
                if workout.status == .scheduled || workout.status == .convertedToEasy {
                    WSPrimaryButton(title: "START", height: 56, fontSize: 20) {
                        store.presentPreflight(blueprint: workout.blueprint)
                    }
                    .padding(.top, 18)
                    .accessibilityLabel("Start workout")
                }
                HStack(spacing: 10) {
                    outline("MOVE DATE") { showMoveSheet = true }
                        .accessibilityIdentifier("workout_move_date")
                    Button("SKIP") {
                        store.skip(workout)
                        dismiss()
                    }
                    .font(WSFont.ui(12, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(WSColor.destructive)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .overlay(
                        RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                            .stroke(WSColor.destructive.opacity(0.6), lineWidth: 1.5)
                    )
                    if workout.blueprint.kind.isQuality {
                        outline("CONVERT TO EASY") {
                            store.skip(workout, convertQuality: true)
                            dismiss()
                        }
                    }
                }
                .padding(.top, 10)
                if !routines.isEmpty {
                    Text("PREP AND RECOVERY")
                        .font(WSFont.ui(12, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(WSColor.text50)
                        .padding(.top, 22)
                        .accessibilityIdentifier("workout_prep_and_recovery")
                    VStack(spacing: 0) {
                        ForEach(routines) { routine in
                            Button { selectedRoutine = routine } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(routine.title.uppercased())
                                            .font(WSFont.ui(14, weight: .bold))
                                            .foregroundStyle(WSColor.text)
                                        Text("\(routine.items.count) MOVEMENTS · \(routine.totalSeconds / 60) MIN")
                                            .font(WSFont.mono(11))
                                            .foregroundStyle(WSColor.text50)
                                    }
                                    Spacer()
                                    Text("›")
                                        .font(WSFont.ui(14, weight: .heavy))
                                        .foregroundStyle(WSColor.text40)
                                }
                                .padding(.vertical, 11)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(WSColor.hairline).frame(height: 1)
                                }
                            }
                            .accessibilityIdentifier("workout_routine_\(routine.phase.rawValue)")
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 52)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(WSColor.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(WSColor.bgSheet)
        .sheet(isPresented: $showMoveSheet) {
            WorkoutMoveDateSheet(workout: workout)
        }
        .sheet(item: $selectedRoutine) { routine in
            NavigationStack { MobilityRoutineView(routine: routine) }
        }
    }

    /// Warm-up, drills and cool-down for this session. Quality days are the only ones
    /// that get a drill block; see MobilityPlanner.
    private var routines: [MobilityRoutine] {
        MobilityPlanner.routines(for: workout.blueprint.kind, catalog: store.movementCatalog)
    }

    private var meta: String {
        let loc = workout.blueprint.location.title.uppercased()
        let q = workout.blueprint.kind.isQuality ? " · Q SESSION" : ""
        return "\(WSFormat.weekdayDate(workout.date)) · \(loc)\(q)"
    }

    private func stepLabel(_ step: WorkoutStep) -> String {
        switch step.target {
        case .distance(let meters): WSFormat.distance(meters, unit: store.unit)
        case .duration(let seconds): Units.formatDuration(seconds)
        }
    }

    private func outline(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(WSFont.ui(11, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(WSColor.text)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .overlay(
                RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
            )
    }
}
