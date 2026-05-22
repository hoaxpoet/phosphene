// ReDiagnosis — CS.1.y re-diagnosis: short-window Beat This! phase accuracy.
//
// CS.1.y.2 (the onset-based cold-start fix) failed validation and was reverted
// (CLAUDE.md Failed Approach #68 — the sub-bass onset detector is not a
// beat-phase reference). The replacement direction is to correct the cold-start
// grid phase from Beat This! run on the first few seconds of LIVE tap audio.
//
// The load-bearing unknown: does Beat This! produce an accurate *phase* on a
// short (≤ 5 s) window? Short windows degrade tempo (Failed Approaches
// #50/#51), but the cached grid already supplies a reliable tempo — only phase
// is needed, and one beat at a known tempo pins phase. This mode measures it.
//
// For each track it runs Beat This! on the first 3 / 4 / 5 s of the raw-tap
// slice (exactly what a live cold-start fix would see) and compares the beat
// phase against full-window Beat This! on the same track — which is the
// verifier's own audible-beat reference. Output: per-track / per-window phase
// error, plus a shortlist of tracks where Beat This! is itself suspect (for
// Matt's M7 ear check — the fix aligns the grid to Beat This!-on-tap and the
// verifier scores against the same detector, so on those tracks the verifier
// cannot be the judge).
//
// No production code; offline; uses captures we already have.

import Foundation
import Session

enum ReDiagnosis {

    // MARK: - Tunables

    /// Short windows tested (s). The cold-start fix would run Beat This! on the
    /// first W s of live tap audio; the correction it produces is valid back to
    /// frame 1 (it is *applied* at ~W s — within Matt's < 5 s budget).
    static let testWindowsS: [Double] = [3.0, 4.0, 5.0]
    /// Reference grid: full-window Beat This! — the same slice the verifier uses
    /// as its audible-beat ground truth (3 s lead-in, 25 s total; 25 s keeps the
    /// spectrogram under Beat This!'s 1500-frame tMax).
    static let referenceLeadS = 3.0
    static let referenceDurationS = 25.0
    /// A window's phase is "viable" when its offset from the reference is within
    /// this — the verifier's aspirational ±30 ms tolerance.
    static let viablePhaseErrorMs = 30.0
    /// Minimum resultant length for a viable window: the short grid's residuals
    /// vs the reference must form a tight cluster (the two grids are co-periodic
    /// — a low resultant means the short window got the tempo wrong).
    static let viableResultant = 0.90
    /// Below this many reference beats Beat This! struggled on the *full* window
    /// — the track is flagged suspect regardless of the short-window result.
    static let minReferenceBeats = 8
    /// Short-window phase spread (across 3/4/5 s) above this flags the track:
    /// Beat This! phase is unstable here, so no window length is trustworthy.
    static let unstableSpreadMs = 50.0

    // MARK: - Result model

    struct WindowResult {
        let windowS: Double
        let beatCount: Int
        let gridBPM: Double
        /// Circular-mean phase offset (signed ms) of this window's grid vs the
        /// full-window reference grid.
        let phaseErrorMs: Double
        /// Resultant length [0,1] of the residual cluster — consistency.
        let resultant: Double
        /// Beat This! returned a usable grid on this window. Fewer than 4 beats
        /// is a degenerate/empty grid (and a 1-beat grid gives a trivially
        /// perfect R) — those cannot anchor a phase.
        var hasUsableGrid: Bool { beatCount >= 4 }
        var viable: Bool {
            hasUsableGrid && abs(phaseErrorMs) <= viablePhaseErrorMs
                && resultant >= viableResultant
        }
    }

    struct TrackReDiag {
        let label: String
        let referenceBeatCount: Int
        let referenceBPM: Double
        let windows: [WindowResult]
        let flagged: Bool
        let flagReason: String?
    }

    // MARK: - Run

    static func run(
        tracks: [TrackSegment],
        rawTap: RawTapAnalysis,
        rawTapStartWallclockS: Double?,
        analyzer: DefaultBeatGridAnalyzer
    ) -> [TrackReDiag] {
        tracks.enumerated().map { idx, track in
            print("  [\(idx + 1)/\(tracks.count)] \(track.label) — short-window Beat This! …")
            return analyzeTrack(
                track: track,
                rawTap: rawTap,
                rawTapStartWallclockS: rawTapStartWallclockS,
                analyzer: analyzer)
        }
    }

