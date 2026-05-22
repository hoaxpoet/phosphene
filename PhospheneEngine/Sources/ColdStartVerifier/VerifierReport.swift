// VerifierReport — Markdown evidence pack for a CS.1 verification run.
//
// Mirrors the SR.1 evidence-pack convention: every cold-start fidelity claim in
// a CS closeout cites this report, not a hypothesis (CLAUDE.md "Diagnostic
// infrastructure precedes fidelity claims").

import Foundation

enum VerifierReport {

    static func render(
        sessionURL: URL, artifacts: SessionArtifacts, rawTap: RawTapAnalysis,
        analysis: ColdStartAnalysisResult, config: VerifierConfig
    ) -> String {
        var md = ""
        md += header(sessionURL: sessionURL, rawTap: rawTap, artifacts: artifacts)
        md += configuration(config: config)
        md += verdict(analysis: analysis, config: config)
        md += perTrackTable(analysis: analysis, config: config)
        md += failureDives(analysis: analysis, config: config)
        md += degenerateSection(analysis: analysis)
        md += methodology(config: config)
        return md
    }

    // MARK: - Sections

    private static func header(
        sessionURL: URL, rawTap: RawTapAnalysis, artifacts: SessionArtifacts
    ) -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
        return """
        # Cold-Start Beat-Sync Verification — CS.1

        - **Generated:** \(stamp)
        - **Session:** `\(sessionURL.lastPathComponent)`
        - **Frames:** \(artifacts.frames.count) across \(artifacts.tracks.count) track segment(s)
        - **raw_tap.wav:** \(fmt(rawTap.durationS, 1)) s @ \(Int(rawTap.sampleRate)) Hz, \
        \(rawTap.onsets.count) sub-bass onsets detected offline

        """
    }

    private static func configuration(config: VerifierConfig) -> String {
        """
        ## Configuration

        | Parameter | Value |
        |---|---|
        | Cold-start window | first \(fmt(config.firstWindowS, 0)) s of each track |
        | Pass tolerance | ±\(fmt(config.passWindowMs, 0)) ms |
        | Aspirational tolerance | ±\(fmt(config.tightWindowMs, 0)) ms |
        | Per-track pass rate | \(fmt(config.passRate * 100, 0))% of matched beats |
        | Display-shift correction | \(fmt(config.displayShiftMs, 1)) ms |

        """
    }

    private static func verdict(
        analysis: ColdStartAnalysisResult, config: VerifierConfig
    ) -> String {
        let rated = analysis.tracks.filter { $0.verdict != .degenerate }.count
        let degenerate = analysis.tracks.count - rated
        let badge = analysis.overallPass ? "✅ PASS" : "❌ FAIL"
        return """
        ## Verdict — \(badge)

        \(fmt(analysis.aggregatePassRate * 100, 0))% of \(rated) rated track(s) meet the \
        ±\(fmt(config.passWindowMs, 0)) ms / \(fmt(config.passRate * 100, 0))% bar \
        (\(degenerate) track(s) degenerate — bar does not apply). The bar to clear is \
        ≥ \(fmt(config.passRate * 100, 0))% of rated tracks passing.

        > Automated verification is necessary but not sufficient — Phase CS closes only \
        on Matt's perceptual M7 review of a real listening-party playlist.

        """
    }

    private static func perTrackTable(
        analysis: ColdStartAnalysisResult, config: VerifierConfig
    ) -> String {
        let passWin = fmt(config.passWindowMs, 0)
        let tightWin = fmt(config.tightWindowMs, 0)
        var md = "## Per-track results\n\n"
        md += "| # | Track | BPM | Align corr | Frame-1 drift | Locked @ "
        md += "| Matched | Within ±\(passWin)ms | Within ±\(tightWin)ms "
        md += "| Median corr. Δ | Verdict |\n"
        md += "|---|---|---|---|---|---|---|---|---|---|---|\n"
        for row in analysis.tracks {
            md += perTrackRow(row)
        }
        md += "\n_Align corr ⚠️ = low-confidence raw_tap↔features alignment; "
        md += "treat that row's deltas with caution._\n\n"
        return md
    }

    private static func perTrackRow(_ row: TrackResult) -> String {
        let bpm = row.windowGridBPM > 0 ? fmt(row.windowGridBPM, 1) : "—"
        let corr = row.alignment.confident
            ? fmt(row.alignment.correlation, 2)
            : "\(fmt(row.alignment.correlation, 2)) ⚠️"
        let lock = row.lockReachedAtPt.map { "\(fmt($0, 1)) s" } ?? "—"
        let matched = row.verdict == .degenerate
            ? "—" : "\(row.matchedCount)/\(row.matchedCount + row.unmatchedCount)"
        let pass = row.withinPassPct.map { fmt($0 * 100, 0) + "%" } ?? "—"
        let tight = row.withinTightPct.map { fmt($0 * 100, 0) + "%" } ?? "—"
        let med = row.medianCorrectedMs.map { fmtSigned($0, 1) + " ms" } ?? "—"
        return "| \(row.track.index + 1) | \(row.track.label) | \(bpm) | \(corr) "
            + "| \(fmtSigned(row.frame1DriftMs, 1)) ms | \(lock) | \(matched) "
            + "| \(pass) | \(tight) | \(med) | \(verdictBadge(row.verdict)) |\n"
    }

    private static func failureDives(
        analysis: ColdStartAnalysisResult, config: VerifierConfig
    ) -> String {
        let failing = analysis.tracks.filter { $0.verdict == .fail }
        guard !failing.isEmpty else { return "" }
        var md = "## Failure dives\n\n"
        for result in failing {
            md += "### \(result.track.label)\n\n"
            md += "Frame-1 drift \(fmtSigned(result.frame1DriftMs, 1)) ms; "
            md += "median corrected Δ \(fmtSigned(result.medianCorrectedMs ?? 0, 1)) ms; "
            md += "MAD \(fmt(result.madMs ?? 0, 1)) ms; "
            md += "\(fmt((result.withinPassPct ?? 0) * 100, 0))% within "
            md += "±\(fmt(config.passWindowMs, 0)) ms.\n\n"
            md += "| Onset (pt s) | Visual beat (pt s) | Raw Δ | Corrected Δ |\n"
            md += "|---|---|---|---|\n"
            for delta in result.deltas {
                let visual = delta.visualBeatPt.map { fmt($0, 3) } ?? "— (unmatched)"
                let raw = delta.rawDeltaMs.map { fmtSigned($0, 1) + " ms" } ?? "—"
                let corr = delta.correctedDeltaMs.map { fmtSigned($0, 1) + " ms" } ?? "—"
                md += "| \(fmt(delta.onsetPt, 3)) | \(visual) | \(raw) | \(corr) |\n"
            }
            md += "\n"
        }
        return md
    }

    private static func degenerateSection(analysis: ColdStartAnalysisResult) -> String {
        let degenerate = analysis.tracks.filter { $0.verdict == .degenerate }
        guard !degenerate.isEmpty else { return "" }
        var md = "## Degenerate tracks (bar does not apply)\n\n"
        for result in degenerate {
            md += "- **\(result.track.label)** — \(result.degenerateReason ?? "unspecified")\n"
        }
        return md + "\n"
    }

    private static func methodology(config: VerifierConfig) -> String {
        """
        ## Methodology & caveats

        - **Ground truth:** `raw_tap.wav` (Core Audio tap audio, pre-DSP) replayed \
        through the engine's `FFTProcessor` → `BeatDetector` at the 1024-sample hop. \
        `onsets[0]` (sub-bass) is the audible-beat reference — the same detector \
        `GridOnsetCalibrator` and the live `LiveBeatDriftTracker` match against.
        - **Visual beats:** `beatPhase01` sawtooth wraps in `features.csv`, crossing \
        time interpolated from the phase advance on each side of the wrapping frame.
        - **Clock alignment:** per-track low-frequency energy-envelope cross-correlation \
        between `raw_tap.wav` and `features.csv` `subBass`. Tracks aligned in order, \
        each constrained after the previous in tap-time. A ⚠️ in the table marks a \
        low-confidence alignment (weak correlation or too-short envelope).
        - **Display-shift caveat:** `beatPhase01` bakes in `visualPhaseOffsetMs + \
        audioOutputLatencyMs` (LiveBeatDriftTracker.swift:573); `raw_tap.wav` is \
        tap-time. The raw per-beat Δ therefore carries `−displayShift`. The corrected \
        Δ adds back the configured `--display-shift-ms` (\(fmt(config.displayShiftMs, 1)) ms) \
        to recover the genuine calibration error. Audio-output latency itself is \
        out of scope for Phase CS (design doc §6.13).
        - **Beat This! cross-check** (design doc §7.1, kickoff step 3) is a CS.1 \
        follow-up — the BeatDetector path above is the complete primary measurement.

        """
    }

    // MARK: - Formatting

    private static func verdictBadge(_ verdict: TrackVerdict) -> String {
        switch verdict {
        case .pass: return "✅ pass"
        case .fail: return "❌ fail"
        case .degenerate: return "➖ degenerate"
        }
    }

    private static func fmt(_ value: Double, _ places: Int) -> String {
        String(format: "%.\(places)f", value)
    }

    private static func fmtSigned(_ value: Double, _ places: Int) -> String {
        String(format: "%+.\(places)f", value)
    }
}
