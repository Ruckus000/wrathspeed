import Foundation
import WrathspeedCore

/// Runs the golden set against the real model N times per case and writes what it saw.
@MainActor
enum Runner {
    struct Options {
        var runs = 5
        var only: String? = nil
        var outputDirectory = URL(fileURLWithPath: "build")
    }

    static func run(_ options: Options) async throws -> [RunRecord] {
        let cases = GoldenCase.all.filter { options.only.map($0.id.contains) ?? true }
        let built = Dictionary(uniqueKeysWithValues: Fixture.allCases.map { ($0, $0.build()) })
        var records: [RunRecord] = []
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let runsDirectory = options.outputDirectory.appendingPathComponent("runs")
        try FileManager.default.createDirectory(at: runsDirectory, withIntermediateDirectories: true)
        let jsonl = runsDirectory.appendingPathComponent("\(stamp).jsonl")
        FileManager.default.createFile(atPath: jsonl.path, contents: nil)
        let handle = try FileHandle(forWritingTo: jsonl)
        defer { try? handle.close() }
        let encoder = JSONEncoder()

        for (index, goldenCase) in cases.enumerated() {
            let fixture = built[goldenCase.fixture]!
            guard let context = CoachContext.make(
                plan: fixture.plan, profile: fixture.profile, results: fixture.results,
                asOf: Fixture.asOf, calendar: Fixture.calendar
            ) else { throw RunnerError.noContext(goldenCase.id) }
            let promptText = CoachPromptBuilder.prompt(message: goldenCase.message, context: context)

            for run in 1...options.runs {
                let client = CoachModelClient()   // fresh session: what a new conversation sees
                let started = Date()
                var record: RunRecord
                do {
                    for turn in goldenCase.turns { _ = try await client.respond(to: turn, context: context) }
                    let answer = try await client.respond(to: goldenCase.message, context: context)
                    let resolution = CoachIntentRecovery.resolution(modelIntent: answer.mapped, message: goldenCase.message, priorTurns: goldenCase.turns, context: context, calendar: Fixture.calendar)
                    let resolved = resolution.intent
                    var shown = answer.raw
                    shown.reply = resolution.demotedAsk ?? answer.reply   // what the runner reads
                    let isCannedAsk = resolution.demotedAsk != nil
                        || (answer.mapped == .clarificationRequired && CoachIntentMapper.clarificationAsk(for: answer.raw) != nil)
                    let scored = Scoring.score(goldenCase, built: fixture, raw: shown, mapped: answer.mapped,
                                               resolved: resolved, promptText: promptText, isCannedAsk: isCannedAsk)
                    var flags = scored.flags
                    if answer.refused { flags.append("REFUSED") }
                    record = RunRecord(
                        caseID: goldenCase.id, family: goldenCase.family, fixture: goldenCase.fixture.rawValue,
                        run: run, message: goldenCase.message,
                        rawIntent: answer.raw.intent, rawFields: fields(of: answer.raw),
                        mappedIntent: IntentName(answer.mapped), resolvedIntent: IntentName(resolved),
                        proposal: scored.proposal, reply: shown.reply,
                        latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                        pass: scored.failures.isEmpty, failures: scored.failures, flags: flags
                    )
                } catch {
                    record = RunRecord(
                        caseID: goldenCase.id, family: goldenCase.family, fixture: goldenCase.fixture.rawValue,
                        run: run, message: goldenCase.message, rawIntent: "", rawFields: [:],
                        mappedIntent: .clarificationRequired, resolvedIntent: .clarificationRequired,
                        proposal: "none", reply: "", latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                        pass: false, failures: ["MODEL_ERROR \(error)"], flags: []
                    )
                }
                records.append(record)
                handle.write(try encoder.encode(record)); handle.write(Data("\n".utf8))
                let mark = record.pass ? "ok " : "FAIL"
                print("[\(index + 1)/\(cases.count)] \(mark) \(goldenCase.id) run \(run): \(record.rawIntent) → \(record.mappedIntent.rawValue) → \(record.resolvedIntent.rawValue) [\(record.proposal)] \(record.latencyMs)ms \(record.failures.joined(separator: "; "))")
            }
        }
        print("wrote \(jsonl.path)")
        return records
    }

    private static func fields(of raw: CoachTypedResponse) -> [String: String] {
        var out: [String: String] = [:]
        if let v = raw.workoutReference { out["workoutReference"] = v }
        if let v = raw.targetWeekday { out["targetWeekday"] = v }
        if let v = raw.targetVDOT { out["targetVDOT"] = String(v) }
        if let v = raw.travelStart { out["travelStart"] = v }
        if let v = raw.travelEnd { out["travelEnd"] = v }
        return out
    }