    private static func analyzeTrack(
        track: TrackSegment,
        rawTap: RawTapAnalysis,
        rawTapStartWallclockS: Double?,
        analyzer: DefaultBeatGridAnalyzer
    ) -> TrackReDiag {
        guard let rawStart = rawTapStartWallclockS, let first = track.frames.first else {
            return TrackReDiag(
                label: track.label,
                referenceBeatCount: 0,
                referenceBPM: 0,
                windows: [],
                flagged: true,
                flagReason: "no raw-tap-start anchor")
        }
        // Clock offset: same sync-independent path as ColdStartAnalysis.
        let beatBass = ColdStartAnalysis.beatBassOnsets(frames: track.frames)
        let coarse = (first.wallclockS - rawStart) - first.playbackTimeS
        let offsetS = ClockOffset.estimate(
            rawOnsets: rawTap.onsets, beatBassOnsets: beatBass, coarseS: coarse)

        // Reference: full-window Beat This! (verifier's audible reference), raw-tap clock.
        let reference = BeatThisGrid.beats(
            samples: rawTap.samples,
            sampleRate: rawTap.sampleRate,
            sliceStartS: offsetS - referenceLeadS,
            durationS: referenceDurationS,
            analyzer: analyzer)
        let refPeriod = medianIOI(reference)
        let refBPM = refPeriod > 0 ? 60.0 / refPeriod : 0
        guard reference.count >= minReferenceBeats, refPeriod > 0 else {
            return TrackReDiag(
                label: track.label,
                referenceBeatCount: reference.count,
                referenceBPM: refBPM,
                windows: [],
                flagged: true,
                flagReason: "Beat This! found only \(reference.count) beats on the "
                    + "full 25 s window — unreliable on this track")
        }

        // Short windows — exactly what a live cold-start fix would see.
        var windows: [WindowResult] = []
        for windowS in testWindowsS {
            let short = BeatThisGrid.beats(
                samples: rawTap.samples,
                sampleRate: rawTap.sampleRate,
                sliceStartS: offsetS,
                durationS: windowS,
                analyzer: analyzer)
            let stats = phaseOffset(of: short, vs: reference, period: refPeriod)
            let shortPeriod = medianIOI(short)
            windows.append(WindowResult(
                windowS: windowS,
                beatCount: short.count,
                gridBPM: shortPeriod > 0 ? 60.0 / shortPeriod : 0,
                phaseErrorMs: stats.offsetMs,
                resultant: stats.resultant))
        }

        // A track is suspect when the 3/4/5 s phase estimates disagree: a viable
        // track's windows should converge as W grows, not scatter.
        let offsets = windows.map(\.phaseErrorMs)
        let spread = (offsets.max() ?? 0) - (offsets.min() ?? 0)
        let unstable = spread > unstableSpreadMs
        let unstableNote = "short-window phase spans \(Int(spread.rounded())) ms "
            + "across 3/4/5 s — Beat This! phase is unstable on this track"
        return TrackReDiag(
            label: track.label,
            referenceBeatCount: reference.count,
            referenceBPM: refBPM,
            windows: windows,
            flagged: unstable,
            flagReason: unstable ? unstableNote : nil)
    }

    // MARK: - Phase comparison

    /// Circular-mean phase offset (signed ms) of `grid` relative to `reference`,
    /// plus the resultant length [0,1]. Residual = grid beat − nearest reference
    /// beat, wrapped into [−P/2, P/2]; aggregated as a circular mean so the wrap
    /// at ±P/2 is handled correctly. Both grids are in the raw-tap clock; a
    /// constant clock shift does not affect the offset (it is shift-invariant).
    private static func phaseOffset(
        of grid: [Double],
        vs reference: [Double],
        period: Double
    ) -> (offsetMs: Double, resultant: Double) {
        guard !grid.isEmpty, !reference.isEmpty, period > 0 else { return (0, 0) }
        var sumCos = 0.0
        var sumSin = 0.0
        var matched = 0
        for beat in grid {
            guard let nearest = ColdStartAnalysis.nearestValue(to: beat, in: reference)
            else { continue }
            var residual = beat - nearest
            residual -= period * (residual / period).rounded()
            let theta = 2.0 * .pi * residual / period
            sumCos += cos(theta)
            sumSin += sin(theta)
            matched += 1
        }
        guard matched > 0 else { return (0, 0) }
        let resultant = (sumCos * sumCos + sumSin * sumSin).squareRoot() / Double(matched)
        let meanResidual = atan2(sumSin, sumCos) * period / (2.0 * .pi)
        return (meanResidual * 1000.0, resultant)
    }

    private static func medianIOI(_ beats: [Double]) -> Double {
        guard beats.count >= 2 else { return 0 }
        var iois: [Double] = []
        iois.reserveCapacity(beats.count - 1)
        for i in 1..<beats.count { iois.append(beats[i] - beats[i - 1]) }
        return ColdStartAnalysis.median(iois)
    }

    // MARK: - Reporting

