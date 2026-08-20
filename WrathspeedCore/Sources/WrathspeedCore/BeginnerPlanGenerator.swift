import Foundation

enum BeginnerPlanGenerator {
    static func generate(_ request: PlanRequest) -> TrainingPlan {
        var calendar = request.calendar
        calendar.firstWeekday = 1
        let start = calendar.startOfDay(for: request.startDate)
        let weeks = PlanGenerator.weekCount(for: request.goal, startDate: start, calendar: calendar)
        let weekdays = request.profile.resolvedRunWeekdays()
        let faster = request.goal.kind == .returnToRunning
        var workouts: [ScheduledWorkout] = []

        for weekIndex in 0..<weeks {
            let progress = Double(weekIndex) / Double(max(weeks - 1, 1))
            let runSeconds = faster ? 60 + progress * 240 : 30 + progress * 180
            let walkSeconds = max(20, faster ? 90 - progress * 70 : 120 - progress * 80)
            let repeats = faster ? 8 : 6 + weekIndex / 2
            let isLong: (Weekday) -> Bool = { $0 == request.profile.longRunWeekday }
            let weekStart = calendar.date(byAdding: .day, value: weekIndex * 7, to: start) ?? start

            for day in weekdays {
                let date = PlanGenerator.dateOnWeekday(day, weekStart: weekStart, calendar: calendar)
                let longMultiplier = isLong(day) ? 1.4 : 1.0
                let blueprint = walkRun(
                    date: date,
                    runSeconds: runSeconds,
                    walkSeconds: walkSeconds,
                    repeats: Int(Double(repeats) * longMultiplier),
                    location: request.location,
                    title: isLong(day) ? "Walk-run (long)" : "Walk-run"
                )
                workouts.append(ScheduledWorkout(blueprint: blueprint))
            }
        }

        workouts.sort { $0.date < $1.date }
        return TrainingPlan(goal: request.goal, profile: request.profile, workouts: workouts)
    }

    static func walkRun(
        date: Date,
        runSeconds: Double,
        walkSeconds: Double,
        repeats: Int,
        location: RunLocation,
        title: String = "Walk-run"
    ) -> WorkoutBlueprint {
        var steps: [WorkoutStep] = [
            WorkoutStep(name: "Warm up walk", target: .duration(seconds: 120), intensity: .rpe(2)),
        ]
        for i in 1...max(1, repeats) {
            steps.append(WorkoutStep(name: "Run \(i)", target: .duration(seconds: runSeconds), intensity: .rpe(5)))
            steps.append(WorkoutStep(name: "Walk \(i)", target: .duration(seconds: walkSeconds), intensity: .rpe(2)))
        }
        steps.append(WorkoutStep(name: "Cool down walk", target: .duration(seconds: 120), intensity: .rpe(2)))
        return WorkoutBlueprint(
            date: date,
            kind: .walkRun,
            title: title,
            location: location,
            steps: steps,
            plannedDistanceMeters: 0,
            usesPaceTargets: false
        )
    }
}
