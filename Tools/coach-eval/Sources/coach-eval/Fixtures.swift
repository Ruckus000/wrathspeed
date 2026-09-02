import Foundation
import WrathspeedCore

/// The plans the golden set runs against. Three shapes, one pinned clock.
///
/// Everything here is public Core API that the harness refactor does not touch, so these are
/// stable regardless of how the model contract is extracted. `asOf` is pinned -- never `Date()` --
/// so a case's expected `wN` and its relative-date expectations mean the same thing on every run.
enum Fixture: String, CaseIterable {
    /// Beginner 5K, three days a week, long run Saturday. Runs Tue/Thu/Sat.
    case f1BeginnerTueThuSat
    /// Intermediate 10K, five days a week, long run Sunday. Saturday is available here.
    case f2Intermediate5Day
    /// Intermediate half marathon in week 9 of 12: ~40 completed workouts precede today. Exists
    /// to show what the model sees when most of the plan is behind the runner.
    case f3LatePlan

    /// Wednesday 2026-09-02, the day the audit was designed; midweek so "this week", "tomorrow"
    /// and "this weekend" all mean something non-trivial.
    static let asOf: Date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2))!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 1
        return calendar
    }

    struct Built {
        var plan: TrainingPlan
        var profile: RunnerProfile
        var results: [WorkoutResult]
        /// `w1..wN` exactly as the coach numbers them, so a case can name a workout by date and
        /// the harness resolves it to the reference the model will use.
        var references: [(workout: ScheduledWorkout, reference: String)]

        func reference(on day: Date) -> String? {
            references.first { Fixture.calendar.isDate($0.workout.date, inSameDayAs: day) }?.reference
        }
    }

    func build() -> Built {
        let calendar = Fixture.calendar
        let (goal, profile, weeksElapsed): (TrainingGoal, RunnerProfile, Int) = switch self {
        case .f1BeginnerTueThuSat:
            (TrainingGoal(kind: .fiveK),
             RunnerProfile(ability: .intermediate, daysPerWeek: 3, longRunWeekday: .saturday, unit: .kilometers, vdot: 35),
             3)
        case .f2Intermediate5Day:
            (TrainingGoal(kind: .tenK),
             RunnerProfile(ability: .intermediate, daysPerWeek: 5, longRunWeekday: .sunday, unit: .kilometers, vdot: 45),
             3)
        case .f3LatePlan:
            (TrainingGoal(kind: .halfMarathon),
             RunnerProfile(ability: .intermediate, daysPerWeek: 5, longRunWeekday: .sunday, unit: .kilometers, vdot: 45),
             8)
        }

        // Start the plan `weeksElapsed` weeks before asOf, on a Sunday, so weeks line up.
        let asOfWeekStart = calendar.dateInterval(of: .weekOfYear, for: Fixture.asOf)!.start
        let start = calendar.date(byAdding: .day, value: -7 * weeksElapsed, to: asOfWeekStart)!
        var plan = PlanGenerator.generate(PlanRequest(goal: goal, profile: profile, startDate: start, calendar: calendar))

        // Everything before today is done, with a plausible result so the prompt's "recent run
        // summaries" and adherence have something to say.
        let today = calendar.startOfDay(for: Fixture.asOf)
        var results: [WorkoutResult] = []
        plan.workouts = plan.workouts.map { workout in
            guard workout.date < today, workout.blueprint.kind.isRunning else { return workout }
            var done = workout
            done.status = .completed
            results.append(WorkoutResult(
                workoutID: workout.id,
                startedAt: calendar.date(byAdding: .hour, value: 7, to: workout.date)!,
                duration: workout.blueprint.plannedDistanceMeters / 1000 * 360,
                distanceMeters: workout.blueprint.plannedDistanceMeters,
                averagePaceSecPerKm: 360,
                heartRateAverage: 152,
                location: .outdoor,
                route: [],
                source: .wrathspeedPhone
            ))
            return done
        }

        let references = CoachPlanRules.references(
            in: plan, asOf: Fixture.asOf, calendar: calendar, limit: CoachPlanRules.modelReferenceLimit
        )
        return Built(plan: plan, profile: profile, results: results, references: references)
    }
}
