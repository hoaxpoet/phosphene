// CrossCapture — BSAudit.2 (Path A.2): cross-capture Beat This! reproducibility.
//
// Per the BSAudit deliverable (`docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`),
// Hypothesis 1 (the dominant cause of CS.1.y.2-redo non-convergence) is that
// Beat This! on a live-tap slice is not cross-capture reproducible — same
// physical Spotify preview, two captures, different beat positions.
//
// This module measures it directly. Takes two or more session directories
// (same playlist, same prep cache assumed); for each track common to all
// sessions, runs Beat This! on the SAME playback-time slice in each session's
// raw_tap.wav and reports the per-session beats' phase residual vs the first
// session's reference.
//
//   - All sessions agree (phase ≤ ±30 ms, R ≥ 0.90) → Beat This!-on-tap is
//     cross-capture stable on this track; Hypothesis 1 partly contradicted.
//   - Sessions disagree → Hypothesis 1 confirmed at this slice configuration;
//     Path A fails; Path B (human-tap ground truth) is the only viable route.
//
// Reporting lives in `CrossCaptureReport.swift`. No production code touched.

import Foundation
import Metal
import Session

enum CrossCapture {

    // MARK: - Tunables

    /// Beat This! slice length (s) — matches ColdStartAnalysis's 25 s reference.
    static let defaultSliceDurationS: Double = 25.0
    /// Default playback-time offset (s) into each track at which the slice begins.
    static let defaultPositionStartS: Double = 0.0
    /// "Agreement" gate vs the first session's reference.
    static let viablePhaseErrorMs: Double = 30.0
    static let viableResultant: Double = 0.90
    /// Minimum reference beats Beat This! must find on the first-session slice.
    static let minReferenceBeats: Int = 8
    /// Max |Δ| (ms) above this flags the track as cross-capture-unstable.
    static let unstableSpreadMs: Double = 50.0

    // MARK: - Config (bundled to keep signatures short)

    struct Config {
        let sliceDurationS: Double
        let positionStartS: Double

        static let `default` = Config(
            sliceDurationS: defaultSliceDurationS,
            positionStartS: defaultPositionStartS)
    }

    // MARK: - Input model

    struct SessionInputs {
        let url: URL
        let artifacts: SessionArtifacts
        let rawTap: RawTapAnalysis
        var label: String { url.lastPathComponent }
    }

    // MARK: - Result model

    struct SessionResult {
        let label: String
        let beatCount: Int
        let gridBPM: Double
        let phaseErrorMs: Double
        let resultant: Double
        var hasUsableGrid: Bool { beatCount >= 4 }
        var viable: Bool {
            hasUsableGrid && abs(phaseErrorMs) <= viablePhaseErrorMs
                && resultant >= viableResultant
        }
    }

    struct TrackResult {
        let label: String
        let referenceBeatCount: Int
        let referenceBPM: Double
        let sessions: [SessionResult]
        /// Max |phaseErrorMs| across non-reference sessions.
        let maxAbsPhaseErrorMs: Double
        let flagged: Bool
        let flagReason: String?
    }

    /// Per-session Beat This! output for one track. Internal staging.
    struct SessionBeats {
        let label: String
        let beats: [Double]
        let period: Double
    }

    // MARK: - Run

    static func run(
        sessions: [SessionInputs],
        analyzer: DefaultBeatGridAnalyzer,
        config: Config = .default
    ) -> [TrackResult] {
        guard sessions.count >= 2 else { return [] }
        let trackLabels = commonTrackLabels(across: sessions)
        return trackLabels.enumerated().map { idx, label in
            print("  [\(idx + 1)/\(trackLabels.count)] \(label) — cross-capture …")
            return analyzeTrack(
                label: label,
                sessions: sessions,
                analyzer: analyzer,
                config: config)
        }
    }

    /// Track labels present in every session, ordered by the first session.
    private static func commonTrackLabels(across sessions: [SessionInputs]) -> [String] {
        guard let first = sessions.first else { return [] }
        let firstLabels = first.artifacts.tracks.compactMap { $0.title }
        return firstLabels.filter { label in
            sessions.dropFirst().allSatisfy { other in
                other.artifacts.tracks.contains { $0.title == label }
            }
        }
    }

