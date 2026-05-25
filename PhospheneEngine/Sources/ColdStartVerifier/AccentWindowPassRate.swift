// AccentWindowPassRate — BSAudit.3.validate.1 verifier mode.
//
// Per-track scoring of the BSAudit.3.impl architecture's perceptual contract:
// "accents fire within ±60 ms of audible beats when the system claims sync;
//  otherwise the system stays gracefully degraded and does not accent-pulse."
//
// Visual beat reference is Beat This! re-run offline on the same per-track
// raw_tap slice ColdStartAnalysis uses (within-capture-stable; the Path A
// finding made cross-capture comparisons unsound, so this mode is strictly
// within-capture).
//
// PER-TRACK ALGORITHM (kickoff §Sub-commit 1 §Verifier mode)
// ---------------------------------------------------------
// 1. Slice the first `firstWindowS` (default 10 s) of features.csv rows.
// 2. Take BeatThisGrid.beats from raw_tap.wav as the audible-beat ground truth.
// 3. For each windowed audible beat at time t_beat, scan rows whose
//    playback_time_s ∈ [t_beat − acceptMs, t_beat + acceptMs]; an accent
//    fired iff any such row has beatComposite > accentThreshold. The
//    `beatComposite` column on BSAudit.3.impl builds is already multiplied
//    by accentConfidence, so the rising edge above threshold encodes BOTH
//    "the underlying onset detector fired" AND "the gating let it through".
// 4. pass_rate = accent_hits / audible_beat_count.
//
// PER-TRACK VERDICT
// -----------------
// - pass-firing   pass_rate ≥ perTrackPassRate.
// - pass-degraded max accent_confidence in the window < degradedConfThreshold
//                 AND max beatComposite in the window ≤ accentThreshold — i.e.,
//                 the system never claimed sync and didn't pulse incorrectly.
// - fail          otherwise (the system claimed sync but missed).
//
// AGGREGATE GATE (design §12 + §4)
// --------------------------------
// ≥ 90 % of non-degenerate catalog reaches pass-firing OR pass-degraded.

import Foundation
import Session

// MARK: - Config

struct AccentWindowConfig {
    /// Window length (s) measured per track. Default 10 from VerifierConfig.
    let firstWindowS: Double
    /// Offset (s) into the track where measurement starts. 0 = track start.
    let windowStartS: Double
    /// Acceptance half-width for accent-vs-audible-beat (ms).
    let acceptMs: Double
    /// Rising-edge threshold for the (gated) `beatComposite` column.
    let accentThreshold: Double
    /// Per-track verdict gate for pass-firing.
    let perTrackPassRate: Double
    /// Max accent_confidence allowed in-window to count as graceful degradation.
    let degradedConfThreshold: Double
}

// MARK: - Result model

enum AccentWindowVerdict: String {
    case passFiring   = "pass-firing"
    case passDegraded = "pass-degraded"
    case fail
    case degenerate
}

struct AccentWindowTrackResult {
    let track: TrackSegment
    let verdict: AccentWindowVerdict
    let degenerateReason: String?
    let audibleBeats: Int
    let accentHits: Int
    let passRate: Double            // 0 when no windowed audible beats
    let maxConfidence: Double       // max accent_confidence over the window
    let maxComposite: Double        // max beatComposite over the window
    let beatThisBeatCount: Int      // total Beat This! beats over the slice
    let clockOffsetS: Double
    let windowGridBPM: Double
    let firstPt: Double
    let windowEnd: Double
}

struct AccentWindowAnalysisResult {
    let tracks: [AccentWindowTrackResult]
    /// (pass-firing + pass-degraded) over non-degenerate tracks.
    let aggregateOkRate: Double
    /// True iff aggregateOkRate ≥ 0.90.
    let overallPass: Bool

    /// Counts by verdict over all tracks (including degenerate).
    var passFiringCount: Int { tracks.filter { $0.verdict == .passFiring }.count }
    var passDegradedCount: Int { tracks.filter { $0.verdict == .passDegraded }.count }
    var failCount: Int { tracks.filter { $0.verdict == .fail }.count }
    var degenerateCount: Int { tracks.filter { $0.verdict == .degenerate }.count }
}

// MARK: - Analysis

enum AccentWindowPassRate {

    // Defaults — exposed for the CLI option layer.
    static let defaultAcceptMs: Double = 60
    static let defaultAccentThreshold: Double = 0.3
    static let defaultPerTrackPassRate: Double = 0.80
    static let defaultDegradedConfThreshold: Double = 0.3
    static let aggregateGate: Double = 0.90

