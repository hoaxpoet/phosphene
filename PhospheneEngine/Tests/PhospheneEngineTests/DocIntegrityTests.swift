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
        // At DOC.9 the last six always-loaded FAs (#27/#31/#67 → preset-session,
        // #64/#65/#73 → shader-authoring) moved to .claude/skills, so `active` (numbered-bold
        // entries in CLAUDE.md) may now be EMPTY — the full text is gated in the skill bodies
        // by skillIntegrity(). The invariant here is resolution, not a live-entry floor: the
        // gap table must be non-empty and the six relocated numbers must resolve via it.
        let relocated: Set<Int> = [27, 31, 64, 65, 67, 73]
        let resolvableHere = active.union(gapped)
        #expect(!gapped.isEmpty, "Failed-Approach gap table imploded (\(gapped.count) gapped) — wholesale loss?")
        let lostRelocated = relocated.subtracting(resolvableHere).sorted()
        #expect(lostRelocated.isEmpty, "Relocated FA(s) #\(lostRelocated) resolve to neither an active CLAUDE.md entry nor a gap-table row — they live in .claude/skills as of DOC.9 and must keep a gap-table row.")
        let cited = Set(Self.matches(#"(?:Failed Approach|FA) #(\d+)"#, Self.citationCorpus(), options: []).compactMap(Int.init))
        let unresolved = cited.subtracting(resolvableHere).sorted()
        #expect(unresolved.isEmpty, "Failed Approach citation(s) #\(unresolved) resolve to neither an active CLAUDE.md entry nor a gap-table row — extend the gap table when relocating entries (the DOC.3/DOC.4 convention).")
    }

    // MARK: - DOC.6 rotation / budget / index gates
    //
    // The pruning-pass prose convention failed twice (measured 2026-06-12: EP narratives
    // four weeks past the RB.3 window; KNOWN_ISSUES 71 % resolved-history; release notes
    // unrotated at 696 KB). Per the D-161 ratchet rule 3 it converts to mechanism:
    // Scripts/rotate_docs.sh performs the moves; these gates make skipping it red.

    /// Cutoff date (`YYYY-MM-DD`) for the rotation gate — entries dated strictly
    /// BEFORE this string belong in the history files. Computed as today − 14 days
    /// in the LOCAL calendar and compared as a STRING, byte-for-byte matching
    /// `Scripts/rotate_docs.sh` (`date -v-14d +%Y-%m-%d` then awk string `<`).
    /// Comparing dates-as-strings (not `Date` objects) is what keeps the gate and
    /// the tool agreeing on the exact boundary day: a datetime cutoff flagged
    /// day-14 entries that the date-only script refused to move (the CLEAN.2.3.5
    /// closeout red-gate class).
    private static var rotationCutoffString: String {
        let calendar = Calendar(identifier: .gregorian)   // local TZ, matches `date`
        let cutoff = calendar.date(byAdding: .day, value: -14, to: Date())
            ?? Date(timeIntervalSinceNow: -14 * 86_400)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.string(from: cutoff)
    }

    /// The LAST `YYYY-MM-DD` string in a header line (ranges use the end date) —
    /// the same rule `Scripts/rotate_docs.sh` applies. Returned as a string so the
    /// comparison against `rotationCutoffString` is chronological-via-lexicographic.
    private static func lastISODateString(in line: String) -> String? {
        matches(#"\d{4}-\d{2}-\d{2}"#, line, options: []).last
    }

    /// True when an EP §Recently Completed entry should already be header-only in
    /// the plan (its body rotated to history). Selection mirrors `rotate_docs.sh`
    /// exactly — ✅/⏳-marked, dated strictly before `cutoff`, still carrying a body —
    /// so the gate flags only entries the tool will actually move. Extracted from the
    /// gate loop so the boundary/marker logic is unit-testable (it was a red-gate
    /// source: CLEAN.2.3.5 closeout).
    static func epEntryNeedsRotation(header: String, bodyLines: Int, cutoff: String) -> Bool {
        guard header.contains("✅") || header.contains("⏳") else { return false }
        guard let dated = lastISODateString(in: header), dated < cutoff else { return false }
        return bodyLines > 0   // mirrors rotate_docs.sh (`bodylines > 0`); >3 under-reported 1–3-line bodies the script rotates
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
        let cutoff = Self.rotationCutoffString
        func closeEntry() {
            if let h = header, Self.epEntryNeedsRotation(header: h, bodyLines: bodyLines, cutoff: cutoff) {
                violations.append(h)
            }
            header = nil; bodyLines = 0
        }
        for line in section {
            if line.hasPrefix("### ") { closeEntry(); header = line }
            else if header != nil && !line.trimmingCharacters(in: .whitespaces).isEmpty { bodyLines += 1 }
        }
        closeEntry()
        #expect(violations.isEmpty, "EP §Recently Completed ✅/⏳ entr\(violations.count == 1 ? "y" : "ies") older than 14 days still carr\(violations.count == 1 ? "ies" : "y") a body: \(violations) — run Scripts/rotate_docs.sh (bodies move to ENGINEERING_PLAN_HISTORY.md; headers stay).")
    }

    @Test("EP rotation predicate matches rotate_docs selection — boundary + ✅/⏳ marker (DOC.6)")
    func engineeringPlanRotationPredicate() {
        // Deterministic (fixed cutoff, no wall-clock). Guards the gate against
        // silently going green and re-pins the two CLEAN.2.3.5 boundary bugs.
        let cutoff = "2026-06-01"
        // old + ✅ + body → must rotate (flagged)
        #expect(Self.epEntryNeedsRotation(header: "### Foo ✅ (2026-05-01)", bodyLines: 10, cutoff: cutoff))
        // ⏳ marker also counts
        #expect(Self.epEntryNeedsRotation(header: "### Bar ⏳ (2026-05-01)", bodyLines: 10, cutoff: cutoff))
        // BOUNDARY: dated exactly == cutoff → NOT flagged (string `<` is false), matching
        // the date-only script — this is the day-14 false-positive the old datetime cutoff hit.
        #expect(!Self.epEntryNeedsRotation(header: "### Foo ✅ (2026-06-01)", bodyLines: 10, cutoff: cutoff))
        // recent → not flagged
        #expect(!Self.epEntryNeedsRotation(header: "### Foo ✅ (2026-06-10)", bodyLines: 10, cutoff: cutoff))
        // old but UNMARKED → not flagged (rotate_docs leaves it for manual triage)
        #expect(!Self.epEntryNeedsRotation(header: "### Foo (2026-05-01)", bodyLines: 10, cutoff: cutoff))
        // old + ✅ but already header-only (no body) → not flagged
        #expect(!Self.epEntryNeedsRotation(header: "### Foo ✅ (2026-05-01)", bodyLines: 0, cutoff: cutoff))
        // old + ✅ + a SINGLE body line → flagged (mirrors rotate_docs `bodylines > 0`; the >3 under-report bug)
        #expect(Self.epEntryNeedsRotation(header: "### Foo ✅ (2026-05-01)", bodyLines: 1, cutoff: cutoff))
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

    // MARK: - Module Map completeness gate (CLEAN.7.3 / D-168)
    //
    // The ARCHITECTURE Module Map claims to be a per-file behavioural reference for
    // every source file. With no enforcement it drifted: the 2026-06-13 audit found 18
    // undocumented files; by 2026-06-18 it was 62 — including four entire CERTIFIED
    // presets (Skein, Murmuration, Dragon Bloom, Fata Morgana) and recent infra
    // (FlashAnalyzer, DefaultOutputDeviceMonitor). An incomplete "read this before
    // grep-ing" index is worse than none. Per the D-161 ratchet rule 3 (violated twice
    // → mechanize) this converts to a gate.

    /// Every `.swift` / `.metal` under PhospheneEngine/Sources + PhospheneApp must be
    /// findable in the Module Map by its filename-minus-extension (a substring match).
    /// Diagnostic/tooling modules and utility trees are documented as ONE group entry
    /// that names its files, so a stem match — not a per-file entry line — is the
    /// contract.
    ///
    /// ponytail: substring membership, not entry-line parsing. A short common stem
    /// ("main", "Audio") can match spuriously, so the gate is permissive — it never
    /// false-reds an unrelated increment (the BUG-049 class). Its job is catching a
    /// whole file/subsystem added with NO mention (the FlashAnalyzer / Skein-cluster
    /// class), which it does. Tighten to entry-line parsing only if spurious passes bite.
    @Test("ARCHITECTURE Module Map documents every Swift/Metal source file (CLEAN.7.3 / D-168)")
    func moduleMapCompleteness() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let arch = Self.read("docs/ARCHITECTURE.md") ?? ""
        #expect(!arch.isEmpty, "ARCHITECTURE.md unreadable")
        let mapText = try #require(Self.sectionLines(of: arch, header: "## Module Map"),
                                   "ARCHITECTURE.md has no ## Module Map section").joined(separator: "\n")
        let fm = FileManager.default
        var undocumented: [String] = []
        for root in ["PhospheneEngine/Sources", "PhospheneApp"] {
            let base = Self.repoRoot.appendingPathComponent(root)
            guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker {
                guard ["swift", "metal"].contains(url.pathExtension) else { continue }
                let stem = url.deletingPathExtension().lastPathComponent
                if !mapText.contains(stem) { undocumented.append(url.lastPathComponent) }
            }
        }
        undocumented.sort()
        let shown = undocumented.prefix(25).joined(separator: ", ")
        #expect(undocumented.isEmpty, "ARCHITECTURE Module Map omits \(undocumented.count) source file(s) under PhospheneEngine/Sources or PhospheneApp/: \(shown). Add a one-line entry under ## Module Map (or name the file in its module's group entry) — per-file completeness is the map's contract (CLEAN.7.3 / D-168).")
    }

    // MARK: - Skill-integrity gate (DOC.9 / D-179)
    //
    // DOC.9 moved the increment-type-scoped protocols (closeout, defect-handling, doc-pruning)
    // plus the preset audio-data-hierarchy and reference-porting rules out of always-loaded
    // CLAUDE.md into .claude/skills/*/SKILL.md (progressive disclosure). A skill that silently
    // loses a doc pointer or a D-/FA citation is the same drift class the earlier gates catch,
    // so the same referential-integrity contract applies to the skills.

    private static let expectedSkills = ["closeout", "defect-handling", "doc-pruning", "preset-session", "shader-authoring"]

    @Test("Skills: present, well-formed frontmatter, and every doc/D-/FA citation resolves (DOC.9)")
    func skillIntegrity() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let fm = FileManager.default
        let skillsDir = Self.repoRoot.appendingPathComponent(".claude/skills")

        // (a) each expected skill dir has a SKILL.md; (b) frontmatter name matches the dir and
        // description is present and ≤ 500 chars.
        var bodies: [String: String] = [:]
        for name in Self.expectedSkills {
            let path = skillsDir.appendingPathComponent("\(name)/SKILL.md")
            guard let text = try? String(contentsOf: path, encoding: .utf8) else {
                Issue.record("Skill '\(name)' has no SKILL.md at .claude/skills/\(name)/SKILL.md")
                continue
            }
            bodies[name] = text
            let fmName = Self.matches(#"^name:\s*(.+?)\s*$"#, text).first
            let fmDesc = Self.matches(#"^description:\s*(.+?)\s*$"#, text).first
            #expect(fmName == name, "Skill '\(name)' frontmatter name is \(fmName.map { "'\($0)'" } ?? "missing") — must equal the directory name.")
            #expect((fmDesc?.isEmpty == false) && (fmDesc?.count ?? .max) <= 500, "Skill '\(name)' frontmatter description is missing, empty, or > 500 chars.")
        }

        // (c) every docs/… path token in a skill body resolves (placeholders containing '<' skipped).
        var missingPaths: [String] = []
        for (name, text) in bodies {
            for token in Self.matches(#"docs/[\w./-]+"#, text, options: []) {
                if token.contains("<") { continue }
                let clean = token.hasSuffix(".") ? String(token.dropLast()) : token
                if !fm.fileExists(atPath: Self.repoRoot.appendingPathComponent(clean).path) {
                    missingPaths.append("\(name): \(clean)")
                }
            }
        }
        #expect(missingPaths.isEmpty, "Skill doc pointer(s) do not resolve: \(missingPaths.sorted()) — fix the path or the skill body.")

        // (d) D-NNN and FA #N citations in skill bodies resolve (same resolvers as the gates above).
        let dec = (Self.read("docs/DECISIONS.md") ?? "") + "\n" + (Self.read("docs/DECISIONS_HISTORY.md") ?? "")
        let definedD = Set(Self.matches(#"^## D-(\d{3})"#, dec).compactMap(Int.init))
        let claude = Self.read("CLAUDE.md") ?? ""
        var faResolvable = Set(Self.matches(#"^(\d+)\. \*\*"#, claude).compactMap(Int.init))
        for row in Self.matches(#"^\| (#[^|]+) \|"#, claude) {
            faResolvable.formUnion(Self.matches(#"#(\d+)"#, row, options: []).compactMap(Int.init))
        }
        let skillText = bodies.values.joined(separator: "\n")
        let citedD = Set(Self.matches(#"D-(\d{3})(?![\d.\w])"#, skillText, options: []).compactMap(Int.init))
        let unresolvedD = citedD.subtracting(definedD).sorted()
        #expect(unresolvedD.isEmpty, "Skill-body decision citation(s) \(unresolvedD.map { "D-\(String(format: "%03d", $0))" }) resolve to no DECISIONS header.")
        let citedFA = Set(Self.matches(#"(?:Failed Approach|FA) #(\d+)"#, skillText, options: []).compactMap(Int.init))
        let unresolvedFA = citedFA.subtracting(faResolvable).sorted()
        #expect(unresolvedFA.isEmpty, "Skill-body Failed-Approach citation(s) #\(unresolvedFA) resolve to neither a CLAUDE.md entry nor a gap-table row.")

        // (e) CLAUDE.md `.claude/skills/<name>` pointers reference only existing skills.
        let pointered = Set(Self.matches(#"\.claude/skills/([\w-]+)"#, claude, options: []))
        let unknown = pointered.subtracting(Set(Self.expectedSkills)).sorted()
        #expect(unknown.isEmpty, "CLAUDE.md points to non-existent skill(s): \(unknown) — pointers reference only .claude/skills/{\(Self.expectedSkills.joined(separator: ","))}.")
    }
}
