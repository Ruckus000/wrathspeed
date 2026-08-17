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

    public static func scheduledTimeMinutes(hour: Int, minute: Int) -> Int {
        let total = hour * 60 + minute
        return max(0, min(total, (24 * 60) - 1))
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

public enum WorkoutReminderOperation: Equatable, Sendable {
    case cancel(workoutID: UUID)
    case schedule(workoutID: UUID, fireDate: Date, title: String)
}

public enum WorkoutReminderReconciliation {
    public static func operations(
        before: [ScheduledWorkout],
        after: [ScheduledWorkout],
        calendar: Calendar = .current
    ) -> [WorkoutReminderOperation] {
        let beforeByID = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        let afterIDs = Set(after.map(\.id))
        var output: [WorkoutReminderOperation] = []

        for workout in before where !afterIDs.contains(workout.id) {
            if workout.reminderEnabled {
                output.append(.cancel(workoutID: workout.id))
            }
        }

        for workout in after {
            let previous = beforeByID[workout.id]
            if let operation = reminderOperation(previous: previous, current: workout, calendar: calendar) {
                output.append(operation)
            }
        }
        return output
    }

    private static func reminderOperation(
        previous: ScheduledWorkout?,
        current: ScheduledWorkout,
        calendar: Calendar
    ) -> WorkoutReminderOperation? {
        let wasEnabled = previous?.reminderEnabled == true
        let isEnabled = current.reminderEnabled

        if !isEnabled {
            return wasEnabled ? .cancel(workoutID: current.id) : nil
        }

        guard let minutes = current.scheduledTimeMinutes,
              let fireDate = WorkoutReminderRules.fireDate(
                workoutDay: current.date,
                scheduledTimeMinutes: minutes,
                calendar: calendar
              )
        else { return nil }

        if wasEnabled,
           previous?.scheduledTimeMinutes == minutes,
           calendar.isDate(previous!.date, inSameDayAs: current.date),
           previous?.blueprint.title == current.blueprint.title {
            return nil
        }

        return .schedule(workoutID: current.id, fireDate: fireDate, title: current.blueprint.title)
    }
}
