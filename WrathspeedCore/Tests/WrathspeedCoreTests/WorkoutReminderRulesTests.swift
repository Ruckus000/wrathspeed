import XCTest
@testable import WrathspeedCore

final class WorkoutReminderRulesTests: XCTestCase {
    func testStableNotificationIdentifier() {
        let id = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        XCTAssertEqual(
            WorkoutReminderRules.notificationIdentifier(for: id),
            "workout-reminder-A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        )
    }

    func testFireDateUsesWorkoutDayAndMinutes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        let fire = WorkoutReminderRules.fireDate(workoutDay: day, scheduledTimeMinutes: 90, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: fire!), 1)
        XCTAssertEqual(calendar.component(.minute, from: fire!), 30)
    }

    func testScheduledTimeMinutesFromClockComponents() {
        XCTAssertEqual(WorkoutReminderRules.scheduledTimeMinutes(hour: 7, minute: 0), 420)
        XCTAssertEqual(WorkoutReminderRules.scheduledTimeMinutes(hour: 18, minute: 30), 1_110)
        XCTAssertEqual(WorkoutReminderRules.scheduledTimeMinutes(hour: 0, minute: 0), 0)
        XCTAssertEqual(WorkoutReminderRules.scheduledTimeMinutes(hour: 23, minute: 59), 1_439)
    }

    func testScheduledTimeMinutesIgnoresDatePortion() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let originalDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 7, minute: 0))!
        let laterDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 17, hour: 7, minute: 0))!
        let originalComponents = calendar.dateComponents([.hour, .minute], from: originalDay)
        let laterComponents = calendar.dateComponents([.hour, .minute], from: laterDay)
        XCTAssertEqual(
            WorkoutReminderRules.scheduledTimeMinutes(hour: laterComponents.hour!, minute: laterComponents.minute!),
            WorkoutReminderRules.scheduledTimeMinutes(hour: originalComponents.hour!, minute: originalComponents.minute!)
        )
    }

    func testLegacyWorkoutPayloadDecodesWithoutReminderFields() throws {
        struct LegacyPayload: Codable {
            var id: UUID
            var blueprint: WorkoutBlueprint
            var status: WorkoutStatus
        }
        let legacy = LegacyPayload(
            id: UUID(),
            blueprint: WorkoutBlueprint(
                date: Date(),
                kind: .easy,
                title: "Easy",
                steps: [],
                plannedDistanceMeters: 5_000,
                usesPaceTargets: true
            ),
            status: .scheduled
        )
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(ScheduledWorkout.self, from: data)
        XCTAssertFalse(decoded.reminderEnabled)
        XCTAssertNil(decoded.scheduledTimeMinutes)
    }
}
