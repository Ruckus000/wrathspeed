import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WrathspeedWidgets: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // A Live Activity has a fixed height and cannot reflow, so its subtree uses the
            // widget type profile, where every role is capped rather than uncapped.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title.uppercased())
                            .wsType(.body, weight: .heavy, tracking: 0.5)
                            .foregroundStyle(.white)
                        Text(context.state.stepName)
                            .wsType(.label, weight: .medium)
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    Spacer()
                    Text(timeString(context.state.elapsed))
                        .wsType(.metric, weight: .bold)
                        .foregroundStyle(WSColor.accent)
                }
                HStack(spacing: 14) {
                    Text(distanceString(context.state.distanceMeters, unitRaw: context.state.distanceUnitRaw))
                    Text(paceString(context.state.paceSecPerKm, unitRaw: context.state.distanceUnitRaw))
                    Text(context.state.isPaused ? "PAUSED" : "LIVE")
                        .foregroundStyle(WSColor.accent)
                }
                .wsType(.metricS)
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.top, 10)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                }
            }
            .padding(14)
            .wsTypeProfile(.widget)
            .activityBackgroundTint(WSColor.liveActivity)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.stepName)
                        .wsType(.label, weight: .bold)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timeString(context.state.elapsed))
                        .wsType(.metric, weight: .bold)
                        .foregroundStyle(WSColor.accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(distanceString(context.state.distanceMeters, unitRaw: context.state.distanceUnitRaw))
                        Text(paceString(context.state.paceSecPerKm, unitRaw: context.state.distanceUnitRaw))
                        Text(context.state.isPaused ? "PAUSED" : "LIVE")
                            .foregroundStyle(WSColor.accent)
                    }
                    .wsType(.metric)
                }
            } compactLeading: {
                Text("▲")
                    .wsType(.label, weight: .heavy)
                    .foregroundStyle(WSColor.accent)
            } compactTrailing: {
                Text(timeString(context.state.elapsed))
                    .wsType(.metric, weight: .bold)
                    .foregroundStyle(.white)
            } minimal: {
                Text("▲")
                    .wsType(.label, weight: .heavy)
                    .foregroundStyle(WSColor.accent)
            }
        }
    }

    private func timeString(_ elapsed: TimeInterval) -> String {
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func distanceString(_ meters: Double, unitRaw: String) -> String {
        let miles = unitRaw == "miles"
        let value = miles ? meters / 1609.344 : meters / 1000
        let suffix = miles ? "MI" : "KM"
        return "\(value.formatted(.number.precision(.fractionLength(2)))) \(suffix)"
    }

    private func paceString(_ paceSecPerKm: Double?, unitRaw: String) -> String {
        let miles = unitRaw == "miles"
        guard let paceSecPerKm else { return miles ? "— /MI" : "— /KM" }
        let seconds = miles ? paceSecPerKm * 1609.344 / 1000 : paceSecPerKm
        let total = max(0, Int(seconds.rounded()))
        let suffix = miles ? "MI" : "KM"
        return String(format: "%d:%02d /\(suffix)", total / 60, total % 60)
    }
}
