import SwiftUI
import WrathspeedCore

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var showN100 = false
    @State private var showInstant = false
    @State private var guidedPlayer: GuidedPlayer?

    private enum GuidedPlayer: Identifiable {
        case strength(StrengthSession)
        case mobility(MobilitySession)

        var id: String {
            switch self {
            case .strength(let session):
                return "strength-\(session.id)"
            case .mobility(let session):
                return "mobility-\(session.routineID)"
            }
        }
    }

    var body: some View {
        ZStack {
            WSScreen {
                header
                if let pending = store.pendingSuggestion {
                    suggestionCard(pending)
                }
                WSEyebrow(text: orderEyebrow)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 26)
                Text(orderTitle)
                    .font(WSFont.display(58))
                    .foregroundStyle(WSColor.text)
                    .lineSpacing(-2)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 6)
                Text(orderMeta)
                    .font(WSFont.ui(14, weight: .semibold))
                    .foregroundStyle(WSColor.text70)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 14)
                if store.dataDensity == .detailed, let steps = stepsLine {
                    Text(steps)
                        .font(WSFont.mono(12, weight: .medium))
                        .foregroundStyle(WSColor.text40)
                        .padding(.horizontal, WSSpace.gutter)
                        .padding(.top, 8)
                }
                primaryAction
                if let strength = store.resumableStrengthSession ?? store.todaysStrength.first {
                    strengthRow(strength, isResume: store.resumableStrengthSession != nil)
                }
                mobilitySection
                HStack {
                    Button("NOT FEELING 100%?") { showN100 = true }
                        .font(WSFont.ui(11, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(WSColor.text45)
                    Spacer()
                    Button("+ INSTANT RUN") { showInstant = true }
                        .font(WSFont.ui(11, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(WSColor.accent)
                }
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 14)
                weekBar
            }
        }
        .sheet(isPresented: $showN100) { NotFeeling100View() }
        .sheet(isPresented: $showInstant) { InstantRunView() }
        .fullScreenCover(item: $guidedPlayer) { player in
            switch player {
            case .strength(let session):
                StrengthPlayerView(session: session)
            case .mobility(let session):
                MobilityPlayerView(session: session)
            }
        }
        .onAppear { presentMobilityPreRunForUITestingIfNeeded() }
    }

    private var header: some View {
        HStack {
            Text(WSFormat.weekdayDate(Date()))
                .font(WSFont.mono(12))
                .tracking(1.5)
                .foregroundStyle(WSColor.text50)
            Spacer()
            Text("STREAK \(store.streak)")
                .font(WSFont.ui(11, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(WSColor.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(Capsule().stroke(WSColor.accent, lineWidth: 1.5))
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 10)
    }

    private func suggestionCard(_ pending: VDOTSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WSEyebrow(text: "PACE SUGGESTION")
            Text(pending.reason)
                .font(WSFont.ui(12, weight: .medium))
                .foregroundStyle(WSColor.text70)
                .padding(.top, 6)
            Text("VDOT \(WSFormat.vdot(store.profile?.vdot ?? 0)) → \(WSFormat.vdot(pending.newVDOT))")
                .font(WSFont.display(22))
                .foregroundStyle(WSColor.text)
                .padding(.top, 8)
            HStack(spacing: 10) {
                Button("ACCEPT") { store.acceptVDOTSuggestion() }
                    .font(WSFont.ui(12, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(WSColor.accent, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Button("NOT NOW") { store.declineVDOTSuggestion() }
                    .font(WSFont.ui(12, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(WSColor.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1.5)
                    )
            }
            .padding(.top, 12)
        }
        .padding(16)
        .overlay(
            RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                .stroke(WSColor.accent, lineWidth: 1.5)
        )
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 18)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if let workout = store.todaysRuns.first {
            WSPrimaryButton(title: "START RUN →", height: 64, fontSize: 24) {
                store.presentPreflight(blueprint: workout.blueprint)
            }
            .accessibilityLabel("Start today's run")
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 20)
        } else if let done = store.todaysCompletedRuns.first, let result = done.result {
            VStack(alignment: .leading, spacing: 6) {
                Text("MISSION COMPLETE ✓")
                    .font(WSFont.ui(12, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(WSColor.accent)
                Text("\(WSFormat.distance(result.distanceMeters, unit: store.unit)) · \(result.averagePaceSecPerKm.map { WSFormat.pace($0, unit: store.unit) } ?? "—")")
                    .font(WSFont.ui(13, weight: .semibold))
                    .foregroundStyle(WSColor.text70)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                    .stroke(WSColor.accent, lineWidth: 1.5)
            )
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 20)
        } else if isRestDay {
            Button {
                showInstant = true
            } label: {
                Text("+ ADD AN INSTANT RUN")
                    .font(WSFont.ui(14, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .overlay(
                        RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundStyle(Color.white.opacity(0.25))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 20)
        }
    }

    private func strengthRow(_ session: StrengthSession, isResume: Bool) -> some View {
        Button {
            guidedPlayer = .strength(session)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PLUS: \(session.title.uppercased())")
                        .font(WSFont.ui(13, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(WSColor.text)
                    Text("\(session.durationMinutes) MIN · \(session.sets.count) EXERCISES")
                        .font(WSFont.ui(11, weight: .medium))
                        .foregroundStyle(WSColor.text45)
                }
                Spacer()
                Text(isResume ? "RESUME →" : "GO →")
                    .font(WSFont.ui(13, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(WSColor.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                    .stroke(WSColor.border, lineWidth: 1)
            )
            // A stroke overlay draws no fill, so the row's interior is not hit-testable
            // without this.
            .contentShape(RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("strength-row-\(session.id)")
        .accessibilityLabel(isResume ? "Resume \(session.title)" : "Start \(session.title)")
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 12)
    }

    private var mobilitySection: some View {
        let sessions = store.mobilitySessionsForToday()
        return Group {
            if !sessions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    WSEyebrow(text: "MOBILITY")
                        .padding(.horizontal, WSSpace.gutter)
                    ForEach(sessions) { session in
                        mobilityRow(session)
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private func mobilityRow(_ session: MobilitySession) -> some View {
        let isResume = store.isMobilityRoutineResumable(session)
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title.uppercased())
                    .font(WSFont.ui(13, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(WSColor.text)
                Text("\(session.durationMinutes) MIN · \(session.movements.count) MOVEMENTS")
                    .font(WSFont.ui(11, weight: .medium))
                    .foregroundStyle(WSColor.text45)
            }
            Spacer()
            Button {
                guidedPlayer = .mobility(session)
            } label: {
                // The frame belongs on the label. Applied outside the Button it left the
                // button's own bounds the size of the glyph run, about 14pt tall, which is
                // what made this row intermittently impossible to tap.
                Text(isResume ? "RESUME →" : "GO →")
                    .font(WSFont.ui(13, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(WSColor.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(isResume ? "Resume \(session.title)" : "Start \(session.title)")
            .accessibilityIdentifier("mobility-row-\(session.routineID)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(
            RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                .stroke(WSColor.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { guidedPlayer = .mobility(session) }
        .padding(.horizontal, WSSpace.gutter)
    }

    private var weekBar: some View {
        let mileage = weekMileage
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("THIS WEEK")
                Spacer()
                Text("\(WSFormat.distance(mileage.done, unit: store.unit)) / \(WSFormat.distanceValue(mileage.planned, unit: store.unit, fraction: 0)) \(WSFormat.unitSuffix(store.unit))")
            }
            .font(WSFont.mono(10))
            .foregroundStyle(WSColor.text40)
            HStack(spacing: 8) {
                ForEach(weekCells) { cell in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(cell.fill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(cell.stroke, lineWidth: cell.stroke == .clear ? 0 : 1.5)
                            )
                            .frame(height: 34)
                        Text(cell.letter)
                            .font(WSFont.mono(9))
                            .foregroundStyle(cell.isToday ? WSColor.accent : WSColor.text40)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(cell.letter), \(cell.completed ? "completed" : cell.scheduled ? "scheduled" : "rest")")
                }
            }
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(WSColor.hairlineStrong).frame(height: 1)
                .padding(.horizontal, WSSpace.gutter)
        }
        .padding(.top, 20)
    }

    private var orderEyebrow: String {
        if isN100Active { return "NOT 100% ACTIVE" }
        return "TODAY'S ORDER"
    }

    private var orderTitle: String {
        if let workout = store.todaysRuns.first ?? store.todaysCompletedRuns.first {
            return workout.blueprint.title.uppercased()
        }
        if isN100Active, store.n100?.mode == .pause { return "REST. RECOVER." }
        return "REST DAY."
    }

    private var orderMeta: String {
        if let workout = store.todaysRuns.first ?? store.todaysCompletedRuns.first {
            let distance = WSFormat.distance(workout.blueprint.plannedDistanceMeters, unit: store.unit)
            let pace = targetPace(for: workout).map { "TARGET \(WSFormat.pace($0, unit: store.unit))" } ?? "NO PACE TARGET"
            return "\(distance) · \(pace) · \(workout.blueprint.kind.title.uppercased())"
        }
        return "Rest day. Add an instant run if you want extra work."
    }

    private var stepsLine: String? {
        guard let workout = store.todaysRuns.first ?? store.todaysCompletedRuns.first else { return nil }
        let parts = workout.blueprint.steps.prefix(3).map { step in
            switch step.target {
            case .distance(let meters): "\(WSFormat.distanceValue(meters, unit: store.unit, fraction: 0)) \(WSFormat.unitSuffix(store.unit)) \(shortStep(step.name))"
            case .duration(let seconds): "\(Units.formatDuration(seconds)) \(shortStep(step.name))"
            }
        }
        return parts.joined(separator: " → ")
    }

    private func shortStep(_ name: String) -> String {
        name.uppercased()
    }

#if DEBUG
    private func presentMobilityPreRunForUITestingIfNeeded() {
        guard UITestingSupport.shouldPresentMobilityPreRun else { return }
        guard guidedPlayer == nil else { return }
        guard let session = store.mobilitySessionsForToday().first(where: { $0.routineID == "pre_run" }) else { return }
        guidedPlayer = .mobility(session)
    }
#else
    private func presentMobilityPreRunForUITestingIfNeeded() {}
#endif

    private var isRestDay: Bool {
        store.todaysRuns.isEmpty && store.todaysCompletedRuns.isEmpty
    }

    private var isN100Active: Bool {
        guard let n100 = store.n100 else { return false }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return today >= cal.startOfDay(for: n100.start) && today < n100.returnEnd(calendar: cal)
    }

    private func targetPace(for workout: ScheduledWorkout) -> TimeInterval? {
        WorkoutPaceTarget.targetPaceSecPerKm(blueprint: workout.blueprint, zones: store.zones)
    }

    private var weekMileage: (done: Double, planned: Double) {
        guard let plan = store.plan else { return (0, 0) }
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date())
        let week = plan.workouts.filter { $0.blueprint.kind.isRunning && (interval?.contains($0.date) ?? false) }
        let planned = week.reduce(0) { $0 + $1.blueprint.plannedDistanceMeters }
        let done = week.filter { $0.status == .completed }.reduce(0) { $0 + ($1.result?.distanceMeters ?? $1.blueprint.plannedDistanceMeters) }
        return (done, planned)
    }

    private var weekCells: [WeekCell] {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return (0..<7).map { offset in
            let date = cal.date(byAdding: .day, value: offset, to: start) ?? start
            let letter = String(WSFormat.weekdayDate(date).prefix(1))
            let isToday = cal.isDateInToday(date)
            let workouts = store.plan?.workouts.filter { cal.isDate($0.date, inSameDayAs: date) && $0.blueprint.kind.isRunning } ?? []
            let completed = workouts.contains { $0.status == .completed }
            let scheduled = workouts.contains { $0.status == .scheduled || $0.status == .convertedToEasy }
            let fill: Color = {
                if completed { return isToday ? WSColor.accent : WSColor.accent.opacity(0.45) }
                if scheduled { return WSColor.surface1 }
                return WSColor.surface3
            }()
            let stroke: Color = isToday && !completed ? WSColor.accent : .clear
            return WeekCell(id: offset, letter: letter, completed: completed, scheduled: scheduled, fill: fill, stroke: stroke, isToday: isToday)
        }
    }
}

private struct WeekCell: Identifiable {
    var id: Int
    var letter: String
    var completed: Bool
    var scheduled: Bool
    var fill: Color
    var stroke: Color
    var isToday: Bool
}