    static func consoleSummary(_ results: [ReDiagnosis.TrackReDiag]) -> String {
        var lines = ["CS.1.y re-diagnosis — short-window Beat This! phase accuracy"]
        for result in results {
            if result.windows.isEmpty {
                lines.append("  [FLAG] \(result.label) — \(result.flagReason ?? "no data")")
                continue
            }
            let cells = result.windows.map { cellText($0) }
            let flag = result.flagged ? "  ⚠ \(result.flagReason ?? "")" : ""
            lines.append("  \(result.label) — \(cells.joined(separator: "  "))\(flag)")
        }
        for window in ReDiagnosis.testWindowsS {
            let viable = results.filter { result in
                result.windows.first { $0.windowS == window }?.viable ?? false
            }.count
            let rated = results.filter { !$0.windows.isEmpty }.count
            let win = String(format: "%.0f", window)
            let tol = String(format: "%.0f", viablePhaseErrorMs)
            let res = String(format: "%.2f", viableResultant)
            lines.append("  window \(win)s: \(viable)/\(rated) tracks viable "
                + "(≤ \(tol) ms, R ≥ \(res))")
        }
        return lines.joined(separator: "\n")
    }

    /// Compact console cell for one window result.
    private static func cellText(_ window: WindowResult) -> String {
        let win = String(format: "%.0f", window.windowS)
        guard window.hasUsableGrid else {
            return "\(win)s empty(\(window.beatCount)b)"
        }
        let mark = window.viable ? "✓" : "✗"
        let offset = String(format: "%+.0f", window.phaseErrorMs)
        return "\(win)s \(offset)ms\(mark)"
    }

    static func report(
        session: URL,
        rawTap: RawTapAnalysis,
        results: [ReDiagnosis.TrackReDiag]
    ) -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let durationStr = String(format: "%.1f", rawTap.durationS)
        let resultantStr = String(format: "%.2f", viableResultant)
        var md = """
        # Cold-Start Re-Diagnosis (CS.1.y) — short-window Beat This! phase accuracy

        - **Generated:** \(stamp)
        - **Session:** `\(session.lastPathComponent)`
        - **raw_tap.wav:** \(durationStr) s @ \(Int(rawTap.sampleRate)) Hz

        ## Question

        The CS.1.y.2 onset-based fix failed (Failed Approach #68). The replacement
        direction corrects the cold-start grid phase from Beat This! run on the
        first ≤ 5 s of live tap audio. This measures whether that is viable: for
        each track, Beat This! on the first 3 / 4 / 5 s of the tap is compared to
        full-window Beat This! (the verifier's audible-beat reference). A window
        is **viable** when its phase is within ±\(Int(viablePhaseErrorMs)) ms of
        the reference with resultant ≥ \(resultantStr).

        ## Per-track, per-window phase error

        | Track | ref beats | ref BPM | 3 s | 4 s | 5 s |
        |---|---|---|---|---|---|

        """
        for result in results {
            md += renderRow(result) + "\n"
        }
        md += "\n_Cell: phase offset vs full-window reference (signed ms), "
        md += "resultant R, beat count, ✓ viable / ✗ not._\n\n"
        md += renderWindowSummary(results)
        md += renderShortlist(results)
        return md
    }

    private static func renderRow(_ result: ReDiagnosis.TrackReDiag) -> String {
        guard !result.windows.isEmpty else {
            return "| \(result.label) | — | — | "
                + "FLAGGED: \(result.flagReason ?? "no data") | | |"
        }
        let bpm = String(format: "%.1f", result.referenceBPM)
        var row = "| \(result.label) | \(result.referenceBeatCount) | \(bpm) |"
        for window in result.windows {
            row += " \(rowCell(window)) |"
        }
        return row
    }

    /// Markdown table cell for one window result.
    private static func rowCell(_ window: WindowResult) -> String {
        guard window.hasUsableGrid else {
            return "empty (\(window.beatCount) beats) ✗"
        }
        let mark = window.viable ? "✓" : "✗"
        let offset = String(format: "%+.0f", window.phaseErrorMs)
        let res = String(format: "%.2f", window.resultant)
        return "\(offset) ms (R \(res), \(window.beatCount)b) \(mark)"
    }

    private static func renderWindowSummary(_ results: [ReDiagnosis.TrackReDiag]) -> String {
        let rated = results.filter { !$0.windows.isEmpty }.count
        var md = "## Window viability summary\n\n| Window | tracks viable |\n|---|---|\n"
        for window in testWindowsS {
            let viable = results.filter { result in
                result.windows.first { $0.windowS == window }?.viable ?? false
            }.count
            md += "| \(Int(window)) s | \(viable) / \(rated) |\n"
        }
        return md + "\n"
    }

    private static func renderShortlist(_ results: [ReDiagnosis.TrackReDiag]) -> String {
        let flagged = results.filter { $0.flagged }
        var md = "## Beat This! trust shortlist (for M7 ear check)\n\n"
        if flagged.isEmpty {
            md += "_No tracks flagged by the automated checks._\n\n"
        } else {
            for result in flagged {
                md += "- **\(result.label)** — \(result.flagReason ?? "flagged")\n"
            }
            md += "\n"
        }
        md += "These tracks need a human check: does Beat This!'s grid sit on the "
        md += "beat a listener hears? The fix aligns the grid to Beat This!-on-tap "
        md += "and the verifier scores against the same detector, so on these "
        md += "tracks the verifier cannot be the judge — only M7 can.\n"
        return md
    }
}
