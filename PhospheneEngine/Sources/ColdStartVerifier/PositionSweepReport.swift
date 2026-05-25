// PositionSweepReport — Markdown writer for BSAudit.2 Path A.1.
//
// Separated from `PositionSweep` to keep both files under SwiftLint's
// file-length and type-body-length caps.

import Foundation

extension PositionSweep {

    static func report(
        session: URL,
        rawTap: RawTapAnalysis,
        results: [TrackResult],
        config: Config
    ) -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let durStr = String(format: "%.1f", rawTap.durationS)
        let resStr = String(format: "%.2f", viableResultant)
        let positions = derivedPositionsForHeader(results: results)
        let posHeader = positions
            .map { "+\(String(format: "%.0f", $0))s" }
            .joined(separator: " | ")
        let posDivider = positions.map { _ in "---" }.joined(separator: "|")
        var md = """
        # BSAudit.2 (Path A.1) — Within-capture Beat This! position sensitivity

        - **Generated:** \(stamp)
        - **Session:** `\(session.lastPathComponent)`
        - **raw_tap.wav:** \(durStr) s @ \(Int(rawTap.sampleRate)) Hz
        - **Slice length:** \(String(format: "%.0f", config.sliceDurationS)) s; \
        **stride:** \(String(format: "%.0f", config.positionStrideS)) s

        ## Question

        Within a single capture, is Beat This! on a \
        \(String(format: "%.0f", config.sliceDurationS)) s slice position-sensitive? \
        For each track, Beat This! is run at multiple sliding offsets from track start; \
        each non-zero position's phase is compared to the position-0 reference via \
        circular-mean residual. A position is **viable** when its phase is within \
        ±\(Int(viablePhaseErrorMs)) ms with resultant ≥ \(resStr). Spread > \
        \(Int(unstableSpreadMs)) ms across positions flags the track as \
        position-unstable.

        ## Per-track per-position phase error (vs position-0)

        | Track | ref beats | ref BPM | \(posHeader) | spread |
        |---|---|---|\(posDivider)|---|

        """
        for result in results {
            md += renderRow(result, positions: positions) + "\n"
        }
        md += "\n_Cell: phase offset vs position-0 (signed ms), R, beat count, "
        md += "✓ viable / ✗ not._\n\n"
        md += renderSummary(results: results)
        md += renderShortlist(results)
        return md
    }

    /// Positions actually measured, sourced from the first track that produced
    /// results. Falls back to a default ladder when every track flagged.
    private static func derivedPositionsForHeader(results: [TrackResult]) -> [Double] {
        if let first = results.first(where: { !$0.positions.isEmpty }) {
            return first.positions.map(\.positionS)
        }
        return [0, 10, 20, 30]
    }

    private static func renderRow(
        _ result: TrackResult,
        positions: [Double]
    ) -> String {
        guard !result.positions.isEmpty else {
            let cols = positions.map { _ in "—" }.joined(separator: " | ")
            return "| \(result.label) | — | — | \(cols) | FLAGGED: "
                + "\(result.flagReason ?? "no data") |"
        }
        let bpm = String(format: "%.1f", result.referenceBPM)
        var row = "| \(result.label) | \(result.referenceBeatCount) | \(bpm) |"
        for pos in positions {
            if let entry = result.positions.first(where: { abs($0.positionS - pos) < 0.5 }) {
                row += " \(rowCell(entry)) |"
            } else {
                row += " — |"
            }
        }
        let spread = String(format: "%.0f", result.phaseSpreadMs)
        let flag = result.flagged ? " ⚠" : ""
        row += " \(spread) ms\(flag) |"
        return row
    }

    private static func rowCell(_ position: PositionResult) -> String {
        guard position.hasUsableGrid else {
            return "empty (\(position.beatCount)b) ✗"
        }
        let mark = position.viable ? "✓" : "✗"
        let off = String(format: "%+.0f", position.phaseErrorMs)
        let res = String(format: "%.2f", position.resultant)
        return "\(off) ms (R \(res), \(position.beatCount)b) \(mark)"
    }

    private static func renderSummary(results: [TrackResult]) -> String {
        let rated = results.filter { !$0.positions.isEmpty }.count
        let unstable = results.filter { $0.flagged && !$0.positions.isEmpty }.count
        var md = "## Summary\n\n"
        md += "- **Rated tracks:** \(rated) / \(results.count)\n"
        md += "- **Position-unstable (spread > \(Int(unstableSpreadMs)) ms):** "
        md += "\(unstable) / \(rated)\n"
        let spreads = results.compactMap { $0.positions.isEmpty ? nil : $0.phaseSpreadMs }
        if !spreads.isEmpty {
            let median = ColdStartAnalysis.median(spreads)
            let maxSpread = spreads.max() ?? 0
            md += "- **Median phase spread:** \(String(format: "%.0f", median)) ms\n"
            md += "- **Max phase spread:** \(String(format: "%.0f", maxSpread)) ms\n"
        }
        md += "\n"
        return md
    }

    private static func renderShortlist(_ results: [TrackResult]) -> String {
        let flagged = results.filter { $0.flagged }
        var md = "## Position-unstable tracks (need closer look)\n\n"
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
