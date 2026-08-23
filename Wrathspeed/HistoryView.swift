import MapKit
import SwiftUI
import WrathspeedCore

struct HistoryView: View {
    @Environment(AppStore.self) private var store
    @State private var filter: HistoryFilter = .runs

    enum HistoryFilter: String, CaseIterable {
        case runs, strength, mobility
        var title: String { rawValue.uppercased() }
    }

    var body: some View {
        NavigationStack {
            WSScreen {
                Text("HISTORY")
                    .wsType(.displayL)
                    .foregroundStyle(WSColor.text)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 10)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 8) {
                    ForEach(HistoryFilter.allCases, id: \.self) { item in
                        WSChip(title: item.title, selected: filter == item) { filter = item }
                            .accessibilityLabel("\(item.title) filter")
                            .accessibilityAddTraits(filter == item ? .isSelected : [])
                    }
                }
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 12)
                healthImportStatusCard
                if let recap = lastWeekRecap {
                    weeklyRecapCard(eyebrow: recap.eyebrow, headline: recap.headline)
                }
                fourWeekSummarySection
                historyList
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var healthImportStatusCard: some View {
        let status = store.healthImportStatus
        switch status.presentation {
        case .idle:
            healthImportManualAction
        case .importing:
            healthImportBanner(
                title: "IMPORTING FROM APPLE HEALTH",
                message: nil,
                showsProgress: true
            )
        case .succeeded:
            VStack(alignment: .leading, spacing: 10) {
                if let lastSuccess = status.lastSuccessfulImportAt {
                    healthImportBanner(
                        title: "LAST IMPORT",
                        message: WSFormat.importTimestamp(lastSuccess),
                        showsProgress: false
                    )
                }
                healthImportManualAction
            }
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 10) {
                healthImportBanner(
                    title: "APPLE HEALTH IMPORT FAILED",
                    message: failure.message.uppercased(),
                    showsProgress: false
                )
                HStack(spacing: 8) {
                    if failure.canRetry {
                        WSPrimaryButton(title: "RETRY IMPORT", height: 44, role: .control) {
                            Task { await store.importHealthWorkouts() }
                        }
                        .accessibilityLabel("Retry Apple Health import")
                    }
                    if failure.canOpenSettings {
                        WSOutlineButton(title: "OPEN SETTINGS", height: 44) {
                            store.openHealthSettings()
                        }
                        .accessibilityLabel("Open Settings for Apple Health access")
                    }
                }
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 18)
        }
    }

    private var healthImportManualAction: some View {
        WSOutlineButton(title: "IMPORT FROM HEALTH", height: 44) {
            Task { await store.importHealthWorkouts() }
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 18)
        .accessibilityLabel("Import from Apple Health")
    }

    private func healthImportBanner(title: String, message: String?, showsProgress: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if showsProgress {
                    ProgressView()
                        .tint(.white)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .wsType(.label, weight: .heavy, tracking: 1.5)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            if let message {
                Text(message)
                    .wsType(.metric)
                    .foregroundStyle(.white)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WSColor.surface1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(WSColor.border, lineWidth: 1)
        )
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, message].compactMap { $0 }.joined(separator: ", "))
    }

    private func weeklyRecapCard(eyebrow: String, headline: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .wsType(.label, weight: .heavy, tracking: 2)
                .foregroundStyle(Color.white.opacity(0.75))
            Text(headline)
                .wsType(.displayXS)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.75)
                .lineLimit(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WSColor.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(eyebrow), \(headline)")
    }

    @ViewBuilder
    private var fourWeekSummarySection: some View {
        let summaries = store.rollingFourWeekSummaries()
        if summaries.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("FOUR-WEEK LOAD")
                    .wsType(.metricS, tracking: 1.5)
                    .foregroundStyle(WSColor.text40)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 18)
                VStack(spacing: 0) {
                    ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                        HStack {
                            Text(WSFormat.weekdayDate(summary.weekStart))
                                .wsType(.metric)
                                .foregroundStyle(WSColor.text50)
                                .frame(width: 88, alignment: .leading)
                            Text(WSFormat.weeklyLoadLine(summary, unit: store.unit))
                                .wsType(.metric)
                                .foregroundStyle(WSColor.text)
                                .multilineTextAlignment(.trailing)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Week of \(WSFormat.weekdayDate(summary.weekStart)), \(WSFormat.weeklyLoadLine(summary, unit: store.unit))")
                    }
                }
                .padding(.horizontal, WSSpace.gutter)
            }
        }
    }

    @ViewBuilder
    private var historyList: some View {
        VStack(spacing: 0) {
            if filter == .runs {
                if store.results.isEmpty {
                    emptyState("NO RUNS YET. COMPLETE A WORKOUT OR IMPORT FROM APPLE HEALTH.")
                } else {
                    ForEach(historyRunRows) { row in
                        runResultRow(row.result)
                    }
                }
            } else if filter == .strength {
                if store.strengthResults.isEmpty {
                    emptyState("STRENGTH HISTORY BUILDS FROM COMPLETED SESSIONS.")
                } else {
                    ForEach(store.strengthResults) { result in
                        strengthResultRow(result)
                    }
                }
            } else if store.mobilityResults.isEmpty {
                emptyState("MOBILITY HISTORY BUILDS FROM COMPLETED ROUTINES.")
            } else {
                ForEach(store.mobilityResults) { result in
                    mobilityResultRow(result)
                }
            }
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 18)
        .padding(.bottom, 24)
    }

    private var historyRunRows: [HistoryRunRow] {
        store.results.map { result in
            HistoryRunRow(
                id: WorkoutResultMerge.historyRowIdentity(for: result, in: store.results),
                result: result
            )
        }
    }

    private func runResultRow(_ result: WorkoutResult) -> some View {
        NavigationLink {
            RunDetailView(result: result)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                WSRow(alignment: .firstTextBaseline) {
                    Text(title(for: result))
                        .wsType(.body, weight: .heavy)
                        .foregroundStyle(WSColor.text)
                } trailing: {
                    Text("\(WSFormat.weekdayDate(result.startedAt)) ›")
                        .wsType(.metricS)
                        .foregroundStyle(WSColor.text40)
                }
                HStack(spacing: 16) {
                    Text(WSFormat.distance(result.distanceMeters, unit: store.unit))
                    Text(result.location.historyLabel)
                    if let pace = result.averagePaceSecPerKm {
                        Text(WSFormat.pace(pace, unit: store.unit))
                    }
                }
                .wsType(.metric)
                .foregroundStyle(Color.white.opacity(0.75))
                .padding(.top, 6)
                if result.isUnavailableInHealth {
                    Text("UNAVAILABLE IN HEALTH")
                        .wsType(.metricS, weight: .bold)
                        .foregroundStyle(WSColor.text50)
                        .padding(.top, 5)
                }
                if let comparison = store.comparison(for: result) {
                    Text(comparison)
                        .wsType(.metric, weight: .medium)
                        .foregroundStyle(WSColor.accent)
                        .padding(.top, 5)
                }
            }
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(runRowAccessibilityLabel(for: result))
    }

    private func runRowAccessibilityLabel(for result: WorkoutResult) -> String {
        var parts = [
            title(for: result),
            WSFormat.weekdayDate(result.startedAt),
            WSFormat.distance(result.distanceMeters, unit: store.unit),
            result.location.title
        ]
        if let pace = result.averagePaceSecPerKm {
            parts.append(WSFormat.pace(pace, unit: store.unit))
        }
        if result.isUnavailableInHealth {
            parts.append("Unavailable in Health")
        }
        if let comparison = store.comparison(for: result) {
            parts.append(comparison)
        }
        return parts.joined(separator: ", ")
    }

    private func title(for result: WorkoutResult) -> String {
        store.plan?.workouts.first { $0.blueprint.id == result.workoutID || $0.id == result.workoutID }?
            .blueprint.title.uppercased() ?? (result.source == .instant ? "INSTANT RUN" : "RUN")
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .wsType(.metric)
            .foregroundStyle(WSColor.text45)
            .padding(.vertical, 24)
            .accessibilityLabel(message)
    }

    private func strengthResultRow(_ result: StrengthSessionResult) -> some View {
        NavigationLink {
            StrengthDetailView(result: result)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(strengthSessionTitle(for: result))
                    .wsType(.body, weight: .heavy)
                Text("\(result.setLogs.filter(\.completed).count) sets · \(WSFormat.weekdayDate(result.startedAt))")
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text50)
            }
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(strengthSessionTitle(for: result)), \(result.setLogs.filter(\.completed).count) sets, \(WSFormat.weekdayDate(result.startedAt))")
    }

    private func strengthSessionTitle(for result: StrengthSessionResult) -> String {
        store.strengthSessions.first { $0.id == result.sessionID }?.title.uppercased() ?? "STRENGTH SESSION"
    }

    private func mobilityResultRow(_ result: MobilitySessionResult) -> some View {
        NavigationLink {
            MobilityDetailView(result: result)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(mobilityRoutineTitle(for: result))
                    .wsType(.body, weight: .heavy)
                Text("\(result.completedMovementIDs.count) movements · \(WSFormat.weekdayDate(result.startedAt))")
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text50)
            }
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mobilityRoutineTitle(for: result)), \(result.completedMovementIDs.count) movements, \(WSFormat.weekdayDate(result.startedAt))")
    }

    private func mobilityRoutineTitle(for result: MobilitySessionResult) -> String {
        (try? MobilityCatalogLoader.routine(id: result.routineID))?.title.uppercased() ?? "MOBILITY ROUTINE"
    }

    private var lastWeekRecap: (eyebrow: String, headline: String)? {
        guard let summary = store.rollingFourWeekSummaries().dropLast().last ?? store.currentWeekSummary() else {
            return nil
        }
        let loadLine = WSFormat.weeklyLoadLine(summary, unit: store.unit)
        return (
            "WEEKLY LOAD",
            "\(loadLine) PLANNED"
        )
    }
}

