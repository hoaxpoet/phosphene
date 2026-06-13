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

    @Test("BUG-numbers: continuous + unique across KNOWN_ISSUES.md + KNOWN_ISSUES_HISTORY.md (top-level entries)")
    func knownIssuesIntegrity() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let ki = Self.read("docs/QUALITY/KNOWN_ISSUES.md") ?? ""
        #expect(!ki.isEmpty, "KNOWN_ISSUES.md unreadable")
        // Resolved entries older than 14 days rotate to KNOWN_ISSUES_HISTORY.md
        // (Scripts/rotate_docs.sh, DOC.6) — continuity spans both files,
        // mirroring the DECISIONS + DECISIONS_HISTORY convention above.
        let hist = Self.read("docs/QUALITY/KNOWN_ISSUES_HISTORY.md") ?? ""
        // Top-level entries only — `### BUG-007.4` sub-entries are the BUG-007 convention.
        let nums = Self.matches(#"^### BUG-(\d+)(?![.\d])"#, ki + "\n" + hist).compactMap(Int.init)
        var counts: [Int: Int] = [:]
        for n in nums { counts[n, default: 0] += 1 }
        let maxN = counts.keys.max() ?? 0
        #expect(maxN >= 46, "BUG inventory imploded (max BUG-\(maxN))")
        // BUG-10 was never filed (pre-existing, verified at DOC.4.1 against full git history).
        let allowedHoles: Set<Int> = [10]
        let holes = (1...maxN).filter { counts[$0] == nil && !allowedHoles.contains($0) }
        #expect(holes.isEmpty, "BUG-number hole(s) \(holes.map { "BUG-\(String(format: "%03d", $0))" }): an entry was deleted. Resolved entries move to §Resolved, then to KNOWN_ISSUES_HISTORY.md via Scripts/rotate_docs.sh — never out of both files.")
        let dupes = counts.filter { $0.value > 1 }.keys.sorted()
        #expect(dupes.isEmpty, "Duplicate top-level BUG entr\(dupes.count == 1 ? "y" : "ies"): \(dupes.map { "BUG-\(String(format: "%03d", $0))" }) — parallel-session number collision landed twice, or a rotation left the entry in both KNOWN_ISSUES.md and KNOWN_ISSUES_HISTORY.md (a move must DELETE the source copy).")
    }

    @Test("CLAUDE.md stays within the always-loaded token budget (D-161: ≤ 7,000 est. tokens)")
    func claudeMdTokenBudget() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let claude = Self.read("CLAUDE.md") ?? ""
        #expect(!claude.isEmpty, "CLAUDE.md unreadable")
        let words = claude.split(whereSeparator: { $0.isWhitespace }).count
        let estTokens = Int(Double(words) * 1.35)
        #expect(estTokens <= 7000, "CLAUDE.md ≈ \(estTokens) est. tokens (\(words) words) — over the 7,000-token cap (D-161). One-in-one-out: demote or retire equal mass in the same commit (handbooks, PRESET_SESSION_CHECKLIST.md, HISTORICAL_DEAD_ENDS.md, DECISIONS_HISTORY.md).")
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
        // Floor lowered 40 → 7 at RB.2 (2026-06-11): Matt's per-entry review removed 43 of
        // 49 active FAs (kept: #27, #31, #64, #65, #67, #73; #4 retired into §Audio Data
        // Hierarchy at RB.2-2 — see docs/diagnostics/RB1_FA_DN_EXPLANATIONS.md and
        // HISTORICAL_DEAD_ENDS §RB.2). The regex also matches other numbered-bold lists in
        // CLAUDE.md (protocol steps), so the count stays comfortably above the floor; the
        // floor guards wholesale loss of the kept set.
        #expect(active.count >= 7 && !gapped.isEmpty, "Failed-Approach inventory imploded (\(active.count) active, \(gapped.count) gapped)")
        let cited = Set(Self.matches(#"(?:Failed Approach|FA) #(\d+)"#, Self.citationCorpus(), options: []).compactMap(Int.init))
        let unresolved = cited.subtracting(active).subtracting(gapped).sorted()
        #expect(unresolved.isEmpty, "Failed Approach citation(s) #\(unresolved) resolve to neither an active CLAUDE.md entry nor a gap-table row — extend the gap table when relocating entries (the DOC.3/DOC.4 convention).")
    }

    // MARK: - DOC.6 rotation / budget / index gates
    //
    // The pruning-pass prose convention failed twice (measured 2026-06-12: EP narratives
    // four weeks past the RB.3 window; KNOWN_ISSUES 71 % resolved-history; release notes
    // unrotated at 696 KB). Per the D-161 ratchet rule 3 it converts to mechanism:
    // Scripts/rotate_docs.sh performs the moves; these gates make skipping it red.

    /// Cutoff used by the rotation gates — entries resolved more than 14 days ago
    /// belong in the history files (Scripts/rotate_docs.sh moves them).
    private static var rotationCutoff: Date { Date(timeIntervalSinceNow: -14 * 86_400) }

    /// The LAST `YYYY-MM-DD` occurrence in a header line (ranges use the end date) —
    /// the same rule Scripts/rotate_docs.sh applies.
    private static func lastISODate(in line: String) -> Date? {
        let dates = matches(#"\d{4}-\d{2}-\d{2}"#, line, options: [])
        guard let last = dates.last else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        return df.date(from: last)
    }

    /// Lines of the section starting at the exact `header` line, up to (exclusive) the
    /// next top-level `## ` line. Nil when the header is absent.
    private static func sectionLines(of text: String, header: String) -> [String]? {
        var inSection = false
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line == header { inSection = true; continue }
            if inSection && line.hasPrefix("## ") { break }
            if inSection { out.append(line) }
        }
        return inSection ? out : nil
    }

    @Test("EP §Recently Completed: entries older than 14 days are header-only (DOC.6 rotation gate)")
    func engineeringPlanRotationGate() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let ep = Self.read("docs/ENGINEERING_PLAN.md") ?? ""
        let section = try #require(Self.sectionLines(of: ep, header: "## Recently Completed"),
                                    "ENGINEERING_PLAN.md has no §Recently Completed")
        var violations: [String] = []
        var header: String?
        var bodyLines = 0
        func closeEntry() {
            if let h = header, let d = Self.lastISODate(in: h), d < Self.rotationCutoff, bodyLines > 3 {
                violations.append(h)
            }
            header = nil; bodyLines = 0
        }
        for line in section {
            if line.hasPrefix("### ") { closeEntry(); header = line }
            else if header != nil && !line.trimmingCharacters(in: .whitespaces).isEmpty { bodyLines += 1 }
        }
        closeEntry()
        #expect(violations.isEmpty, "EP §Recently Completed entr\(violations.count == 1 ? "y" : "ies") older than 14 days still carr\(violations.count == 1 ? "ies" : "y") a body: \(violations) — run Scripts/rotate_docs.sh (bodies move to ENGINEERING_PLAN_HISTORY.md; headers stay).")
    }

    @Test("KNOWN_ISSUES §Resolved (recent) stays within its 50 KB budget (DOC.6)")
    func knownIssuesResolvedBudget() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let ki = Self.read("docs/QUALITY/KNOWN_ISSUES.md") ?? ""
        let section = try #require(Self.sectionLines(of: ki, header: "## Resolved (recent)"),
                                    "KNOWN_ISSUES.md has no §Resolved (recent)")
        let bytes = section.joined(separator: "\n").utf8.count
        #expect(bytes <= 50 * 1024, "KNOWN_ISSUES §Resolved (recent) is \(bytes / 1024) KB (budget 50 KB) — run Scripts/rotate_docs.sh (resolved entries older than 14 days move to KNOWN_ISSUES_HISTORY.md).")
    }

    @Test("RELEASE_NOTES_DEV: pre-current-month content stays within its 50 KB budget (DOC.6)")
    func releaseNotesRotationBudget() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let rn = Self.read("docs/RELEASE_NOTES_DEV.md") ?? ""
        #expect(!rn.isEmpty, "RELEASE_NOTES_DEV.md unreadable")
        // The budget is on ROTATION DEBT (entries from months before the current one),
        // not the whole file: the current month legitimately lives in the active file
        // and alone measured 72 KB on 2026-06-12 — a raw whole-file cap cannot coexist
        // with the monthly rotation. 50 KB of stale-month content ≈ a rotation skipped
        // for a couple of weeks past a month boundary.
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        let currentMonth = df.string(from: Date())
        var staleBytes = 0
        var inStale = false
        for line in rn.components(separatedBy: "\n") {
            if line.hasPrefix("## [dev-") {
                let month = String(line.dropFirst("## [dev-".count).prefix(7))
                inStale = month < currentMonth
            }
            if inStale { staleBytes += line.utf8.count + 1 }
        }
        #expect(staleBytes <= 50 * 1024, "RELEASE_NOTES_DEV.md carries \(staleBytes / 1024) KB of entries from before \(currentMonth) (budget 50 KB) — run Scripts/rotate_docs.sh (whole months move to RELEASE_NOTES_DEV_YYYY-MM.md files).")
    }

    @Test("DECISIONS §Index is complete: every ## D- header has a row and vice versa (DOC.6)")
    func decisionsIndexCompleteness() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let dec = Self.read("docs/DECISIONS.md") ?? ""
        #expect(!dec.isEmpty, "DECISIONS.md unreadable")
        let headers = Set(Self.matches(#"^## (D-[A-Za-z0-9-]+)"#, dec))
        let rows = Set(Self.matches(#"^\| (D-[A-Za-z0-9-]+) \|"#, dec)).subtracting(["D-###"])
        #expect(!headers.isEmpty && !rows.isEmpty, "DECISIONS.md header/index inventory empty — §Index missing?")
        let missingRows = headers.subtracting(rows).sorted()
        let staleRows = rows.subtracting(headers).sorted()
        #expect(missingRows.isEmpty, "DECISIONS entr\(missingRows.count == 1 ? "y" : "ies") \(missingRows) ha\(missingRows.count == 1 ? "s" : "ve") no §Index row — update the index table.")
        #expect(staleRows.isEmpty, "DECISIONS §Index row(s) \(staleRows) have no matching entry — update the index table (rotated entries lose their row; the entry itself lives in DECISIONS_HISTORY.md).")
    }

    @Test("KNOWN_ISSUES §Open Index is complete: every open entry has a row and vice versa (DOC.6)")
    func knownIssuesOpenIndexCompleteness() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let ki = Self.read("docs/QUALITY/KNOWN_ISSUES.md") ?? ""
        let openSection = try #require(Self.sectionLines(of: ki, header: "## Open"),
                                        "KNOWN_ISSUES.md has no §Open")
        // Top-level open entries carry an ALL-CAPS ID prefix (BUG-NNN, AUDIT-…);
        // narrative sub-headers (### Expected behavior, …) do not match.
        let openText = openSection.joined(separator: "\n")
        let entries = Set(Self.matches(#"^### ([A-Z]{2,}-[^\s]+)"#, openText))
        let rows = Set(Self.matches(#"^\| ([A-Z]{2,}-[^\s]+) \|"#, ki)).subtracting(["ID"])
        #expect(!entries.isEmpty && !rows.isEmpty, "KNOWN_ISSUES open-entry/index inventory empty — §Open Index missing?")
        let missingRows = entries.subtracting(rows).sorted()
        let staleRows = rows.subtracting(entries).sorted()
        #expect(missingRows.isEmpty, "Open entr\(missingRows.count == 1 ? "y" : "ies") \(missingRows) ha\(missingRows.count == 1 ? "s" : "ve") no §Open Index row — update the index table.")
        #expect(staleRows.isEmpty, "§Open Index row(s) \(staleRows) have no matching open entry — update the index table (resolved entries lose their row when they move to §Resolved).")
    }
}
