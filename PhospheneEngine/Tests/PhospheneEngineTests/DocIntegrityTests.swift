// DocIntegrityTests — the doc-set's referential-integrity gate (DOC.4.1, 2026-06-11).
//
// Born from two silent corruptions found by the DOC.4 pruning sweep:
//   • The parallel FBS.S5c commit (`5ac5ad90`) accidentally DELETED the whole D-155 entry
//     from DECISIONS.md while editing the adjacent D-154 amendment — undetected for a day,
//     found only by a manual grep sweep.
//   • D-145 was number-reserved at the Nimbus renumbering and cited across docs/code/tests,
//     but the entry was never actually written.
// Parallel sessions edit the shared inventory docs (DECISIONS, KNOWN_ISSUES, CLAUDE.md)
// concurrently; nothing structural caught either failure. This suite makes the invariants
// executable so the regression gate (run on every increment) catches the class.
//
// Invariants:
//   1. D-number CONTINUITY — every D-001…D-max has a `## D-NNN` header in DECISIONS.md or
//      DECISIONS_HISTORY.md (catches whole-entry deletion even when nothing cites it, and
//      reserved-but-never-filed numbers).
//   2. D-header UNIQUENESS — at most one non-Amendment header per number across both files
//      (catches the D-086 class: a half-landed move leaving the entry in both files).
//      Explicit `— Amendment` headers (the D-082 convention) are allowed.
//   3. D-citation RESOLUTION — every `D-NNN` token cited in CLAUDE.md, engine/app source,
//      or the active docs tree resolves to a header in one of the two files.
//   4. BUG continuity + uniqueness in KNOWN_ISSUES.md (top-level `### BUG-NNN` entries;
//      dotted sub-entries like BUG-007.4 are the BUG-007 convention and don't count).
//   5. Failed-Approach RESOLUTION — every `Failed Approach #N` / `FA #N` citation resolves
//      to an active CLAUDE.md entry or a gap-table row (the DOC.3 relocation convention).
//
// House rule this suite enforces, stated once: doc entries are MOVED, never deleted; a
// number once assigned must forever resolve somewhere greppable.

import Foundation
import Testing

@Suite("Doc referential integrity (DOC.4.1)")
struct DocIntegrityTests {

    // MARK: - Repo file access

