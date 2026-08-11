import SwiftUI
import WrathspeedCore

struct OnboardingView: View {
    @Environment(AppStore.self) private var store

    @State private var kind: GoalKind = .halfMarathon
    @State private var weeks: Double = 12
    @State private var hasRaceDate = false
    @State private var raceDate = Date().addingTimeInterval(12 * 7 * 24 * 3600)
    @State private var ability: Ability = .intermediate
    @State private var days = 4
    @State private var longRun: Weekday = .saturday
    @State private var mileageDisplay = 30.0
    @State private var longestDisplay = 10.0
    @State private var hasRaceTime = false
    @State private var raceDistanceKind: GoalKind = .fiveK
    @State private var raceHours = 0
    @State private var raceMinutes = 25
    @State private var raceSeconds = 0
    @State private var strength = StrengthPreferences()

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    Picker("Plan type", selection: $kind) {
                        ForEach(GoalKind.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    if !kind.isBeginner {
                        Toggle("I have a race date", isOn: $hasRaceDate)
                        if hasRaceDate {
                            DatePicker("Race date", selection: $raceDate, displayedComponents: .date)
                        }
                        Stepper("Length: \(Int(weeks)) weeks", value: $weeks, in: Double(kind.minimumWeeks)...26)
                    }
                }
                Section("Running") {
                    Picker("Ability", selection: $ability) {
                        ForEach(Ability.allCases, id: \.self) { item in
                            Text(item.rawValue.capitalized).tag(item)
                        }
                    }
                    Stepper("Days per week: \(days)", value: $days, in: 3...6)
                    Picker("Long run day", selection: $longRun) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            Text(day.label).tag(day)
                        }
                    }
                    HStack {
                        Text("Weekly mileage")
                        Spacer()
                        TextField("Mileage", value: $mileageDisplay, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Longest recent run")
                        Spacer()
                        TextField("Longest", value: $longestDisplay, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("Recent race time", isOn: $hasRaceTime)
                    if hasRaceTime {
                        Picker("Distance", selection: $raceDistanceKind) {
                            Text("5K").tag(GoalKind.fiveK)
                            Text("10K").tag(GoalKind.tenK)
                            Text("Half").tag(GoalKind.halfMarathon)
                            Text("Marathon").tag(GoalKind.marathon)
                        }
                        HStack {
                            TextField("H", value: $raceHours, format: .number)
                            TextField("M", value: $raceMinutes, format: .number)
                            TextField("S", value: $raceSeconds, format: .number)
                        }
                    }
                }
                Section("Strength") {
                    Picker("Experience", selection: $strength.ability) {
                        ForEach(StrengthAbility.allCases, id: \.self) { item in
                            Text(item.rawValue.capitalized).tag(item)
                        }
                    }
                    Picker("Goal", selection: $strength.goal) {
                        ForEach(StrengthGoal.allCases, id: \.self) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    Picker("Session length", selection: $strength.durationMinutes) {
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("60 min").tag(60)
                    }
                    Stepper("Sessions per week: \(strength.sessionsPerWeek)", value: $strength.sessionsPerWeek, in: 1...4)
                }
            }
            .navigationTitle("Wrathspeed")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create plan") { submit() }
                }
            }
        }
    }

    private func submit() {
        let unit = DistanceUnit.default()
        let recent: RaceResult? = {
            guard hasRaceTime, let meters = raceDistanceKind.distanceMeters else { return nil }
            let duration = TimeInterval(raceHours * 3600 + raceMinutes * 60 + raceSeconds)
            return RaceResult(distanceMeters: meters, duration: duration)
        }()
        let profile = RunnerProfile(
            ability: ability,
            weeklyMileageMeters: Units.meters(fromDisplay: mileageDisplay, unit: unit),
            longestRunMeters: Units.meters(fromDisplay: longestDisplay, unit: unit),
            daysPerWeek: days,
            longRunWeekday: longRun,
            unit: unit,
            recentRace: recent
        )
        let goal = TrainingGoal(
            kind: kind,
            raceDate: hasRaceDate && !kind.isBeginner ? raceDate : nil,
            weekCount: Int(weeks)
        )
        store.completeOnboarding(goal: goal, profile: profile, strength: strength)
    }
}

extension Weekday {
    var label: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }
}