    private static func analyzeTrack(
        label: String,
        sessions: [SessionInputs],
        analyzer: DefaultBeatGridAnalyzer,
        config: Config
    ) -> TrackResult {
        let perSessionBeats = collectPerSessionBeats(
            label: label,
            sessions: sessions,
            analyzer: analyzer,
            config: config)
        let reference = perSessionBeats[0]
        let refBPM = reference.period > 0 ? 60.0 / reference.period : 0
        guard reference.beats.count >= minReferenceBeats, reference.period > 0 else {
            return TrackResult(
                label: label,
                referenceBeatCount: reference.beats.count,
                referenceBPM: refBPM,
                sessions: [],
                maxAbsPhaseErrorMs: 0,
                flagged: true,
                flagReason: "Beat This! found only \(reference.beats.count) beats on "
                    + "first-session reference — unreliable on this track")
        }
        let sessionResults = perSessionBeats.map { entry in
            score(entry: entry, reference: reference)
        }
        let nonReference = sessionResults.dropFirst()
        let maxAbs = nonReference.map { abs($0.phaseErrorMs) }.max() ?? 0
        let unstable = maxAbs > unstableSpreadMs
        let reason = unstable
            ? "max |Δ| \(Int(maxAbs.rounded())) ms across \(nonReference.count) other "
                + "capture(s) — Beat This! cross-capture unstable on this track"
            : nil
        return TrackResult(
            label: label,
            referenceBeatCount: reference.beats.count,
            referenceBPM: refBPM,
            sessions: sessionResults,
            maxAbsPhaseErrorMs: maxAbs,
            flagged: unstable,
            flagReason: reason)
    }

    /// Run Beat This! on each session for the given track label; bundle beats
    /// + period per session.
    private static func collectPerSessionBeats(
        label: String,
        sessions: [SessionInputs],
        analyzer: DefaultBeatGridAnalyzer,
        config: Config
    ) -> [SessionBeats] {
        sessions.map { input -> SessionBeats in
            guard let track = input.artifacts.tracks.first(where: { $0.title == label }),
                  let beats = beats(
                    forTrack: track,
                    input: input,
                    config: config,
                    analyzer: analyzer) else {
                return SessionBeats(label: input.label, beats: [], period: 0)
            }
            let period = BeatPhaseStats.medianIOI(beats)
            return SessionBeats(label: input.label, beats: beats, period: period)
        }
    }

    /// Score one session's beats against the first-session reference.
    private static func score(
        entry: SessionBeats,
        reference: SessionBeats
    ) -> SessionResult {
        let entryBPM = entry.period > 0 ? 60.0 / entry.period : 0
        guard !entry.beats.isEmpty else {
            return SessionResult(
                label: entry.label,
                beatCount: 0,
                gridBPM: 0,
                phaseErrorMs: 0,
                resultant: 0)
        }
        let stats = BeatPhaseStats.phaseOffset(
            of: entry.beats,
            vs: reference.beats,
            period: reference.period)
        return SessionResult(
            label: entry.label,
            beatCount: entry.beats.count,
            gridBPM: entryBPM,
            phaseErrorMs: stats.offsetMs,
            resultant: stats.resultant)
    }

    /// Resolve clock offset for `track` in `input` and run Beat This! on the
    /// slice at `positionStartS`. Returns playback-time beats. nil when this
    /// session has no raw-tap-start anchor.
    private static func beats(
        forTrack track: TrackSegment,
        input: SessionInputs,
        config: Config,
        analyzer: DefaultBeatGridAnalyzer
    ) -> [Double]? {
        guard let rawStart = input.artifacts.rawTapStartWallclockS,
              let first = track.frames.first else { return nil }
        let beatBass = ColdStartAnalysis.beatBassOnsets(frames: track.frames)
        let coarse = (first.wallclockS - rawStart) - first.playbackTimeS
        let offsetS = ClockOffset.estimate(
            rawOnsets: input.rawTap.onsets,
            beatBassOnsets: beatBass,
            coarseS: coarse)
        let sliceStartRaw = first.playbackTimeS + config.positionStartS + offsetS
        let beatsRaw = BeatThisGrid.beats(
            samples: input.rawTap.samples,
            sampleRate: input.rawTap.sampleRate,
            sliceStartS: sliceStartRaw,
            durationS: config.sliceDurationS,
            analyzer: analyzer)
        return beatsRaw.map { $0 - offsetS }
    }

    // MARK: - Console summary (full report lives in CrossCaptureReport.swift)

    static func consoleSummary(_ results: [TrackResult]) -> String {
        var lines = ["BSAudit.2 (Path A.2) — cross-capture Beat This! reproducibility"]
        for result in results {
            if result.sessions.isEmpty {
                lines.append("  [FLAG] \(result.label) — \(result.flagReason ?? "no data")")
                continue
            }
            let cells = result.sessions.dropFirst().map { cellText($0) }
            let flag = result.flagged ? "  ⚠ \(result.flagReason ?? "")" : ""
            lines.append("  \(result.label) — \(cells.joined(separator: "  "))\(flag)")
        }
        let rated = results.filter { !$0.sessions.isEmpty }.count
        let unstable = results.filter { $0.flagged && !$0.sessions.isEmpty }.count
        lines.append("  \(unstable)/\(rated) tracks cross-capture-unstable "
            + "(max |Δ| > \(Int(unstableSpreadMs)) ms vs reference)")
        return lines.joined(separator: "\n")
    }

    private static func cellText(_ session: SessionResult) -> String {
        guard session.hasUsableGrid else {
            return "[\(session.label)] empty(\(session.beatCount)b)"
        }
        let mark = session.viable ? "✓" : "✗"
        let off = String(format: "%+.0f", session.phaseErrorMs)
        return "[\(session.label)] \(off)ms\(mark)"
    }
}
