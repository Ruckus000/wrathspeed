import SwiftUI
import WrathspeedCore

struct MobilityDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let result: MobilitySessionResult

    private var routine: MobilityRoutineTemplate? {
        try? MobilityCatalogLoader.routine(id: result.routineID)
    }

    private var routineTitle: String {
        routine?.title.uppercased() ?? "MOBILITY ROUTINE"
    }

    private var totalMovements: Int {
        routine?.movements.count ?? result.completedMovementIDs.count
    }

    private var duration: TimeInterval {
        result.endedAt.timeIntervalSince(result.startedAt)
    }

    var body: some View {
        WSScreen {
            detailHeader
            summaryStats
            if let routine {
                movementsSection(routine: routine)
            }
            sessionSection
            Spacer(minLength: 30)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(WSColor.bg.ignoresSafeArea())
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            WSRow {
                WSBackButton(title: "← HISTORY", accessibilityLabel: "Back to history") { dismiss() }
            } trailing: {
                Text(WSFormat.weekdayDate(result.startedAt))
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text40)
            }
            Text(routineTitle)
                .wsType(.displayM)
                .foregroundStyle(WSColor.text)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
                .padding(.top, 18)
            if let routine {
                Text(routine.category.displayName.uppercased())
                    .wsType(.metric)
                    .foregroundStyle(WSColor.text50)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.top, 8)
    }

    private var summaryStats: some View {
        HStack {
            stat("MOVEMENTS", "\(result.completedMovementIDs.count)/\(max(totalMovements, result.completedMovementIDs.count))")
            stat("TIME", WSFormat.duration(duration))
            stat(
                "STATUS",
                result.lifecycle == .completed ? "DONE" : result.lifecycle.rawValue.uppercased()
            )
        }
        .padding(.horizontal, WSSpace.gutter)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(WSColor.hairlineStrong).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairlineStrong).frame(height: 1) }
        .padding(.top, 22)
        .padding(.horizontal, WSSpace.gutter)
    }

    private func movementsSection(routine: MobilityRoutineTemplate) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MOVEMENTS")
                .wsType(.metricS, tracking: 1.5)
                .foregroundStyle(WSColor.text40)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 22)
            VStack(spacing: 0) {
                ForEach(routine.movements) { movement in
                    movementRow(movement)
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
                    label: "COMPLETION",
                    value: completionLabel,
                    showDivider: false
                )
            }
            .padding(.horizontal, WSSpace.gutter)
        }
    }

    private var completionLabel: String {
        let completed = result.completedMovementIDs.count
        let total = max(totalMovements, completed)
        guard total > 0 else { return WSFormat.missingValue }
        if completed >= total { return "COMPLETE" }
        return "\(completed) OF \(total) MOVEMENTS"
    }

    private func movementRow(_ movement: MobilityMovement) -> some View {
        let completed = result.completedMovementIDs.contains(movement.id)
        let status = completed ? "COMPLETED" : "NOT DONE"
        let detail = movementDetail(movement)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(completed ? WSColor.accent : WSColor.text50)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(movement.name.uppercased())
                    .wsType(.body, weight: .heavy)
                    .foregroundStyle(WSColor.text)
                if !detail.isEmpty {
                    Text(detail)
                        .wsType(.metric)
                        .foregroundStyle(WSColor.text50)
                }
                Text(status)
                    .wsType(.metricS, weight: .bold)
                    .foregroundStyle(completed ? WSColor.accent : WSColor.text50)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(WSColor.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(movement.name), \(status.lowercased())\(detail.isEmpty ? "" : ", \(detail)")")
    }

    private func movementDetail(_ movement: MobilityMovement) -> String {
        var parts: [String] = []
        if let duration = movement.durationSeconds {
            parts.append(WSFormat.duration(duration))
        }
        if let reps = movement.reps {
            parts.append("\(reps) REPS")
        }
        if let side = movement.side, !side.isEmpty {
            parts.append(side.uppercased())
        }
        return parts.joined(separator: " · ")
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
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}
