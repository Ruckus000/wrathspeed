import Foundation

struct WatchStartResolver {
    private var launchRequested = false
    private var pendingRequest: WatchStartRequest?
    private var startedWorkoutIDs: Set<UUID> = []

    mutating func receiveLaunchRequest() -> WatchStartRequest? {
        launchRequested = true
        return resolveIfReady()
    }

    mutating func receive(_ request: WatchStartRequest) -> WatchStartRequest? {
        pendingRequest = request
        return resolveIfReady()
    }

    private mutating func resolveIfReady() -> WatchStartRequest? {
        guard launchRequested, let pendingRequest else { return nil }
        launchRequested = false
        self.pendingRequest = nil
        guard startedWorkoutIDs.insert(pendingRequest.blueprint.id).inserted else { return nil }
        return pendingRequest
    }
}
