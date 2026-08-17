import Foundation

public enum WorkoutReminderSchedulingError: LocalizedError, Equatable, Sendable {
    case permissionDenied
    case schedulingFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Notification permission was denied. Your workout change is saved; enable reminders in Settings when you're ready."
        case .schedulingFailed:
            "Couldn't schedule the reminder, but your workout change is saved. Try again from the workout details."
        }
    }
}

public protocol WorkoutReminderScheduling: Sendable {
    func requestAuthorizationIfNeeded() async -> Bool
    func scheduleReminder(workoutID: UUID, fireDate: Date, title: String) async throws
    func cancelReminder(workoutID: UUID) async
    func notificationIdentifier(for workoutID: UUID) -> String
}

public enum WorkoutReminderRules {
    public static func notificationIdentifier(for workoutID: UUID) -> String {
        "workout-reminder-\(workoutID.uuidString)"
    }

    public static func fireDate(
        workoutDay: Date,
        scheduledTimeMinutes: Int,
        calendar: Calendar
    ) -> Date? {
        let day = calendar.startOfDay(for: workoutDay)
        let clamped = max(0, min(scheduledTimeMinutes, (24 * 60) - 1))
        return calendar.date(byAdding: .minute, value: clamped, to: day)
    }
}

public final class MockWorkoutReminderScheduler: WorkoutReminderScheduling, @unchecked Sendable {
    public var authorizationGranted = true
    public var shouldFailScheduling = false
    public private(set) var scheduled: [UUID: Date] = [:]

    public init() {}

    public func requestAuthorizationIfNeeded() async -> Bool {
        authorizationGranted
    }

    public func scheduleReminder(workoutID: UUID, fireDate: Date, title: String) async throws {
        if !authorizationGranted {
            throw WorkoutReminderSchedulingError.permissionDenied
        }
        if shouldFailScheduling {
            throw WorkoutReminderSchedulingError.schedulingFailed
        }
        scheduled[workoutID] = fireDate
    }

    public func cancelReminder(workoutID: UUID) async {
        scheduled.removeValue(forKey: workoutID)
    }

    public func notificationIdentifier(for workoutID: UUID) -> String {
        WorkoutReminderRules.notificationIdentifier(for: workoutID)
    }
}
