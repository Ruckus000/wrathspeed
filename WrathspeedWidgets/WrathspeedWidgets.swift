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
            HStack {
                VStack(alignment: .leading) {
                    Text(context.state.title)
                        .font(.headline)
                    Text(context.state.stepName)
                        .font(.subheadline)
                }
                Spacer()
                Text(timeString(context.state.elapsed))
                    .monospacedDigit()
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.7))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.stepName)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timeString(context.state.elapsed))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.isPaused ? "Paused" : context.state.title)
                }
            } compactLeading: {
                Image(systemName: "figure.run")
            } compactTrailing: {
                Text(timeString(context.state.elapsed))
            } minimal: {
                Image(systemName: "figure.run")
            }
        }
    }

    private func timeString(_ elapsed: TimeInterval) -> String {
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
