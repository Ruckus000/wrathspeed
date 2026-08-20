import Foundation
import WrathspeedCore

final class MockWorkoutReminderScheduler: WorkoutReminderScheduling, @unchecked Sendable {
    var authorizationGranted = true
    var shouldFailScheduling = false
    private(set) var scheduled: [UUID: Date] = [:]
    private(set) var cancelled: [UUID] = []

    func requestAuthorizationIfNeeded() async -> Bool {
        authorizationGranted
    }

    func scheduleReminder(workoutID: UUID, fireDate: Date, title: String) async throws {
        if !authorizationGranted {
            throw WorkoutReminderSchedulingError.permissionDenied
        }
        if shouldFailScheduling {
            throw WorkoutReminderSchedulingError.schedulingFailed
        }
        scheduled[workoutID] = fireDate
    }

    func cancelReminder(workoutID: UUID) async {
        scheduled.removeValue(forKey: workoutID)
        cancelled.append(workoutID)
    }

    func notificationIdentifier(for workoutID: UUID) -> String {
        WorkoutReminderRules.notificationIdentifier(for: workoutID)
    }
}
