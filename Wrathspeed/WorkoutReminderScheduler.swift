import Foundation
import UserNotifications
import WrathspeedCore

final class LiveWorkoutReminderScheduler: WorkoutReminderScheduling, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func scheduleReminder(workoutID: UUID, fireDate: Date, title: String) async throws {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        else {
            throw WorkoutReminderSchedulingError.permissionDenied
        }

        let content = UNMutableNotificationContent()
        content.title = "Upcoming run"
        content.body = title
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: WorkoutReminderRules.notificationIdentifier(for: workoutID),
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            throw WorkoutReminderSchedulingError.schedulingFailed
        }
    }

    func cancelReminder(workoutID: UUID) async {
        center.removePendingNotificationRequests(
            withIdentifiers: [WorkoutReminderRules.notificationIdentifier(for: workoutID)]
        )
    }

    func notificationIdentifier(for workoutID: UUID) -> String {
        WorkoutReminderRules.notificationIdentifier(for: workoutID)
    }
}
