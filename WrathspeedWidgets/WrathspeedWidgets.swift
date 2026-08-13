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
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title.uppercased())
                            .font(WSFont.ui(13, weight: .heavy))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                        Text(context.state.stepName)
                            .font(WSFont.ui(11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    Spacer()
                    Text(timeString(context.state.elapsed))
                        .font(WSFont.mono(15, weight: .bold))
                        .foregroundStyle(WSColor.accent)
                }
                HStack(spacing: 14) {
                    Text(distanceString(context.state.distanceMeters, unitRaw: context.state.distanceUnitRaw))
                    Text(paceString(context.state.paceSecPerKm, unitRaw: context.state.distanceUnitRaw))
                    Text(context.state.isPaused ? "PAUSED" : "LIVE")
                        .foregroundStyle(WSColor.accent)
                }
                .font(WSFont.mono(10))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.top, 10)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                }
            }
            .padding(14)
            .activityBackgroundTint(WSColor.liveActivity)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.stepName)
                        .font(WSFont.ui(12, weight: .bold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timeString(context.state.elapsed))
                        .font(WSFont.mono(13, weight: .bold))
                        .foregroundStyle(WSColor.accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(distanceString(context.state.distanceMeters, unitRaw: context.state.distanceUnitRaw))
                        Text(paceString(context.state.paceSecPerKm, unitRaw: context.state.distanceUnitRaw))
                        Text(context.state.isPaused ? "PAUSED" : "LIVE")
                            .foregroundStyle(WSColor.accent)
                    }
                    .font(WSFont.mono(11))
                }
            } compactLeading: {
                Text("▲")
                    .font(WSFont.ui(12, weight: .heavy))
                    .foregroundStyle(WSColor.accent)
            } compactTrailing: {
                Text(timeString(context.state.elapsed))
                    .font(WSFont.mono(12, weight: .bold))
                    .foregroundStyle(.white)
            } minimal: {
                Text("▲")
                    .font(WSFont.ui(11, weight: .heavy))
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