    enum RunnerError: Error { case noContext(String) }
}

/// Per-case verdicts and the two committed artifacts.
enum Report {
    struct CaseResult: Codable {
        var id: String
        var family: String
        var safety: Bool
        var passes: Int
        var runs: Int
        var tierMet: Bool
        var failures: [String]
        var flags: [String]
        var proposals: [String]
    }

    struct Baseline: Codable {
        var promptHash: String
        var osVersion: String
        var date: String
        var runs: Int
        var cases: [String: Int]
    }

    static func summarize(_ records: [RunRecord]) -> [CaseResult] {
        let byCase = Dictionary(grouping: records, by: \.caseID)
        return GoldenCase.all.compactMap { goldenCase in
            guard let runs = byCase[goldenCase.id], !runs.isEmpty else { return nil }
            let passes = runs.filter(\.pass).count
            let required = goldenCase.safety ? runs.count : Int((Double(runs.count) * 0.8).rounded(.up))
            return CaseResult(
                id: goldenCase.id, family: goldenCase.family, safety: goldenCase.safety,
                passes: passes, runs: runs.count, tierMet: passes >= required,
                failures: Array(Set(runs.flatMap(\.failures))).sorted(),
                flags: Array(Set(runs.flatMap(\.flags))).sorted(),
                proposals: Array(Set(runs.map(\.proposal))).sorted()
            )
        }
    }

    static func scorecard(_ results: [CaseResult], records: [RunRecord]) -> String {
        var out = "# Coach evaluation scorecard\n\n"
        out += "Prompt hash `\(CoachPromptBuilder.promptHash)` · \(ProcessInfo.processInfo.operatingSystemVersionString) · \(ISO8601DateFormatter().string(from: Date()))\n\n"
        let met = results.filter(\.tierMet).count
        let safetyResults = results.filter(\.safety)
        out += "**\(met)/\(results.count) cases met their tier.** Safety: \(safetyResults.filter(\.tierMet).count)/\(safetyResults.count) at N/N. Median latency \(median(records.map(\.latencyMs))) ms.\n\n"
        for family in Array(Set(results.map(\.family))).sorted() {
            let rows = results.filter { $0.family == family }
            out += "## \(family) — \(rows.filter(\.tierMet).count)/\(rows.count)\n\n| case | passes | tier | rule | failures | flags |\n|---|---|---|---|---|---|\n"
            for r in rows {
                out += "| `\(r.id)`\(r.safety ? " 🛡" : "") | \(r.passes)/\(r.runs) | \(r.tierMet ? "met" : "**MISSED**") | \(r.proposals.joined(separator: "; ")) | \(r.failures.joined(separator: "; ")) | \(r.flags.joined(separator: ", ")) |\n"
            }
            out += "\n"
        }
        return out
    }

    static func baseline(_ results: [CaseResult], runs: Int) -> Baseline {
        Baseline(
            promptHash: CoachPromptBuilder.promptHash,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            date: ISO8601DateFormatter().string(from: Date()),
            runs: runs,
            cases: Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0.passes) })
        )
    }

    /// Exit non-zero on a regression. Same N required: a 3/5 and a 3/3 are not the same claim.
    ///
    /// Run-to-run variance is real: a rerun of an unchanged contract at N=5 moved nine cases by
    /// one run. So an ordinary case regresses only when it drops by two or more runs; a safety
    /// case regresses on any drop, because its tier is N of N.
    static func compare(_ results: [CaseResult], to baseline: Baseline, runs: Int) -> [String] {
        guard baseline.runs == runs else { return ["baseline has N=\(baseline.runs), this run has N=\(runs); compare at the same N"] }
        var regressions: [String] = []
        for r in results {
            guard let before = baseline.cases[r.id] else { continue }
            let drop = before - r.passes
            if drop >= 2 || (r.safety && drop >= 1) {
                regressions.append("\(r.id)\(r.safety ? " 🛡" : ""): \(before)/\(runs) → \(r.passes)/\(runs)")
            }
        }
        if baseline.promptHash != CoachPromptBuilder.promptHash {
            regressions.insert("prompt hash changed \(baseline.promptHash) → \(CoachPromptBuilder.promptHash); regressions below are against a different prompt", at: 0)
        }
        return regressions
    }

    private static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }
}
