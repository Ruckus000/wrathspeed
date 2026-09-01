import Foundation
import XCTest
@testable import WrathspeedCore

/// `DateInterval.contains` is closed at both ends, so the next week's first workout -- scheduled
/// at local midnight, exactly the boundary -- landed in both weeks. On Today that turned a
/// 33.0 mi week into "38 MI". These pin the half-open behaviour that replaced it.
final class WeekWindowTests: XCTestCase {
    /// Fixed on all three axes the assertions below depend on. `Calendar(identifier:)` carries
    /// a fixed locale rather than the host's, so `firstWeekday` is 1 either way -- but every
    /// date in these tests is written assuming Sunday-start weeks, and that assumption should
    /// be visible rather than inherited from a default.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    func testExcludesTheBoundaryThatDateIntervalIncludes() throws {
        let calendar = self.calendar
        let midweek = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let window = try XCTUnwrap(WeekWindow(containing: midweek, calendar: calendar))

        XCTAssertTrue(window.contains(window.start), "the first instant belongs to this week")
        XCTAssertFalse(window.contains(window.end), "the last instant belongs to the next week")

        // The exact comparison the old spelling got wrong.
        let interval = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: midweek))
        XCTAssertTrue(interval.contains(window.end), "DateInterval is closed -- this is the trap")
    }

    func testEveryDayOfAPlanWeekLandsInExactlyOneWindow() throws {
        let calendar = self.calendar
        // Every workout a generated plan carries sits at local midnight, which is precisely
        // where the two spellings disagree.
        let midnights: [Date] = try (0..<21).map { offset in
            let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 30)))
            return try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: day))
        }
        let windows: [WeekWindow] = try stride(from: 0, to: 21, by: 7).map { offset in
            let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 30)))
            let inWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: day))
            return try XCTUnwrap(WeekWindow(containing: inWeek, calendar: calendar))
        }

        for midnight in midnights {
            let hits = windows.filter { $0.contains(midnight) }.count
            XCTAssertEqual(hits, 1, "\(midnight) landed in \(hits) weeks, not exactly one")
        }
    }

    func testCalendarHelperMatchesTheDirectInitialiser() throws {
        let calendar = self.calendar
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let viaHelper = try XCTUnwrap(calendar.weekWindow(for: date))
        let direct = try XCTUnwrap(WeekWindow(containing: date, calendar: calendar))
        XCTAssertEqual(viaHelper.start, direct.start)
        XCTAssertEqual(viaHelper.end, direct.end)
    }

    /// The concrete regression: a Sunday-to-Saturday plan week plus the following Sunday's
    /// tempo run. The closed interval summed all five; the week is only the first four.
    func testWeekTotalExcludesTheFollowingWeeksFirstWorkout() throws {
        let calendar = self.calendar
        func midnight(_ day: Int, month: Int = 8) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
        }
        let dated: [(Date, Double)] = [
            (try midnight(30), 7_500),   // Sun, this week
            (try midnight(1, month: 9), 14_000),
            (try midnight(3, month: 9), 14_000),
            (try midnight(5, month: 9), 17_700),
            (try midnight(6, month: 9), 7_500)  // Sun, NEXT week -- the double-counted one
        ]
        let window = try XCTUnwrap(WeekWindow(containing: try midnight(1, month: 9), calendar: calendar))

        let total = dated.filter { window.contains($0.0) }.reduce(0) { $0 + $1.1 }
        XCTAssertEqual(total, 53_200, "the following Sunday must not be counted in this week")

        let interval = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: try midnight(1, month: 9)))
        let closedTotal = dated.filter { interval.contains($0.0) }.reduce(0) { $0 + $1.1 }
        XCTAssertEqual(closedTotal, 60_700, "documents the old, wrong total this test guards against")
    }
}
