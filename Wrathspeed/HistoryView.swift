import MapKit
import SwiftUI
import WrathspeedCore

struct HistoryView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            WSScreen {
                Text("HISTORY")
                    .font(WSFont.display(44))
                    .foregroundStyle(WSColor.text)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 10)
                if let recap = lastWeekRecap {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recap.eyebrow)
                            .font(WSFont.ui(11, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(Color.white.opacity(0.75))
                        Text(recap.headline)
                            .font(WSFont.display(26))
                            .foregroundStyle(.white)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WSColor.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 18)
                }
                VStack(spacing: 0) {
                    ForEach(store.results, id: \.workoutID) { result in
                        NavigationLink {
                            RunDetailView(result: result)
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(title(for: result))
                                        .font(WSFont.ui(15, weight: .heavy))
                                        .foregroundStyle(WSColor.text)
                                    Spacer()
                                    Text("\(WSFormat.weekdayDate(result.startedAt)) ›")
                                        .font(WSFont.mono(10))
                                        .foregroundStyle(WSColor.text40)
                                }
                                HStack(spacing: 16) {
                                    Text(WSFormat.distance(result.distanceMeters, unit: store.unit))
                                    if let pace = result.averagePaceSecPerKm {
                                        Text(WSFormat.pace(pace, unit: store.unit))
                                    }
                                }
                                .font(WSFont.mono(13))
                                .foregroundStyle(Color.white.opacity(0.75))
                                .padding(.top, 6)
                                if let comparison = store.comparison(for: result) {
                                    Text(comparison)
                                        .font(WSFont.mono(11, weight: .medium))
                                        .foregroundStyle(WSColor.accent)
                                        .padding(.top, 5)
                                }
                            }
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
                    }
                }
                .padding(.horizontal, WSSpace.gutter)
                .padding(.bottom, 24)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func title(for result: WorkoutResult) -> String {
        store.plan?.workouts.first { $0.blueprint.id == result.workoutID || $0.id == result.workoutID }?
            .blueprint.title.uppercased() ?? "RUN"
    }

    private var lastWeekRecap: (eyebrow: String, headline: String)? {
        let cal = Calendar.current
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
              let lastStart = cal.date(byAdding: .day, value: -7, to: thisWeek)
        else { return nil }
        let lastEnd = thisWeek
        let weekWorkouts = store.plan?.workouts.filter {
            $0.date >= lastStart && $0.date < lastEnd && $0.blueprint.kind.isRunning
        } ?? []
        guard !weekWorkouts.isEmpty else { return nil }
        let done = weekWorkouts.filter { $0.status == .completed }
        let miles = done.reduce(0) { $0 + ($1.result?.distanceMeters ?? $1.blueprint.plannedDistanceMeters) }
        let groups = store.weekGroups()
        let weekNumber = (groups.firstIndex { cal.isDate($0.start, inSameDayAs: lastStart) } ?? 0) + 1
        let excuse = done.count == weekWorkouts.count ? "NO EXCUSES." : "KEEP GOING."
        return (
            "LAST WEEK — WEEK \(weekNumber)",
            "\(done.count)/\(weekWorkouts.count) SESSIONS. \(WSFormat.distance(miles, unit: store.unit)). \(excuse)"
        )
    }
}

