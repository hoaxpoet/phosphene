// Report.swift — Markdown report for QualityReelAnalyzer.
//
// Split out of main.swift to satisfy file_length lint.

import Foundation
import DSP

struct ReportContext {
    let outPath: String
    let reelPath: String
    let durationSec: Double
    let grid: BeatGrid
    let beatLumas: [Double]
    let midLumas: [Double]
    let framesDir: String
    let audioOnly: Bool
}

enum ReportWriter {

    static func write(context: ReportContext) throws {
        let outURL = URL(fileURLWithPath: context.outPath)
        try FileManager.default.createDirectory(
            at: outURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var lines: [String] = []
        lines.append(contentsOf: header(context: context))
        lines.append(contentsOf: gridSection(grid: context.grid))
        if context.audioOnly {
            lines.append("> `--audio-only` set — no frame sampling performed.")
            lines.append("")
        } else if context.beatLumas.isEmpty || context.midLumas.isEmpty {
            lines.append("> No beat / midpoint frames sampled (empty grid or extraction failed).")
            lines.append("")
        } else {
            lines.append(contentsOf: reactivitySection(context: context))
        }
        try lines.joined(separator: "\n")
            .write(toFile: context.outPath, atomically: true, encoding: .utf8)
    }

    private static func header(context: ReportContext) -> [String] {
        let durStr = String(format: "%.1f", context.durationSec)
        let nowStr = ISO8601DateFormatter().string(from: Date())
        return [
            "# Quality Reel Analysis",
            "",
            "- **Reel:** `\(context.reelPath)`",
            "- **Duration:** \(durStr)s",
            "- **Generated:** \(nowStr)",
            ""
        ]
    }

    private static func gridSection(grid: BeatGrid) -> [String] {
        let bpm = String(format: "%.2f", grid.bpm)
        let conf = String(format: "%.3f", grid.barConfidence)
        return [
            "## Beat Grid (Beat This!)",
            "",
            "- **BPM:** \(bpm)",
            "- **Beats:** \(grid.beats.count)",
            "- **Downbeats:** \(grid.downbeats.count)",
            "- **Beats per bar:** \(grid.beatsPerBar)",
            "- **Bar confidence:** \(conf)",
            ""
        ]
    }

    private static func reactivitySection(context: ReportContext) -> [String] {
        let beatStats = Stats.from(context.beatLumas)
        let midStats = Stats.from(context.midLumas)
        let beatDeltas = Stats.consecutiveDeltas(context.beatLumas)
        let midDeltas = Stats.consecutiveDeltas(context.midLumas)
        let beatDeltaStats = Stats.from(beatDeltas)
        let midDeltaStats = Stats.from(midDeltas)
        let ratio = (midDeltaStats.mean > 1e-6)
            ? beatDeltaStats.mean / midDeltaStats.mean : 0
        let ratioStr = String(format: "%.2f", ratio)
        return reactivityLines(
            context: context,
            beatStats: beatStats,
            midStats: midStats,
            beatDeltas: beatDeltas,
            midDeltas: midDeltas,
            beatDeltaStats: beatDeltaStats,
            midDeltaStats: midDeltaStats,
            ratioStr: ratioStr
        )
    }

    // swiftlint:disable function_parameter_count
    private static func reactivityLines(
        context: ReportContext,
        beatStats: Stats, midStats: Stats,
        beatDeltas: [Double], midDeltas: [Double],
        beatDeltaStats: Stats, midDeltaStats: Stats,
        ratioStr: String
    ) -> [String] {
        var lines: [String] = []
        lines.append("## Visual Reactivity")
        lines.append("")
        lines.append(
            "Per-frame mean luma sampled at beat timestamps and at midpoints "
            + "between beats. Luma in [0, 1]."
        )
        lines.append("")
        lines.append("| Sample          | Count |   Mean | Std Dev |  Min  |  Max  |")
        lines.append("| --------------- | ----: | -----: | ------: | ----: | ----: |")
        lines.append(formatRow(
            label: "Beat frames", count: context.beatLumas.count, stats: beatStats
        ))
        lines.append(formatRow(
            label: "Midpoint frames", count: context.midLumas.count, stats: midStats
        ))
        lines.append("")
        lines.append("### Frame-to-frame luma delta (|Δ luma|)")
        lines.append("")
        lines.append("| Series              | Count |   Mean | Std Dev |  Max  |")
        lines.append("| ------------------- | ----: | -----: | ------: | ----: |")
        lines.append(formatDeltaRow(
            label: "Beat → next beat", count: beatDeltas.count, stats: beatDeltaStats
        ))
        lines.append(formatDeltaRow(
            label: "Midpoint → next midpoint", count: midDeltas.count, stats: midDeltaStats
        ))
        lines.append("")
        lines.append("- **Beat-reactivity ratio:** \(ratioStr)×")
        lines.append("  - >> 1 → visuals respond to beats more than to mid-beat noise.")
        lines.append("  - ≈ 1 → visuals are equally active across beat and mid-beat positions.")
        lines.append("  - < 1 → visuals are anti-correlated with beats (rare; phase issue).")
        lines.append("")
        lines.append("## Frame Samples")
        lines.append("")
        lines.append("Frames written to `\(context.framesDir)`:")
        lines.append("- `beat_NNNN_tXXXX.png` — sampled at beat N (`grid.beats[N]`)")
        lines.append("- `mid_NNNN_tXXXX.png`  — sampled halfway to beat N+1")
        lines.append("")
        lines.append(
            "Inspect a handful manually to confirm ffmpeg's keyframe-seek "
            + "didn't snap timestamps to the wrong frame."
        )
        return lines
    }
    // swiftlint:enable function_parameter_count

    private static func formatRow(label: String, count: Int, stats: Stats) -> String {
        let padded = label.padding(toLength: 15, withPad: " ", startingAt: 0)
        let countStr = String(format: "%5d", count)
        let meanStr = String(format: "%.4f", stats.mean)
        let stdStr = String(format: "%.4f", stats.stddev)
        let lowStr = String(format: "%.3f", stats.min)
        let hiStr = String(format: "%.3f", stats.max)
        return "| \(padded) | \(countStr) | \(meanStr) | \(stdStr)  | \(lowStr) | \(hiStr) |"
    }

    private static func formatDeltaRow(label: String, count: Int, stats: Stats) -> String {
        let padded = label.padding(toLength: 19, withPad: " ", startingAt: 0)
        let countStr = String(format: "%5d", count)
        let meanStr = String(format: "%.4f", stats.mean)
        let stdStr = String(format: "%.4f", stats.stddev)
        let hiStr = String(format: "%.3f", stats.max)
        return "| \(padded) | \(countStr) | \(meanStr) | \(stdStr)  | \(hiStr) |"
    }
}

struct Stats {
    let mean: Double
    let stddev: Double
    let min: Double
    let max: Double

    static func from(_ values: [Double]) -> Stats {
        guard !values.isEmpty else { return Stats(mean: 0, stddev: 0, min: 0, max: 0) }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { acc, val in
            acc + (val - mean) * (val - mean)
        } / Double(values.count)
        return Stats(
            mean: mean,
            stddev: variance.squareRoot(),
            min: values.min() ?? 0,
            max: values.max() ?? 0
        )
    }
}

extension Stats {
    static func consecutiveDeltas(_ values: [Double]) -> [Double] {
        guard values.count > 1 else { return [] }
        var deltas: [Double] = []
        deltas.reserveCapacity(values.count - 1)
        for idx in 1..<values.count {
            deltas.append(abs(values[idx] - values[idx - 1]))
        }
        return deltas
    }
}
