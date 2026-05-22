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
        - **raw_tap.wav:** \(fmt(rawTap.durationS, 1)) s @ \(Int(rawTap.sampleRate)) Hz

        """
    }

    private static func configuration(config: VerifierConfig) -> String {
        """
        ## Configuration

        | Parameter | Value |
        |---|---|
        | Window | \(fmt(config.firstWindowS, 0)) s @ +\(fmt(config.windowStartS, 0)) s into each track |
        | Pass tolerance | ±\(fmt(config.passWindowMs, 0)) ms |
        | Aspirational tolerance | ±\(fmt(config.tightWindowMs, 0)) ms |
        | Per-track pass rate | \(fmt(config.passRate * 100, 0))% of windowed beats |
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
        md += "| # | Track | BPM | Frame-1 drift | Locked @ | Matched "
        md += "| Within ±\(passWin)ms | Within ±\(tightWin)ms | Median corr. Δ "
        md += "| Clock offset | Verdict |\n"
        md += "|---|---|---|---|---|---|---|---|---|---|---|\n"
        for row in analysis.tracks {
            md += perTrackRow(row)
        }
        md += "\n_Matched = windowed Beat This! beats that found a visual beat within "
        md += "match range. Clock offset = raw-tap ↔ playback-time offset (onset-paired)._\n\n"
        return md
    }

    private static func perTrackRow(_ row: TrackResult) -> String {
        let bpm = row.windowGridBPM > 0 ? fmt(row.windowGridBPM, 1) : "—"
        let lock = row.lockReachedAtPt.map { "\(fmt($0, 1)) s" } ?? "—"
        let matched = row.verdict == .degenerate
            ? "—" : "\(row.matchedCount)/\(row.matchedCount + row.unmatchedCount)"
        let pass = row.withinPassPct.map { fmt($0 * 100, 0) + "%" } ?? "—"
        let tight = row.withinTightPct.map { fmt($0 * 100, 0) + "%" } ?? "—"
        let med = row.medianCorrectedMs.map { fmtSigned($0, 1) + " ms" } ?? "—"
        return "| \(row.track.index + 1) | \(row.track.label) | \(bpm) "
            + "| \(fmtSigned(row.frame1DriftMs, 1)) ms | \(lock) | \(matched) "
            + "| \(pass) | \(tight) | \(med) | \(fmt(row.clockOffsetS, 2)) s "
            + "| \(verdictBadge(row.verdict)) |\n"
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
            md += "| Audible beat (pt s) | Visual beat (pt s) | Raw Δ | Corrected Δ |\n"
            md += "|---|---|---|---|\n"
            for delta in result.deltas {
                let visual = delta.visualBeatPt.map { fmt($0, 3) } ?? "— (unmatched)"
                let raw = delta.rawDeltaMs.map { fmtSigned($0, 1) + " ms" } ?? "—"
                let corr = delta.correctedDeltaMs.map { fmtSigned($0, 1) + " ms" } ?? "—"
                md += "| \(fmt(delta.audibleBeatPt, 3)) | \(visual) | \(raw) | \(corr) |\n"
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

        - **Visual beat:** `beatPhase01` sawtooth wraps in `features.csv` — the grid \
        prediction the cold-start infrastructure produces.
        - **Audible beat:** a Beat This! beat. Beat This! is re-run offline on a \
        per-track ~25 s slice of `raw_tap.wav` (the pre-DSP tap audio) — a genuine \
        one-beat-per-beat tracker, unlike the live `beatBass` onset feature which \
        fires more than once per beat.
        - **Clock offset:** raw_tap.wav and features.csv are independent but faithful \
        real-time clocks. The per-track offset is pinned by pairing raw_tap \
        BeatDetector onsets against features.csv `beatBass` onsets — the same physical \
        events, so the offset is sync-independent and cannot absorb a real sync error.
        - **Display-shift caveat:** `beatPhase01` bakes in `visualPhaseOffsetMs + \
        audioOutputLatencyMs` (LiveBeatDriftTracker.swift:573). The corrected Δ adds \
        back the configured `--display-shift-ms` (\(fmt(config.displayShiftMs, 1)) ms) \
        to recover the genuine calibration error. Audio-output latency itself is out \
        of scope for Phase CS (design doc §6.13).
        - **Meaningful window:** the verdict is strongest in the pre-lock portion of \
        the cold-start window — once the drift tracker locks (`Locked @`), \
        `beatPhase01` is nudged toward the live onsets by design.

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
