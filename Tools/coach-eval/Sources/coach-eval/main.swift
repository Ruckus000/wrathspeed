import Foundation
import WrathspeedCore

// coach-eval --check
// coach-eval --run [--n 5] [--only <id-substring>] [--out build] [--compare baseline.json]
let arguments = Array(CommandLine.arguments.dropFirst())
func value(after flag: String) -> String? {
    guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

guard let command = arguments.first, ["--check", "--run", "--prompt"].contains(command) else {
    print("usage: coach-eval --check | --prompt <fixture> | --run [--n 5] [--only id] [--out build] [--compare baseline.json]")
    exit(64)
}

// `--prompt <fixture>`: exactly what the model is shown for that fixture, and how big it is.
if command == "--prompt" {
    guard let name = arguments.dropFirst().first, let fixture = Fixture(rawValue: name) else {
        print("fixtures:", Fixture.allCases.map(\.rawValue).joined(separator: ", ")); exit(64)
    }
    let built = fixture.build()
    let context = CoachContext.make(plan: built.plan, profile: built.profile, results: built.results,
                                    asOf: Fixture.asOf, calendar: Fixture.calendar)!
    let text = CoachPromptBuilder.prompt(message: "<message>", context: context)
    print(text)
    print("--- instructions \(CoachPromptBuilder.instructions.count) chars · prompt \(text.count) chars · \(context.workouts.count) workouts · \(context.recentResults.count) results")
    exit(0)
}

print("prompt hash:", CoachPromptBuilder.promptHash)
switch CoachModelClient.availability {
case .available:
    print("availability: available")
case let .unavailable(reason):
    print("availability: unavailable(\(reason)) — the harness needs Apple Intelligence on this Mac")
    exit(2)
}

if command == "--check" {
    let context = CoachContext(
        asOf: Date(), goal: TrainingGoal(kind: .fiveK),
        profile: RunnerProfile(ability: .intermediate, daysPerWeek: 3, longRunWeekday: .saturday, unit: .kilometers),
        currentWeekStart: Date(), workouts: [], recentResults: [], adherence: 1
    )
    let started = Date()
    do {
        let answer = try await CoachModelClient().respond(to: "What does VDOT mean?", context: context)
        print("raw intent: \(answer.raw.intent) | mapped: \(answer.mapped) | \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        print("reply:", answer.raw.reply)
        print("OK — the shipped contract answers from a macOS executable")
    } catch {
        print("respond failed:", error); exit(1)
    }
    exit(0)
}

var options = Runner.Options()
if let n = value(after: "--n").flatMap(Int.init) { options.runs = n }
options.only = value(after: "--only")
if let out = value(after: "--out") { options.outputDirectory = URL(fileURLWithPath: out) }

do {
    let records = try await Runner.run(options)
    let results = Report.summarize(records)
    let card = Report.scorecard(results, records: records)
    try FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)
    let cardURL = options.outputDirectory.appendingPathComponent("scorecard.md")
    try card.write(to: cardURL, atomically: true, encoding: .utf8)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let baselineURL = options.outputDirectory.appendingPathComponent("baseline.json")
    try encoder.encode(Report.baseline(results, runs: options.runs)).write(to: baselineURL)
    print("\n" + card)
    print("wrote \(cardURL.path) and \(baselineURL.path)")

    if let path = value(after: "--compare") {
        let baseline = try JSONDecoder().decode(Report.Baseline.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let regressions = Report.compare(results, to: baseline, runs: options.runs)
        if regressions.isEmpty { print("no regressions against \(path)") }
        else { print("REGRESSIONS against \(path):"); regressions.forEach { print("  " + $0) }; exit(1) }
    }
} catch {
    print("run failed:", error); exit(1)
}