    /// Fewer than this many Beat This! beats in the window → degenerate.
    static let minBeatsForRhythmic = 4
    /// Beat This! slice geometry — reuse ColdStartAnalysis values so the
    /// audible-beat reference is identical to the existing verifier mode.
    static let sliceLeadS: Double = ColdStartAnalysis.sliceLeadS
    static let sliceDurationS: Double = ColdStartAnalysis.sliceDurationS

    static func run(
        tracks: [TrackSegment],
        config: AccentWindowConfig,
        rawTap: RawTapAnalysis,
        rawTapStartWallclockS: Double?,
        analyzer: DefaultBeatGridAnalyzer
    ) -> AccentWindowAnalysisResult {
        var results: [AccentWindowTrackResult] = []
        for (idx, track) in tracks.enumerated() {
            print("  [\(idx + 1)/\(tracks.count)] \(track.label) — Beat This! …")
            if let resolved = resolveAudibleBeats(
                track: track,
                rawTap: rawTap,
                rawTapStartWallclockS: rawTapStartWallclockS,
                analyzer: analyzer) {
                results.append(evaluate(
                    track: track,
                    audibleBeatsPt: resolved.beatsPt,
                    offsetS: resolved.offsetS,
                    config: config))
            } else {
                results.append(degenerateResult(
                    track: track,
                    config: config,
                    offsetS: 0,
                    beatThisCount: 0,
                    reason: "no raw-tap-start anchor in session.log"))
            }
        }
        let rated = results.filter { $0.verdict != .degenerate }
        let ok = rated.filter { $0.verdict == .passFiring || $0.verdict == .passDegraded }.count
        let rate = rated.isEmpty ? 0 : Double(ok) / Double(rated.count)
        return AccentWindowAnalysisResult(
            tracks: results,
            aggregateOkRate: rate,
            overallPass: !rated.isEmpty && rate >= aggregateGate)
    }

    /// Beat This! one-per-beat audible reference for a track, mapped into
    /// playback-time. Reuses the same slice geometry + ClockOffset estimator
    /// as ColdStartAnalysis so the two modes can be cross-checked on the same
    /// session.
    private static func resolveAudibleBeats(
        track: TrackSegment, rawTap: RawTapAnalysis,
        rawTapStartWallclockS: Double?, analyzer: DefaultBeatGridAnalyzer
    ) -> (beatsPt: [Double], offsetS: Double)? {
        guard let rawStart = rawTapStartWallclockS, let first = track.frames.first else {
            return nil
        }
        let beatBass = ColdStartAnalysis.beatBassOnsets(frames: track.frames)
        let coarse = (first.wallclockS - rawStart) - first.playbackTimeS
        let offsetS = ClockOffset.estimate(
            rawOnsets: rawTap.onsets, beatBassOnsets: beatBass, coarseS: coarse)
        let beatThisRawTap = BeatThisGrid.beats(
            samples: rawTap.samples,
            sampleRate: rawTap.sampleRate,
            sliceStartS: offsetS - sliceLeadS,
            durationS: sliceDurationS,
            analyzer: analyzer)
        return (beatThisRawTap.map { $0 - offsetS }, offsetS)
    }

    /// Pure per-track verdict — testable without Beat This! / Metal. The
    /// audible-beat reference is supplied already mapped into playback-time.
    static func evaluate(
        track: TrackSegment,
        audibleBeatsPt: [Double],
        offsetS: Double,
        config: AccentWindowConfig
    ) -> AccentWindowTrackResult {
        let firstPt = track.firstPlaybackTimeS + config.windowStartS
        let windowEnd = firstPt + config.firstWindowS
        let windowFrames = track.frames.filter {
            $0.playbackTimeS >= firstPt && $0.playbackTimeS <= windowEnd
        }
        let maxConf = windowFrames.map(\.accentConfidence).max() ?? 0
        let maxComposite = windowFrames.map(\.beatComposite).max() ?? 0
        let windowBPM: Double = {
            let bpms = windowFrames.map(\.gridBPM).filter { $0 > 0 }
            if bpms.isEmpty { return track.installedBPM ?? 0 }
            return ColdStartAnalysis.median(bpms)
        }()
        let beatThisCount = audibleBeatsPt.count
        let audible = audibleBeatsPt.filter { $0 >= firstPt && $0 <= windowEnd }

        guard track.hasGrid else {
            return degenerateResult(
                track: track,
                config: config,
                offsetS: offsetS,
                beatThisCount: beatThisCount,
                reason: "no beat grid installed (reactive mode)")
        }
        guard audible.count >= minBeatsForRhythmic else {
            let reason = "Beat This! found only \(audible.count) beats in first "
                + "\(Int(config.firstWindowS)) s (rhythmless or analysis failed)"
            return degenerateResult(
                track: track,
                config: config,
                offsetS: offsetS,
                beatThisCount: beatThisCount,
                reason: reason)
        }

        let hits = countAccentHits(
            audible: audible, frames: windowFrames, config: config)
        let rate = Double(hits) / Double(audible.count)
        let verdict: AccentWindowVerdict
        if rate >= config.perTrackPassRate {
            verdict = .passFiring
        } else if maxConf < config.degradedConfThreshold
                  && maxComposite <= config.accentThreshold {
            verdict = .passDegraded
        } else {
            verdict = .fail
        }
        return AccentWindowTrackResult(
            track: track,
            verdict: verdict,
            degenerateReason: nil,
            audibleBeats: audible.count,
            accentHits: hits,
            passRate: rate,
            maxConfidence: maxConf,
            maxComposite: maxComposite,
            beatThisBeatCount: beatThisCount,
            clockOffsetS: offsetS,
            windowGridBPM: windowBPM,
            firstPt: firstPt,
            windowEnd: windowEnd)
    }

