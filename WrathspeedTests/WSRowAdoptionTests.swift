import XCTest

/// Fails when a view file grows a bare `HStack { A; Spacer(); B }` instead of using `WSRow`.
///
/// This scans source rather than behaviour, which is unusual and deliberate. The defect class is
/// "somebody wrote a bare row", and that is a property of the source: a behavioural test can only
/// check rows that were already migrated, which is exactly the gap that let Today's `STREAK 0`
/// render as `STREA` / `K` long after the row problem was supposedly fixed. Adoption is the part
/// that decayed, so adoption is the part that needs the guard.
///
/// A row shaped `HStack { X; Spacer() }` is fine and is not flagged — the spacer absorbs all the
/// slack, so a single child cannot be squeezed. Only content on *both* sides of a spacer competes
/// for width.
final class WSRowAdoptionTests: XCTestCase {
    /// Deliberate exceptions. Each one needs a reason, so that an exception is a decision someone
    /// wrote down rather than a row that slipped through.
    private let allowed: [String: String] = [
        "WSRow.swift": "WSRow's own horizontal candidate — the thing every other row defers to.",
    ]

    func testNoViewFileHasABareSqueezableRow() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WrathspeedTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Wrathspeed")

        var offenders: [String] = []
        var scanned = 0

        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []

        for file in files {
            let name = file.lastPathComponent
            if allowed[name] != nil { continue }
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            scanned += 1
            offenders += squeezableRows(in: lines).map { "\(name):\($0)" }
        }

        XCTAssertGreaterThan(scanned, 20, "the scanner found almost no sources — the path is probably wrong")
        XCTAssertTrue(
            offenders.isEmpty,
            """
            These rows put content on both sides of a Spacer inside a plain HStack, so each side \
            can be squeezed narrower than its own longest word and the text breaks mid-word. \
            Use WSRow instead, or add the file to `allowed` with a reason:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    /// Line numbers of `HStack` blocks that hold a top-level `Spacer` with content on both sides.
    /// Brace-matched, and only children at the block's own indentation are considered, so a nested
    /// stack's spacer is not mistaken for this one's.
    private func squeezableRows(in lines: [String]) -> [Int] {
        var found: [Int] = []
        for (index, line) in lines.enumerated() {
            guard line.trimmingCharacters(in: .whitespaces).hasPrefix("HStack"),
                  line.hasSuffix("{"),
                  let end = blockEnd(lines, from: index),
                  // A ViewThatFits already supplies the stacked alternative, so its horizontal
                  // candidate is meant to look like this. Rows with three or more slots use it
                  // directly, since WSRow takes two.
                  !isInsideViewThatFits(lines, at: index)
            else { continue }

            let body = Array(lines[(index + 1) ..< end])
            guard let childIndent = body.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                .map(indent) else { continue }

            var sawSpacer = false, before = false, after = false
            for child in body where indent(child) == childIndent {
                let text = child.trimmingCharacters(in: .whitespaces)
                if text.isEmpty || text.hasPrefix(".") || text.hasPrefix("}") { continue }
                if text.hasPrefix("Spacer(") { sawSpacer = true; continue }
                if sawSpacer { after = true } else { before = true }
            }
            if sawSpacer && before && after { found.append(index + 1) }
        }
        return found
    }

    /// Whether an enclosing, still-open `ViewThatFits` block contains this line.
    private func isInsideViewThatFits(_ lines: [String], at index: Int) -> Bool {
        var depth = 0
        for i in stride(from: index - 1, through: 0, by: -1) {
            depth += lines[i].filter { $0 == "}" }.count
            depth -= lines[i].filter { $0 == "{" }.count
            if depth < 0 {
                if lines[i].contains("ViewThatFits") { return true }
                depth = 0
            }
        }
        return false
    }

    private func indent(_ line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    private func blockEnd(_ lines: [String], from start: Int) -> Int? {
        var depth = 0
        for i in start ..< lines.count {
            depth += lines[i].filter { $0 == "{" }.count
            depth -= lines[i].filter { $0 == "}" }.count
            if depth == 0 && i > start { return i }
        }
        return nil
    }
}
