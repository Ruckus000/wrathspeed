import SwiftUI
import WrathspeedCore

struct StrengthDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let result: StrengthSessionResult

    @State private var catalog: StrengthCatalog?

    private var sessionTitle: String {
        store.strengthSessions.first { $0.id == result.sessionID }?.title.uppercased() ?? "STRENGTH SESSION"
    }

    private var completedSets: [StrengthSetLog] {
        result.setLogs.filter(\.completed)
    }

    private var skippedSets: [StrengthSetLog] {
        result.setLogs.filter(\.skipped)
    }

    var body: some View {
        WSScreen {
            detailHeader
            summaryStats
            if !completedSets.isEmpty || !skippedSets.isEmpty {
                setsSection
            }
            sessionSection
            Spacer(minLength: 30)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(WSColor.bg.ignoresSafeArea())
        .task {
            catalog = try? StrengthCatalogLoader.load()
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            WSRow {
                Button("← HISTORY") { dismiss() }
                    .wsType(.body, weight: .heavy, tracking: 1)
                    .foregroundStyle(WSColor.text50)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityLabel("Back to history")
            } trailing: {
                Text(WSFormat.weekdayDate(result.startedAt))
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text40)
            }
            Text(sessionTitle)
                .wsType(.displayM)
                .foregroundStyle(WSColor.text)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
                .padding(.top, 18)
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 8)
    }

    private var summaryStats: some View {
        HStack {
            stat("SETS DONE", "\(completedSets.count)")
            stat("SKIPPED", "\(skippedSets.count)")
            stat("TIME", WSFormat.duration(result.endedAt.timeIntervalSince(result.startedAt)))
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(WSColor.hairlineStrong).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairlineStrong).frame(height: 1) }
        .padding(.top, 22)
        .padding(.horizontal, WSSpace.gutter)
    }

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SETS")
                .wsType(.metricS, tracking: 1.5)
                .foregroundStyle(WSColor.text40)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 22)
            VStack(spacing: 0) {
                ForEach(result.setLogs) { log in
                    setRow(log)
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
                WSHairlineRow(
                    label: "DIFFICULTY",
                    value: result.difficultyRPE.map { "RPE \($0)" } ?? WSFormat.missingValue
                )
                WSHairlineRow(
                    label: "HEALTH SYNC",
                    value: WSFormat.healthSyncLabel(
                        state: result.healthSync.state,
                        failureMessage: result.healthSync.failureMessage
                    ),
                    valueColor: result.healthSync.state == .failed ? WSColor.accent : WSColor.text,
                    showDivider: false
                )
            }
            .padding(.horizontal, WSSpace.gutter)
        }
    }

    private func setRow(_ log: StrengthSetLog) -> some View {
        let status = log.skipped ? "SKIPPED" : (log.completed ? "COMPLETED" : "INCOMPLETE")
        let detail = setDetail(log)
        return VStack(alignment: .leading, spacing: 4) {
            WSRow(alignment: .firstTextBaseline) {
                Text(exerciseName(for: log).uppercased())
                    .wsType(.body, weight: .heavy)
                    .foregroundStyle(WSColor.text)
            } trailing: {
                Text(status)
                    .wsType(.metricS, weight: .bold)
                    .foregroundStyle(log.skipped ? WSColor.text50 : WSColor.accent)
            }
            if !detail.isEmpty {
                Text(detail)
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text50)
            }
            if let note = log.note, !note.isEmpty {
                Text("NOTE: \(note.uppercased())")
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text45)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(exerciseName(for: log)), \(status.lowercased())\(detail.isEmpty ? "" : ", \(detail)")")
    }

    private func setDetail(_ log: StrengthSetLog) -> String {
        var parts: [String] = []
        if let reps = log.reps {
            parts.append("\(reps) REPS")
        }
        let load = WSFormat.strengthLoad(value: log.loadValue, unit: log.loadUnit)
        if load != WSFormat.missingValue {
            parts.append(load)
        }
        if let substitutionID = log.substitutionExerciseID {
            let name = catalog?.exercises.first { $0.id == substitutionID }?.name ?? substitutionID
            parts.append("SUB: \(name.uppercased())")
        }
        return parts.joined(separator: " · ")
    }

    private func exerciseName(for log: StrengthSetLog) -> String {
        if let substitutionID = log.substitutionExerciseID,
           let exercise = catalog?.exercises.first(where: { $0.id == substitutionID }) {
            return exercise.name
        }
        return catalog?.exercises.first { $0.id == log.exerciseID }?.name ?? log.exerciseID
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .wsType(.metricS)
                .foregroundStyle(WSColor.text40)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(value)
                .wsType(.displayXS)
                .foregroundStyle(WSColor.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}