struct RunDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let result: WorkoutResult

    var body: some View {
        WSScreen {
            HStack {
                Button("← HISTORY") { dismiss() }
                    .font(WSFont.ui(13, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(WSColor.text50)
                Spacer()
                Text(WSFormat.weekdayDate(result.startedAt))
                    .font(WSFont.mono(11))
                    .foregroundStyle(WSColor.text40)
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)
            Text(title)
                .font(WSFont.display(46))
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 18)
            HStack {
                stat("DISTANCE", WSFormat.distanceValue(result.distanceMeters, unit: store.unit))
                stat("TIME", WSFormat.duration(result.duration))
                stat("AVG PACE", result.averagePaceSecPerKm.map { WSFormat.paceClock($0, unit: store.unit) } ?? "—", accent: true)
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(WSColor.hairlineStrong).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairlineStrong).frame(height: 1) }
            .padding(.top, 22)
            .padding(.horizontal, WSSpace.gutter)
            if let comparison = store.comparison(for: result) {
                Text(comparison)
                    .font(WSFont.mono(11))
                    .foregroundStyle(WSColor.accent)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 14)
            }
            if let route = result.route, route.count > 1 {
                Map(initialPosition: .region(region(for: route))) {
                    MapPolyline(coordinates: route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(WSColor.accent, lineWidth: 4)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous))
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 16)
            }
            let splits = store.resolvedSplits(for: result)
            if !splits.isEmpty {
                Text("SPLITS · VS TARGET")
                    .font(WSFont.mono(10))
                    .tracking(1.5)
                    .foregroundStyle(WSColor.text40)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 22)
                VStack(spacing: 0) {
                    ForEach(splits, id: \.index) { split in
                        splitRow(split)
                    }
                }
                .padding(.horizontal, WSSpace.gutter)
            }
            Text("SESSION")
                .font(WSFont.mono(10))
                .tracking(1.5)
                .foregroundStyle(WSColor.text40)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 22)
            VStack(spacing: 0) {
                WSHairlineRow(label: "SOURCE", value: result.source.displayName.uppercased())
                WSHairlineRow(label: "MATCH", value: matchLabel)
                WSHairlineRow(label: "AVG HR", value: result.heartRateAverage.map { "\(Int($0.rounded()))" } ?? "—")
                WSHairlineRow(label: "LOCATION", value: result.location.title.uppercased())
                WSHairlineRow(label: "HEALTH SYNC", value: result.healthSync.state.title.uppercased(), valueColor: WSColor.accent, showDivider: false)
            }
            .padding(.horizontal, WSSpace.gutter)
            if result.matchInfo.state == .suggested, let suggestedID = result.matchInfo.suggestedWorkoutID {
                matchSuggestionCard(suggestedID: suggestedID)
            } else if result.matchInfo.state == .matched {
                WSOutlineButton(title: "UNMATCH FROM PLAN") {
                    store.unmatchHealthResult(result.workoutID)
                }
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
            }
            Spacer(minLength: 30)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(WSColor.bg.ignoresSafeArea())
    }

    private var title: String {
        store.plan?.workouts.first { $0.blueprint.id == result.workoutID || $0.id == result.workoutID }?
            .blueprint.title.uppercased() ?? "RUN"
    }

    private var matchLabel: String {
        switch result.matchInfo.state {
        case .unmatched: "UNMATCHED"
        case .suggested: "SUGGESTED"
        case .matched: "MATCHED"
        case .ignored: "KEPT UNMATCHED"
        }
    }

    private func matchSuggestionCard(suggestedID: UUID) -> some View {
        let workout = store.plan?.workouts.first { $0.id == suggestedID }
        return VStack(alignment: .leading, spacing: 10) {
            Text("MATCH TO PLAN?")
                .font(WSFont.ui(13, weight: .heavy))
                .foregroundStyle(WSColor.accent)
            Text(workout?.blueprint.title.uppercased() ?? "PLANNED RUN")
                .font(WSFont.ui(15, weight: .heavy))
            HStack(spacing: 8) {
                WSPrimaryButton(title: "CONFIRM", height: 44, fontSize: 16) {
                    store.confirmHealthMatch(for: result.workoutID, scheduledWorkoutID: suggestedID)
                }
                WSOutlineButton(title: "KEEP UNMATCHED", height: 44) {
                    store.keepHealthUnmatched(for: result.workoutID)
                }
            }
            if let candidates = store.alternateMatchCandidates(for: result).dropFirst().first {
                WSOutlineButton(title: "CHOOSE ANOTHER") {
                    store.rejectHealthMatch(for: result.workoutID, suggestedWorkoutID: suggestedID)
                }
                .overlay {
                    if candidates.scheduledWorkoutID != suggestedID {
                        EmptyView()
                    }
                }
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, WSSpace.gutter)
    }

    private var targetPace: TimeInterval? {
        guard let workout = store.plan?.workouts.first(where: { $0.blueprint.id == result.workoutID || $0.id == result.workoutID }),
              workout.blueprint.usesPaceTargets
        else { return result.averagePaceSecPerKm }
        switch workout.blueprint.kind {
        case .easy, .longRun, .freeRun: return store.zones?.secondsPerKilometer(for: .easy)
        case .tempo: return store.zones?.secondsPerKilometer(for: .threshold)
        case .intervals: return store.zones?.secondsPerKilometer(for: .interval)
        case .race: return store.zones?.secondsPerKilometer(for: .marathon)
        default: return result.averagePaceSecPerKm
        }
    }

    private func splitRow(_ split: WorkoutSplit) -> some View {
        let target = targetPace ?? split.paceSecPerKm
        let faster = split.paceSecPerKm <= target
        let ratio = min(1, target / max(split.paceSecPerKm, 1))
        return HStack(spacing: 12) {
            Text(String(format: "%02d", split.index))
                .font(WSFont.mono(11, weight: .bold))
                .foregroundStyle(WSColor.text50)
                .frame(width: 26, alignment: .leading)
            Text(WSFormat.paceClock(split.paceSecPerKm, unit: store.unit))
                .font(WSFont.ui(15, weight: .heavy))
                .frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WSColor.surface2)
                    Capsule()
                        .fill(faster ? WSColor.accent : Color.white.opacity(0.28))
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 8)
            Text(WSFormat.signedPaceDelta(split.paceSecPerKm - target))
                .font(WSFont.mono(11))
                .foregroundStyle(faster ? WSColor.accent : WSColor.text50)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
    }

    private func stat(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(WSFont.mono(10))
                .foregroundStyle(WSColor.text40)
            Text(value)
                .font(WSFont.display(32))
                .foregroundStyle(accent ? WSColor.accent : WSColor.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func region(for route: [RoutePoint]) -> MKCoordinateRegion {
        let lats = route.map(\.latitude), lons = route.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.005, (maxLat - minLat) * 1.3), longitudeDelta: max(0.005, (maxLon - minLon) * 1.3))
        )
    }
}