    /// Number of audible beats that have at least one rising-edge accent row
    /// (beatComposite > accentThreshold) within ±acceptMs of the beat.
    private static func countAccentHits(
        audible: [Double],
        frames: [FeatureFrame],
        config: AccentWindowConfig
    ) -> Int {
        let acceptS = config.acceptMs / 1000.0
        var hits = 0
        for beat in audible {
            let lo = beat - acceptS
            let hi = beat + acceptS
            let fired = frames.contains { frame in
                frame.playbackTimeS >= lo
                    && frame.playbackTimeS <= hi
                    && frame.beatComposite > config.accentThreshold
            }
            if fired { hits += 1 }
        }
        return hits
    }

    private static func degenerateResult(
        track: TrackSegment,
        config: AccentWindowConfig,
        offsetS: Double,
        beatThisCount: Int,
        reason: String
    ) -> AccentWindowTrackResult {
        let firstPt = track.firstPlaybackTimeS + config.windowStartS
        let windowEnd = firstPt + config.firstWindowS
        let windowFrames = track.frames.filter {
            $0.playbackTimeS >= firstPt && $0.playbackTimeS <= windowEnd
        }
        let bpms = windowFrames.map(\.gridBPM).filter { $0 > 0 }
        let windowBPM = bpms.isEmpty ? (track.installedBPM ?? 0) : ColdStartAnalysis.median(bpms)
        return AccentWindowTrackResult(
            track: track,
            verdict: .degenerate,
            degenerateReason: reason,
            audibleBeats: 0,
            accentHits: 0,
            passRate: 0,
            maxConfidence: windowFrames.map(\.accentConfidence).max() ?? 0,
            maxComposite: windowFrames.map(\.beatComposite).max() ?? 0,
            beatThisBeatCount: beatThisCount,
            clockOffsetS: offsetS,
            windowGridBPM: windowBPM,
            firstPt: firstPt,
            windowEnd: windowEnd)
    }
}

// MARK: - Console summary

extension AccentWindowAnalysisResult {
    func consoleSummary(config: AccentWindowConfig) -> String {
        var lines: [String] = []
        for result in tracks {
            let tag = result.verdict.rawValue.uppercased()
            let detail: String
            if result.verdict == .degenerate {
                detail = result.degenerateReason ?? ""
            } else {
                detail = String(
                    format: "%d/%d hits (%.0f%%), max conf %.2f, max composite %.2f",
                    result.accentHits,
                    result.audibleBeats,
                    result.passRate * 100,
                    result.maxConfidence,
                    result.maxComposite)
            }
            lines.append("  [\(tag)] \(result.track.label) — \(detail)")
        }
        let rated = tracks.filter { $0.verdict != .degenerate }.count
        let okCount = passFiringCount + passDegradedCount
        let header = String(
            format: "BSAudit.3 accent-window verdict: %@ — %.0f%% of %d rated track(s) "
                + "PASS-firing|degraded (bar: %.0f%%, accept ±%.0f ms, threshold %.2f)",
            overallPass ? "PASS" : "FAIL",
            rated > 0 ? Double(okCount) / Double(rated) * 100 : 0,
            rated,
            AccentWindowPassRate.aggregateGate * 100,
            config.acceptMs,
            config.accentThreshold)
        return ([header] + lines).joined(separator: "\n")
    }
}
