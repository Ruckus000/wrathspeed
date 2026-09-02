import XCTest
@testable import WrathspeedCore

/// On which days of the week does "I'M SORE" actually produce an applicable proposal?
///
/// `cutIntensity` used to search the current `weekOfYear` for an unstarted quality workout. The
/// generator places the week's single quality session on the earliest run day, so for 3- and
/// 4-day plans the button was blocked from the day after that session until the week rolled
/// over -- most of the week, for most plans. The UI test could not see it: it asserted
/// `KEEP AS IS`, which renders on blocked cards too.
///
/// This is the audit's first artifact. It enumerates every `daysPerWeek × longRunWeekday` shape
/// the generator can produce and, for each day the runner might ask, states whether the coach
/// can help. The oracle is what a runner means by "this week": the next seven days.
final class CoachSorenessWindowTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }

    /// A Sunday, so plan weeks and `weekOfYear` line up and the table reads naturally.
    private var planStart: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 4))!
    }

    private func profile(daysPerWeek: Int, longRun: Weekday) -> RunnerProfile {
        RunnerProfile(
            ability: .intermediate,
            weeklyMileageMeters: 35_000,
            longestRunMeters: 10_000,
            daysPerWeek: daysPerWeek,
            longRunWeekday: longRun,
            unit: .kilometers,
            vdot: 45,
            availableWeekdays: nil   // the generator's own placement, not a hand-picked set
        )
    }

    private func generatedPlan(daysPerWeek: Int, longRun: Weekday) -> (TrainingPlan, RunnerProfile) {
        let profile = profile(daysPerWeek: daysPerWeek, longRun: longRun)
        let request = PlanRequest(
            goal: TrainingGoal(kind: .fiveK),
            profile: profile,
            startDate: planStart,
            calendar: calendar
        )
        return (PlanGenerator.generate(request), profile)
    }

    /// What the runner means: an unstarted quality session and an unstarted long run somewhere
    /// in the next seven days.
    private func runnerExpectsHelp(plan: TrainingPlan, asOf: Date) -> Bool {
        let start = calendar.startOfDay(for: asOf)
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        let window = plan.workouts.filter { $0.date >= start && $0.date < end && $0.status == .scheduled }
        let quality = window.contains { $0.blueprint.kind.isQuality && $0.blueprint.kind != .race }
        let long = window.contains { $0.blueprint.kind == .longRun }
        return quality && long
    }

    private func coachHelps(plan: TrainingPlan, profile: RunnerProfile, asOf: Date) -> Bool {
        guard let result = try? CoachPlanRules.preview(
            intent: .cutIntensity, plan: plan, profile: profile, asOf: asOf, calendar: calendar
        ) else { return false }
        return !result.changes.isEmpty
    }

    func testSorenessIsApplicableWheneverTheNextSevenDaysCarryQualityAndALongRun() throws {
        let weekdays: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        // Week 3 of the plan: clear of the opening week and of any race-week taper.
        let weekStart = calendar.date(byAdding: .day, value: 14, to: planStart)!

        var table = "\nI'M SORE applicability by plan shape (rows: longRun day; cols: day asked)\n"
        var mismatches: [String] = []

        for daysPerWeek in 3...6 {
            table += "\n\(daysPerWeek) days/week      " + names.joined(separator: " ") + "\n"
            for longRun in weekdays {
                let (plan, profile) = generatedPlan(daysPerWeek: daysPerWeek, longRun: longRun)
                var row = "  long run \(names[longRun.rawValue - 1])  "
                for offset in 0..<7 {
                    let asOf = calendar.date(byAdding: .day, value: offset, to: weekStart)!
                    let expected = runnerExpectsHelp(plan: plan, asOf: asOf)
                    let actual = coachHelps(plan: plan, profile: profile, asOf: asOf)
                    row += (actual ? " ✓ " : " · ") + " "
                    if expected != actual {
                        mismatches.append(
                            "\(daysPerWeek)d/wk, long run \(names[longRun.rawValue - 1]), asked \(names[offset]): "
                                + "runner expects \(expected ? "help" : "nothing"), coach gives \(actual ? "a proposal" : "a blocked card")"
                        )
                    }
                }
                table += row + "\n"
            }
        }
        print(table)

        XCTAssertTrue(
            mismatches.isEmpty,
            "The coach and the runner disagree on \(mismatches.count) day(s):\n  " + mismatches.joined(separator: "\n  ")
        )
    }
}
