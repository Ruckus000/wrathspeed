import XCTest
@testable import WrathspeedCore

final class WorkoutReminderReconciliationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func workout(
        id: UUID = UUID(),
        day: Date,
        title: String = "Easy",
        reminderEnabled: Bool = false,
        minutes: Int? = nil
    ) -> ScheduledWorkout {
        var workout = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: day,
            kind: .easy,
            title: title,
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        workout.id = id
        workout.reminderEnabled = reminderEnabled
        workout.scheduledTimeMinutes = minutes
        return workout
    }

    func testUnchangedReminderProducesNoOperation() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        let workout = workout(id: UUID(), day: day, reminderEnabled: true, minutes: 420)
        let ops = WorkoutReminderReconciliation.operations(before: [workout], after: [workout], calendar: calendar)
        XCTAssertTrue(ops.isEmpty)
    }

    func testDisablingReminderCancelsOnce() {
        let id = UUID()
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        let before = workout(id: id, day: day, reminderEnabled: true, minutes: 420)
        var after = before
        after.reminderEnabled = false
        let ops = WorkoutReminderReconciliation.operations(before: [before], after: [after], calendar: calendar)
        XCTAssertEqual(ops, [.cancel(workoutID: id)])
    }

    func testRemovedWorkoutCancelsReminder() {
        let id = UUID()
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        let before = workout(id: id, day: day, reminderEnabled: true, minutes: 420)
        let ops = WorkoutReminderReconciliation.operations(before: [before], after: [], calendar: calendar)
        XCTAssertEqual(ops, [.cancel(workoutID: id)])
    }

    func testMoveWithEnabledReminderSchedulesReplacement() {
        let id = UUID()
        let beforeDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        let afterDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6))!
        let before = workout(id: id, day: beforeDay, reminderEnabled: true, minutes: 420)
        var after = before
        after.blueprint.date = afterDay
        let ops = WorkoutReminderReconciliation.operations(before: [before], after: [after], calendar: calendar)
        XCTAssertEqual(ops.count, 1)
        guard case .schedule(let workoutID, let fireDate, _) = ops[0] else {
            return XCTFail("Expected schedule operation")
        }
        XCTAssertEqual(workoutID, id)
        XCTAssertEqual(calendar.component(.hour, from: fireDate), 7)
    }
}
