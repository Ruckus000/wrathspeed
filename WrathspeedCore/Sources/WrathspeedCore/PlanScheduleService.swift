import Foundation

public enum PlanScheduleService {
  public static func navigableWeekStarts(
    centeredOn date: Date = Date(),
    calendar: Calendar = .current
  ) -> [Date] {
    guard let current = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
    let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: current) ?? current
    let next = calendar.date(byAdding: .weekOfYear, value: 1, to: current) ?? current
    return [previous, current, next]
  }

  public static func planDay(
    for date: Date,
    calendar: Calendar
  ) -> Date {
    calendar.startOfDay(for: date)
  }

  public static func canMove(
    workout: ScheduledWorkout,
    to date: Date,
    plan: TrainingPlan,
    profile: RunnerProfile? = nil,
    asOf: Date = Date(),
    calendar: Calendar = .current
  ) -> PlanMoveValidation {
    let target = planDay(for: date, calendar: calendar)
    let today = planDay(for: asOf, calendar: calendar)
    guard target >= today else {
      return PlanMoveValidation(allowed: false, reason: "You can’t schedule runs in the past.")
    }
    let conflict = plan.workouts.contains {
      $0.id != workout.id
        && calendar.isDate($0.date, inSameDayAs: target)
        && ($0.status == .scheduled || $0.status == .convertedToEasy)
    }
    if conflict {
      return PlanMoveValidation(allowed: false, reason: "You already have a run that day.")
    }
    var warnings: [String] = []
    if workout.blueprint.kind == .longRun,
       !AdaptationRules.canMoveLongRun(from: workout.date, to: target) {
      return PlanMoveValidation(allowed: false, reason: "Long runs can only move within 48 hours.")
    }
    if AdaptationRules.wouldCreateAdjacentQuality(existing: plan.workouts, moving: workout, to: target, calendar: calendar) {
      warnings.append("That would place quality days back-to-back.")
    }
    if wouldConcentrateWeeklyLoad(plan: plan, moving: workout, to: target, calendar: calendar) {
      warnings.append("That would concentrate this week’s load.")
    }
    if let unusual = unusualLongRunPlacementWarning(
      workout: workout,
      to: target,
      profile: profile,
      calendar: calendar
    ) {
      warnings.append(unusual)
    }
    return PlanMoveValidation(allowed: true, warnings: warnings)
  }

  public static func wouldConcentrateWeeklyLoad(
    plan: TrainingPlan,
    moving: ScheduledWorkout,
    to date: Date,
    calendar: Calendar = .current
  ) -> Bool {
    guard moving.blueprint.kind.isRunning else { return false }
    guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return false }
    let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart

    func weekTotal(excludingMoving: Bool) -> Double {
      plan.workouts.reduce(0) { partial, workout in
        guard workout.blueprint.kind.isRunning,
              workout.status == .scheduled || workout.status == .convertedToEasy,
              workout.date >= weekStart,
              workout.date < weekEnd
        else { return partial }
        if excludingMoving && workout.id == moving.id { return partial }
        return partial + workout.blueprint.plannedDistanceMeters
      }
    }

    let withoutMoving = weekTotal(excludingMoving: true)
    let withMoving = withoutMoving + moving.blueprint.plannedDistanceMeters
    let average = averageWeeklyRunningLoad(plan: plan, calendar: calendar)
    guard average > 0 else { return false }
    return withMoving > average * 1.25
  }

  public static func unusualLongRunPlacementWarning(
    workout: ScheduledWorkout,
    to date: Date,
    profile: RunnerProfile?,
    calendar: Calendar = .current
  ) -> String? {
    guard workout.blueprint.kind == .longRun else { return nil }
  if let profile {
      let targetWeekday = calendar.component(.weekday, from: date)
      let preferred = profile.longRunWeekday.calendarWeekday
      if targetWeekday != preferred {
        return "Long runs are usually scheduled on \(profile.longRunWeekday.displayName)."
      }
    }
    let originalDay = calendar.startOfDay(for: workout.date)
    let targetDay = calendar.startOfDay(for: date)
    let delta = abs(targetDay.timeIntervalSince(originalDay))
    if delta > 24 * 3600 {
      return "Moving a long run more than one day is unusual."
    }
    return nil
  }

  private static func averageWeeklyRunningLoad(
    plan: TrainingPlan,
    calendar: Calendar
  ) -> Double {
    let groups = Dictionary(grouping: plan.workouts.filter {
      $0.blueprint.kind.isRunning && ($0.status == .scheduled || $0.status == .convertedToEasy)
    }) { workout in
      calendar.dateInterval(of: .weekOfYear, for: workout.date)?.start ?? workout.date
    }
    guard !groups.isEmpty else { return 0 }
    let totals = groups.values.map { workouts in
      workouts.reduce(0) { $0 + $1.blueprint.plannedDistanceMeters }
    }
    return totals.reduce(0, +) / Double(totals.count)
  }
}

public struct PlanMoveValidation: Equatable, Sendable {
  public var allowed: Bool
  public var reason: String?
  public var warnings: [String]

  public init(allowed: Bool, reason: String? = nil, warnings: [String] = []) {
    self.allowed = allowed
    self.reason = reason
    self.warnings = warnings
  }
}

public struct PlanUndoSnapshot: Codable, Equatable, Sendable {
  public var plan: TrainingPlan
  public var n100: N100Adjustment?

  public init(plan: TrainingPlan, n100: N100Adjustment?) {
    self.plan = plan
    self.n100 = n100
  }
}
