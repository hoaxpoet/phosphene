// AccentWindowPassRateReport — Markdown renderer for `--accent-window-pass-rate`.
//
// Mirrors the cold_start_report.md pattern: a header section with the
// run's configuration + aggregate verdict, then a per-track table, then a
// per-track detail block citing the audible-beat count, accent-hit count,
// max accent_confidence, max beatComposite, and verdict reason.

import Foundation

enum AccentWindowReport {

    static func render(
        sessionURL: URL,
        analysis: AccentWindowAnalysisResult,
        config: AccentWindowConfig
    ) -> String {
        var lines: [String] = []
        lines.append(header(sessionURL: sessionURL, config: config))
        lines.append(verdictBanner(analysis: analysis, config: config))
        lines.append("")
        lines.append(perTrackTable(analysis: analysis))
        lines.append("")
        lines.append("## Per-track detail")
        lines.append("")
        for result in analysis.tracks {
            lines.append(perTrackDetail(result: result))
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func header(sessionURL: URL, config: AccentWindowConfig) -> String {
        """
        # ColdStartVerifier — `--accent-window-pass-rate` (BSAudit.3.validate)

        - Session: `\(sessionURL.path)`
        - Window: \(format(config.firstWindowS)) s starting at \
        +\(format(config.windowStartS)) s
        - Acceptance window: ±\(format(config.acceptMs)) ms around each audible beat
        - Accent rising-edge threshold (beatComposite): \(format(config.accentThreshold, "%.2f"))
        - Per-track pass-firing gate: \(percent(config.perTrackPassRate))
        - Graceful-degradation cap (max accent_confidence): \
        \(format(config.degradedConfThreshold, "%.2f"))
        - Aggregate gate (% PASS-firing + PASS-degraded over non-degenerate): \
        \(percent(AccentWindowPassRate.aggregateGate))
        - Audible-beat reference: Beat This! on raw_tap.wav, \
        \(format(AccentWindowPassRate.sliceDurationS)) s slice
        """
    }

    private static func verdictBanner(
        analysis: AccentWindowAnalysisResult,
        config: AccentWindowConfig
    ) -> String {
        let rated = analysis.tracks.count - analysis.degenerateCount
        let okPct = rated > 0
            ? Double(analysis.passFiringCount + analysis.passDegradedCount) / Double(rated)
            : 0
        let summary = String(
            format: "**%@** — %d / %d rated tracks PASS-firing|degraded (%.0f%%)",
            analysis.overallPass ? "PASS" : "FAIL",
            analysis.passFiringCount + analysis.passDegradedCount,
            rated,
            okPct * 100)
        _ = config  // shape-only formatter; aggregate gate is in the header.
        let breakdown = String(
            format: "PASS-firing: %d · PASS-degraded: %d · FAIL: %d · degenerate: %d",
            analysis.passFiringCount,
            analysis.passDegradedCount,
            analysis.failCount,
            analysis.degenerateCount)
        return "\n## Verdict\n\n\(summary)  \n\(breakdown)"
    }

    private static func perTrackTable(analysis: AccentWindowAnalysisResult) -> String {
        var rows: [String] = []
        rows.append("| # | Track | Verdict | audible | hits | pass_rate | max conf | max composite |")
        rows.append("|---|---|---|---:|---:|---:|---:|---:|")
        for (idx, result) in analysis.tracks.enumerated() {
            rows.append(tableRow(index: idx, result: result))
        }
        return rows.joined(separator: "\n")
    }

    private static func tableRow(index: Int, result: AccentWindowTrackResult) -> String {
        let label = mdEscape(result.track.label)
        let verdict = "`\(result.verdict.rawValue)`"
        if result.verdict == .degenerate {
            return "| \(index + 1) | \(label) | \(verdict) | — | — | — | — | — |"
        }
        return String(
            format: "| %d | %@ | %@ | %d | %d | %.0f%% | %.2f | %.2f |",
            index + 1,
            label,
            verdict,
            result.audibleBeats,
            result.accentHits,
            result.passRate * 100,
            result.maxConfidence,
            result.maxComposite)
    }

    private static func perTrackDetail(result: AccentWindowTrackResult) -> String {
        var lines = ["### \(result.track.label)"]
        lines.append("")
        lines.append("- Verdict: `\(result.verdict.rawValue)`")
        if let reason = result.degenerateReason {
            lines.append("- Degenerate reason: \(reason)")
        }
        lines.append(String(
            format: "- Window: %.2f–%.2f s playback-time, BPM %.1f",
            result.firstPt,
            result.windowEnd,
            result.windowGridBPM))
        lines.append(String(
            format: "- Beat This! over slice: %d beat(s)",
            result.beatThisBeatCount))
        lines.append(String(format: "- Clock offset: %.3f s", result.clockOffsetS))
        if result.verdict != .degenerate {
            lines.append(String(
                format: "- Audible beats in window: %d  •  accent hits: %d  •  pass rate: %.1f%%",
                result.audibleBeats,
                result.accentHits,
                result.passRate * 100))
            lines.append(String(
                format: "- Max accent_confidence in window: %.3f  •  Max beatComposite: %.3f",
                result.maxConfidence,
                result.maxComposite))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func format(_ value: Double, _ fmt: String = "%.0f") -> String {
        String(format: fmt, value)
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    /// Markdown-safe escape for pipe characters in track titles (cell delimiters).
    private static func mdEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }
}
