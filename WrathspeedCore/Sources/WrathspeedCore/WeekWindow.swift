import Foundation

/// The half-open week containing a date: `[start, end)`.
///
/// This exists because `DateInterval.contains(_:)` is closed at both ends -- it returns true
/// for a date exactly equal to `end`. Every workout in a generated plan is scheduled at local
/// midnight, and `end` is the next week's midnight, so the plain
/// `calendar.dateInterval(of: .weekOfYear, for:)?.contains(workout.date)` spelling counted the
/// following week's first workout in *both* weeks. On the Today screen that showed a 33.0 mi
/// week as "38 MI" -- the next Sunday's 4.7 mi tempo run, added twice over.
///
/// `HistoryInsights.weeklySummary` already did this correctly by hand; this is that comparison,
/// named once, so the next caller cannot reach for `DateInterval` and reintroduce the bug.
public struct WeekWindow: Sendable {
    public let start: Date
    public let end: Date

    /// The week containing `date`, or `nil` when the calendar cannot produce one.
    public init?(containing date: Date, calendar: Calendar = .current) {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let end = calendar.date(byAdding: .day, value: 7, to: start)
        else { return nil }
        self.start = start
        self.end = end
    }

    /// The week beginning at `start`, for callers that already hold a week boundary -- a group
    /// key from `weekGroups()`, or the week a calendar screen is paged to.
    ///
    /// This was removed as unused when `WeekWindow` was introduced and reinstated once three
    /// callers wanted it. It exists so those callers do not each re-derive `start + 7 days` and
    /// its comparison, which is how the closed-interval bug got into five places to begin with.
    public init?(startingAt start: Date, calendar: Calendar = .current) {
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
        self.start = start
        self.end = end
    }

    /// Half-open, unlike `DateInterval.contains`: the final instant belongs to the next week.
    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

public extension Calendar {
    /// The half-open week containing `date`. Prefer this over `dateInterval(of:for:)` whenever
    /// the result is used to test membership -- see `WeekWindow`.
    func weekWindow(for date: Date) -> WeekWindow? {
        WeekWindow(containing: date, calendar: self)
    }
}
