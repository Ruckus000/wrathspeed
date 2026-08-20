#if os(iOS)
import ActivityKit

final class WorkoutLiveActivityPresenter: @unchecked Sendable {
    private var activity: Activity<WorkoutActivityAttributes>?

    func start(attributes: WorkoutActivityAttributes, state: WorkoutActivityAttributes.ContentState) {
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    func update(state: WorkoutActivityAttributes.ContentState) {
        Task { await activity?.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() async {
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
    }
}
#endif
