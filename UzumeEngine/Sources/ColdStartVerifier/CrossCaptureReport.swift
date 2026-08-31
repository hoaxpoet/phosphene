// CrossCaptureReport — Markdown writer for BSAudit.2 Path A.2.
//
// Separated from `CrossCapture` so the core module stays under SwiftLint's
// length caps.

import Foundation

extension CrossCapture {

    static func report(
        sessions: [SessionInputs],
        results: [TrackResult],
        config: Config
    ) -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let resStr = String(format: "%.2f", viableResultant)
        let labels = sessions.map(\.label)
        let nonRefLabels = labels.dropFirst()
        let columnHeader = nonRefLabels.joined(separator: " | ")
        let columnDivider = nonRefLabels.map { _ in "---" }.joined(separator: "|")
        var md = """
        # BSAudit.2 (Path A.2) — Cross-capture Beat This! reproducibility

        - **Generated:** \(stamp)
        - **Reference session:** `\(labels.first ?? "—")`
        - **Compared against:** \(nonRefLabels.map { "`\($0)`" }.joined(separator: ", "))
        - **Slice length:** \(String(format: "%.0f", config.sliceDurationS)) s @ +\
        \(String(format: "%.0f", config.positionStartS)) s into each track

        ## Question

        For tracks common to all sessions, Beat This! is run on the same playback-time \
        slice of each session's `raw_tap.wav`. The reference session's beats anchor the \
        comparison; each other session's beats are scored as a circular-mean phase \
        residual against that reference. **A session is "viable" when its phase is \
        within ±\(Int(viablePhaseErrorMs)) ms of the reference with resultant ≥ \
        \(resStr).** Max |Δ| > \(Int(unstableSpreadMs)) ms flags the track as \
        cross-capture-unstable.

        ## Per-track cross-capture phase agreement

        | Track | ref beats | ref BPM | \(columnHeader) | max \\|Δ\\| |
        |---|---|---|\(columnDivider)|---|

        """
        for result in results {
            md += renderRow(result, nonRefLabels: Array(nonRefLabels)) + "\n"
        }
        md += "\n_Cell: phase offset vs reference (signed ms), R, beat count, "
        md += "✓ viable / ✗ not._\n\n"
        md += renderSummary(results)
        md += renderShortlist(results)
        return md
    }

    private static func renderRow(
        _ result: TrackResult,
        nonRefLabels: [String]
    ) -> String {
        guard !result.sessions.isEmpty else {
            let cols = nonRefLabels.map { _ in "—" }.joined(separator: " | ")
            return "| \(result.label) | — | — | \(cols) | FLAGGED: "
                + "\(result.flagReason ?? "no data") |"
        }
        let bpm = String(format: "%.1f", result.referenceBPM)
        var row = "| \(result.label) | \(result.referenceBeatCount) | \(bpm) |"
        for label in nonRefLabels {
            if let entry = result.sessions.first(where: { $0.label == label }) {
                row += " \(rowCell(entry)) |"
            } else {
                row += " — |"
            }
        }
        let spread = String(format: "%.0f", result.maxAbsPhaseErrorMs)
        let flag = result.flagged ? " ⚠" : ""
        row += " \(spread) ms\(flag) |"
        return row
    }

    private static func rowCell(_ session: SessionResult) -> String {
        guard session.hasUsableGrid else {
            return "empty (\(session.beatCount)b) ✗"
        }
        let mark = session.viable ? "✓" : "✗"
        let off = String(format: "%+.0f", session.phaseErrorMs)
        let res = String(format: "%.2f", session.resultant)
        return "\(off) ms (R \(res), \(session.beatCount)b) \(mark)"
    }

    private static func renderSummary(_ results: [TrackResult]) -> String {
        let rated = results.filter { !$0.sessions.isEmpty }.count
        let unstable = results.filter { $0.flagged && !$0.sessions.isEmpty }.count
        var md = "## Summary\n\n"
        md += "- **Rated tracks:** \(rated) / \(results.count)\n"
        md += "- **Cross-capture unstable (max |Δ| > \(Int(unstableSpreadMs)) ms):** "
        md += "\(unstable) / \(rated)\n"
        let maxes = results.compactMap { $0.sessions.isEmpty ? nil : $0.maxAbsPhaseErrorMs }
        if !maxes.isEmpty {
            let median = ColdStartAnalysis.median(maxes)
            let worst = maxes.max() ?? 0
            md += "- **Median max |Δ|:** \(String(format: "%.0f", median)) ms\n"
            md += "- **Worst max |Δ|:** \(String(format: "%.0f", worst)) ms\n"
        }
        md += "\n"
        return md
    }

    private static func renderShortlist(_ results: [TrackResult]) -> String {
        let flagged = results.filter { $0.flagged }
        var md = "## Cross-capture-unstable tracks (need closer look)\n\n"
        if flagged.isEmpty {
            md += "_No tracks flagged by the automated checks._\n\n"
        } else {
            for result in flagged {
                md += "- **\(result.label)** — \(result.flagReason ?? "flagged")\n"
            }
            md += "\n"
        }
        return md
    }
}