    /// Repo root derived from this file's path (…/PhospheneEngine/Tests/PhospheneEngineTests/…).
    private static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }   // file → Tests dir ×2 → PhospheneEngine → root
        return url
    }()

    private static func read(_ relative: String) -> String? {
        try? String(contentsOf: repoRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    /// Skip everything cleanly when the repo docs aren't present (e.g. a bundled test
    /// product run outside the checkout) — same print-skip pattern as the session-artifact
    /// gates. A MISSING doc in a real checkout is itself a failure, so distinguish: the
    /// docs directory must exist for the gate to arm.
    private static var docsPresent: Bool {
        FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("docs/DECISIONS.md").path)
            && FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("CLAUDE.md").path)
    }

    private static func matches(_ pattern: String, _ text: String, options: NSRegularExpression.Options = [.anchorsMatchLines]) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.numberOfRanges > 1 ? $0.range(at: 1) : $0.range)
        }
    }

    /// Every file whose citations must resolve: CLAUDE.md + Swift/Metal/JSON sources + the
    /// docs tree (all of it — history files keep entries forever, so even changelog and
    /// archive citations must resolve SOMEWHERE; that is the invariant).
    private static func citationCorpus() -> String {
        var parts: [String] = []
        if let c = read("CLAUDE.md") { parts.append(c) }
        let fm = FileManager.default
        for top in ["PhospheneEngine/Sources", "PhospheneApp", "PhospheneEngine/Tests", "docs"] {
            let base = repoRoot.appendingPathComponent(top)
            guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker {
                let ext = url.pathExtension
                guard ["swift", "metal", "md", "json"].contains(ext) else { continue }
                if let t = try? String(contentsOf: url, encoding: .utf8) { parts.append(t) }
            }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Gates

    @Test("D-numbers: continuous, unique, and every citation resolves (DECISIONS + HISTORY)")
    func decisionsIntegrity() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let dec = Self.read("docs/DECISIONS.md") ?? ""
        let hist = Self.read("docs/DECISIONS_HISTORY.md") ?? ""
        #expect(!dec.isEmpty && !hist.isEmpty, "DECISIONS.md / DECISIONS_HISTORY.md unreadable")

        // Header inventory (numeric decisions). Amendment headers (D-082 convention) are
        // separate lines re-using the number with an explicit "Amendment" marker.
        let headerLines = Self.matches(#"^## (D-\d{3}[^\n]*)"#, dec + "\n" + hist)
        var primary: [Int: Int] = [:]
        for line in headerLines {
            let num = Int(line.dropFirst(2).prefix(3)) ?? -1
            if line.contains("Amendment") { continue }
            primary[num, default: 0] += 1
        }
        let maxN = primary.keys.max() ?? 0
        #expect(maxN >= 160, "Decision inventory imploded (max D-\(maxN)) — wholesale loss?")

        // 1. CONTINUITY — a vanished entry shows up as a hole.
        let holes = (1...maxN).filter { primary[$0] == nil }
        #expect(holes.isEmpty, "D-number hole(s) \(holes.map { "D-\(String(format: "%03d", $0))" }): an entry was deleted or a reserved number was never filed. Entries are MOVED to DECISIONS_HISTORY.md, never deleted (the D-155/D-145 classes — see this suite's header).")

        // 2. UNIQUENESS — the D-086 both-files class.
        let dupes = primary.filter { $0.value > 1 }.keys.sorted()
        #expect(dupes.isEmpty, "Duplicate non-Amendment header(s) for \(dupes.map { "D-\(String(format: "%03d", $0))" }) across DECISIONS.md + DECISIONS_HISTORY.md — a move must DELETE the source copy.")

        // 3. RESOLUTION — every cited token has a header somewhere.
        let defined = Set(headerLines.compactMap { Int($0.dropFirst(2).prefix(3)) })
        let cited = Set(Self.matches(#"D-(\d{3})(?![\d.\w])"#, Self.citationCorpus(), options: []).compactMap(Int.init))
        let unresolved = cited.subtracting(defined).sorted()
        #expect(unresolved.isEmpty, "Cited but undefined decision(s): \(unresolved.map { "D-\(String(format: "%03d", $0))" }) — either the entry was deleted (restore it) or the number was used without filing (file it).")
    }

    @Test("BUG-numbers: continuous + unique in KNOWN_ISSUES.md (top-level entries)")
    func knownIssuesIntegrity() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let ki = Self.read("docs/QUALITY/KNOWN_ISSUES.md") ?? ""
        #expect(!ki.isEmpty, "KNOWN_ISSUES.md unreadable")
        // Top-level entries only — `### BUG-007.4` sub-entries are the BUG-007 convention.
        let nums = Self.matches(#"^### BUG-(\d+)(?![.\d])"#, ki).compactMap(Int.init)
        var counts: [Int: Int] = [:]
        for n in nums { counts[n, default: 0] += 1 }
        let maxN = counts.keys.max() ?? 0
        #expect(maxN >= 46, "BUG inventory imploded (max BUG-\(maxN))")
        // BUG-10 was never filed (pre-existing, verified at DOC.4.1 against full git history).
        let allowedHoles: Set<Int> = [10]
        let holes = (1...maxN).filter { counts[$0] == nil && !allowedHoles.contains($0) }
        #expect(holes.isEmpty, "BUG-number hole(s) \(holes.map { "BUG-\(String(format: "%03d", $0))" }): an entry was deleted from KNOWN_ISSUES.md. Resolved entries move to the Resolved section, never out of the file.")
        let dupes = counts.filter { $0.value > 1 }.keys.sorted()
        #expect(dupes.isEmpty, "Duplicate top-level BUG entr\(dupes.count == 1 ? "y" : "ies"): \(dupes.map { "BUG-\(String(format: "%03d", $0))" }) — parallel-session number collision landed twice (the BUG-042/045 renumbering protocol exists for this).")
    }

    @Test("Failed-Approach citations resolve to an active CLAUDE.md entry or the gap table")
    func failedApproachIntegrity() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let claude = Self.read("CLAUDE.md") ?? ""
        let active = Set(Self.matches(#"^(\d+)\. \*\*"#, claude).compactMap(Int.init))
        // Gap-table rows: `| #14, #20 | destination |`
        var gapped = Set<Int>()
        for row in Self.matches(#"^\| (#[^|]+) \|"#, claude) {
            gapped.formUnion(Self.matches(#"#(\d+)"#, row, options: []).compactMap(Int.init))
        }
        #expect(active.count >= 40 && !gapped.isEmpty, "Failed-Approach inventory imploded (\(active.count) active, \(gapped.count) gapped)")
        let cited = Set(Self.matches(#"(?:Failed Approach|FA) #(\d+)"#, Self.citationCorpus(), options: []).compactMap(Int.init))
        let unresolved = cited.subtracting(active).subtracting(gapped).sorted()
        #expect(unresolved.isEmpty, "Failed Approach citation(s) #\(unresolved) resolve to neither an active CLAUDE.md entry nor a gap-table row — extend the gap table when relocating entries (the DOC.3/DOC.4 convention).")
    }
}