private struct HistoryRunRow: Identifiable {
    let id: String
    let result: WorkoutResult
}

struct RunDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let result: WorkoutResult

    private var currentResult: WorkoutResult {
        WorkoutResultMerge.canonical(of: result, in: store.results)
    }

    var body: some View {
        WSScreen {
            WSRow {
                Button("← HISTORY") { dismiss() }
                    .wsType(.body, weight: .heavy, tracking: 1)
                    .foregroundStyle(WSColor.text50)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityLabel("Back to history")
            } trailing: {
                Text(WSFormat.weekdayDate(currentResult.startedAt))
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text40)
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)
            Text(title)
                .wsType(.displayL)
                .foregroundStyle(WSColor.text)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 18)
            HStack {
                stat("DISTANCE", WSFormat.distanceValue(currentResult.distanceMeters, unit: store.unit))
                stat("TIME", WSFormat.duration(currentResult.duration))
                stat(
                    "AVG PACE",
                    currentResult.averagePaceSecPerKm.map { WSFormat.paceClock($0, unit: store.unit) } ?? WSFormat.missingValue,
                    accent: currentResult.averagePaceSecPerKm != nil
                )
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(WSColor.hairlineStrong).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairlineStrong).frame(height: 1) }
            .padding(.top, 22)
            .padding(.horizontal, WSSpace.gutter)
            if let comparison = store.comparison(for: currentResult) {
                Text(comparison)
                    .wsType(.metric)
                    .foregroundStyle(WSColor.accent)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 14)
            }
            routeSection
            splitsSection
            sessionSection
            matchActions
            Spacer(minLength: 30)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(WSColor.bg.ignoresSafeArea())
    }

    @ViewBuilder
    private var routeSection: some View {
        if let route = currentResult.route, route.count > 1 {
            Map(initialPosition: .region(region(for: route))) {
                MapPolyline(coordinates: route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                    .stroke(WSColor.accent, lineWidth: 4)
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous))
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 16)
            .accessibilityHidden(true)
        } else if currentResult.location == .outdoor {
            Text("ROUTE UNAVAILABLE")
                .wsType(.metric)
                .foregroundStyle(WSColor.text50)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 16)
                .accessibilityLabel("Route unavailable")
        }
    }

    @ViewBuilder
    private var splitsSection: some View {
        let splits = store.resolvedSplits(for: currentResult)
        if !splits.isEmpty {
            Text(targetPace == nil ? "SPLITS" : "SPLITS · VS TARGET")
                .wsType(.metricS, tracking: 1.5)
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
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SESSION")
                .wsType(.metricS, tracking: 1.5)
                .foregroundStyle(WSColor.text40)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 22)
            VStack(spacing: 0) {
                WSHairlineRow(label: "SOURCE", value: currentResult.source.displayName.uppercased())
                WSHairlineRow(label: "MATCH", value: matchLabel)
                WSHairlineRow(label: "LOCATION", value: currentResult.location.historyLabel)
                WSHairlineRow(label: "AVG HR", value: WSFormat.heartRate(bpm: currentResult.heartRateAverage))
                WSHairlineRow(label: "ACTIVE ENERGY", value: WSFormat.activeEnergy(kilocalories: currentResult.energyKilocalories))
                WSHairlineRow(label: "CADENCE", value: WSFormat.cadence(stepsPerMinute: currentResult.cadenceAverage))
                WSHairlineRow(
                    label: "HEALTH SYNC",
                    value: healthSyncLabel,
                    valueColor: WSColor.text,
                    showDivider: !currentResult.isUnavailableInHealth
                )
                if currentResult.isUnavailableInHealth {
                    WSHairlineRow(
                        label: "APPLE HEALTH",
                        value: "UNAVAILABLE IN HEALTH",
                        valueColor: WSColor.text50,
                        showDivider: false
                    )
                }
            }
            .padding(.horizontal, WSSpace.gutter)
            if currentResult.isUnavailableInHealth {
                Text("LOCAL RUN RECORD KEPT. APPLE HEALTH EVIDENCE WAS REMOVED OR IS NO LONGER AVAILABLE.")
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text45)
                    .padding(.horizontal, WSSpace.gutter)
                    .padding(.top, 10)
                    .accessibilityLabel("Local run record kept. Apple Health evidence was removed or is no longer available.")
            }
        }
    }

    private var healthSyncLabel: String {
        WSFormat.healthSyncLabel(
            state: currentResult.healthSync.state,
            failureMessage: currentResult.healthSync.failureMessage
        )
    }

    @ViewBuilder
    private var matchActions: some View {
        if currentResult.matchInfo.state == .suggested, let suggestedID = currentResult.matchInfo.suggestedWorkoutID {
            matchSuggestionCard(suggestedID: suggestedID)
        } else if currentResult.matchInfo.state == .matched {
            WSOutlineButton(title: "UNMATCH FROM PLAN") {
                store.unmatchHealthResult(currentResult)
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 12)
            .accessibilityLabel("Unmatch from plan")
        }
    }

    private var title: String {
        store.plan?.workouts.first { $0.blueprint.id == currentResult.workoutID || $0.id == currentResult.workoutID }?
            .blueprint.title.uppercased() ?? (currentResult.source == .instant ? "INSTANT RUN" : "RUN")
    }

    private var matchLabel: String {
        switch currentResult.matchInfo.state {
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
                .wsType(.body, weight: .heavy)
                .foregroundStyle(WSColor.accent)
            Text(workout?.blueprint.title.uppercased() ?? "PLANNED RUN")
                .wsType(.body, weight: .heavy)
            HStack(spacing: 8) {
                WSPrimaryButton(title: "CONFIRM", height: 44, role: .control) {
                    store.confirmHealthMatch(currentResult, scheduledWorkoutID: suggestedID)
                }
                .accessibilityLabel("Confirm match to plan")
                WSOutlineButton(title: "KEEP UNMATCHED", height: 44) {
                    store.keepHealthUnmatched(currentResult)
                }
                .accessibilityLabel("Keep unmatched")
            }
            if let candidates = store.alternateMatchCandidates(for: currentResult).dropFirst().first {
                WSOutlineButton(title: "CHOOSE ANOTHER") {
                    store.rejectHealthMatch(currentResult, suggestedWorkoutID: suggestedID)
                }
                .accessibilityLabel("Choose another planned run")
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
        guard let workout = store.plan?.workouts.first(where: { $0.blueprint.id == currentResult.workoutID || $0.id == currentResult.workoutID }) else {
            return nil
        }
        return WorkoutPaceTarget.targetPaceSecPerKm(blueprint: workout.blueprint, zones: store.zones)
    }

    private func splitRow(_ split: WorkoutSplit) -> some View {
        let paceLabel = WSFormat.paceClock(split.paceSecPerKm, unit: store.unit)
        let comparison = targetPace.map { target -> (faster: Bool, delta: String, ratio: CGFloat) in
            let faster = split.paceSecPerKm <= target
            let delta = WSFormat.signedPaceDelta(split.paceSecPerKm - target)
            let ratio = CGFloat(min(1, target / max(split.paceSecPerKm, 1)))
            return (faster, delta, ratio)
        }
        return HStack(spacing: 12) {
            Text(String(format: "%02d", split.index))
                .wsType(.metric, weight: .bold)
                .foregroundStyle(WSColor.text50)
                .frame(width: 26, alignment: .leading)
            Text(paceLabel)
                .wsType(.body, weight: .heavy)
                .frame(width: 64, alignment: .leading)
            if let comparison {
                if reduceMotion {
                    Text(comparison.faster ? "FASTER" : "SLOWER")
                        .wsType(.metricS, weight: .bold)
                        .foregroundStyle(comparison.faster ? WSColor.accent : WSColor.text50)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(WSColor.surface2)
                            Capsule()
                                .fill(comparison.faster ? WSColor.accent : Color.white.opacity(0.28))
                                .frame(width: geo.size.width * comparison.ratio)
                        }
                    }
                    .frame(height: 8)
                }
                Text(comparison.delta)
                    .wsType(.metric)
                    .foregroundStyle(comparison.faster ? WSColor.accent : WSColor.text50)
                    .frame(width: 48, alignment: .trailing)
            } else {
                Spacer()
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            comparison.map {
                "Split \(split.index), pace \(paceLabel), \($0.faster ? "faster" : "slower") than target, delta \($0.delta)"
            } ?? "Split \(split.index), pace \(paceLabel)"
        )
    }

    private func stat(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .wsType(.metricS)
                .foregroundStyle(WSColor.text40)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(value)
                .wsType(.displayS)
                .foregroundStyle(accent ? WSColor.accent : WSColor.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
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
