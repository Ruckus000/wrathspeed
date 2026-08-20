import XCTest
@testable import WrathspeedCore

final class NotFeeling100DiscardTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testTodayCreatedFutureStartCanDiscard() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let future = calendar.date(byAdding: .day, value: 3, to: today)!
        let adjustment = N100Adjustment(
            start: future,
            dayCount: 7,
            mode: .reducedDifficulty,
            returnPace: .balanced,
            createdAt: today
        )
        XCTAssertTrue(NotFeeling100Rules.canDiscardOnCreationDay(adjustment: adjustment, createdOn: today, calendar: calendar))
    }

    func testTodayCreatedBackdatedStartCanDiscard() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let backdated = calendar.date(byAdding: .day, value: -2, to: today)!
        let adjustment = N100Adjustment(
            start: backdated,
            dayCount: 7,
            mode: .reducedDifficulty,
            returnPace: .balanced,
            createdAt: today
        )
        XCTAssertTrue(NotFeeling100Rules.canDiscardOnCreationDay(adjustment: adjustment, createdOn: today, calendar: calendar))
    }

    func testYesterdayCreatedCannotDiscardToday() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let adjustment = N100Adjustment(
            start: today,
            dayCount: 7,
            mode: .reducedDifficulty,
            returnPace: .balanced,
            createdAt: yesterday
        )
        XCTAssertFalse(NotFeeling100Rules.canDiscardOnCreationDay(adjustment: adjustment, createdOn: today, calendar: calendar))
    }

    func testLegacyDecodeWithoutCreatedAtCannotDiscard() throws {
        let adjustment = N100Adjustment(
            start: Date(timeIntervalSince1970: 1_772_102_400),
            dayCount: 7,
            mode: .reducedDifficulty,
            returnPace: .balanced
        )
        let data = try JSONEncoder().encode(adjustment)
        let decoded = try JSONDecoder().decode(N100Adjustment.self, from: data)
        XCTAssertNil(decoded.createdAt)
        XCTAssertFalse(NotFeeling100Rules.canDiscardOnCreationDay(adjustment: decoded, createdOn: Date()))
    }
}
