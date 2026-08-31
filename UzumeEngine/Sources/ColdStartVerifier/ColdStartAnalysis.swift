// ColdStartAnalysis — the CS.1 measurement (Option C).
//
// Visual beat  = `beatPhase01` sawtooth wrap (the grid prediction the cold-start
//                infrastructure produces) — features.csv, playback-time clock.
// Audible beat = a Beat This! beat. Beat This! is re-run offline on a per-track
//                slice of raw_tap.wav (BeatThisGrid) — a genuine beat *tracker*,
//                one beat per beat. Its beats are mapped from the raw-tap clock
//                into playback-time via the sync-independent ClockOffset.
//
// Why Option C: `beatBass` (the live onset feature) fires >1×/beat, so matching
// it to per-beat visual beats produced a meaningless walking-sawtooth delta
// (see 2026-05-22 discussion). Beat This! gives a true one-per-beat grid, so the
// per-beat delta is a real visual-vs-audible sync error.
//
// Per-track verdict (kickoff step 4):
//   pass       — non-degenerate; ≥ passRate of windowed beats within ±passWindowMs.
//   fail       — non-degenerate; below passRate.
//   degenerate — no grid, no raw-tap anchor, or Beat This! found too few beats.

import Foundation
import Session

// MARK: - Result model

enum TrackVerdict: String {
    case pass, fail, degenerate
}

/// One audible beat (Beat This!) and its nearest visual beat.
struct BeatDelta {
    let audibleBeatPt: Double
    let visualBeatPt: Double?
    /// visual − audible, ms. nil when no visual beat is within match range.
    let rawDeltaMs: Double?
    /// rawDeltaMs + displayShiftMs — the latency-corrected calibration error.
    let correctedDeltaMs: Double?
}

struct TrackResult {
    let track: TrackSegment
    let verdict: TrackVerdict
    let degenerateReason: String?
    let deltas: [BeatDelta]              // windowed audible beats, in order
    let matchedCount: Int
    let unmatchedCount: Int              // audible beats with no visual beat near
    let medianCorrectedMs: Double?
    let madMs: Double?
    let withinPassPct: Double?           // of all windowed audible beats
    let withinTightPct: Double?
    let frame1DriftMs: Double
    let windowGridBPM: Double
    let lockReachedAtPt: Double?
    /// raw-tap ↔ playback-time clock offset used to map Beat This! beats.
    let clockOffsetS: Double
    /// Total Beat This! beats found over the analysed slice.
    let beatThisBeatCount: Int
}

struct ColdStartAnalysisResult {
    let tracks: [TrackResult]
    let aggregatePassRate: Double        // over non-degenerate tracks
    let overallPass: Bool
}

/// Per-track setup values threaded through the degenerate / rated paths.
private struct TrackContext {
    let frame1DriftMs: Double
    let windowGridBPM: Double
    let lockReachedAtPt: Double?
    let firstPt: Double
    let windowEnd: Double
    let clockOffsetS: Double
    let beatThisBeatCount: Int
}

// MARK: - Analysis

enum ColdStartAnalysis {

    /// `beatBass` rising-edge threshold (used only to pin the clock offset).
    static let beatBassOnsetThreshold = 0.6
    /// An audible beat matches a visual beat within this fraction of a period.
    static let maxMatchFractionOfPeriod = 0.6
    /// Fewer than this many Beat This! beats in the window → degenerate.
    static let minBeatsForRhythmic = 4
    /// Beat This! slice: lead-in before the track, and total slice length (s).
    /// 25 s keeps the spectrogram under Beat This!'s tMax (30 s at 50 fps).
    static let sliceLeadS = 3.0
    static let sliceDurationS = 25.0

    static func run(
        tracks: [TrackSegment], config: VerifierConfig,
        rawTap: RawTapAnalysis, rawTapStartWallclockS: Double?,
        analyzer: DefaultBeatGridAnalyzer
    ) -> ColdStartAnalysisResult {
        var results: [TrackResult] = []
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
                let ctx = makeContext(
                    track: track, config: config, offsetS: 0, beatThisCount: 0)
                results.append(degenerateResult(
                    track, ctx, "no raw-tap-start anchor in session.log"))
            }
        }
        let rated = results.filter { $0.verdict != .degenerate }
        let passed = rated.filter { $0.verdict == .pass }.count
        let rate = rated.isEmpty ? 0 : Double(passed) / Double(rated.count)
        return ColdStartAnalysisResult(
            tracks: results,
            aggregatePassRate: rate,
            overallPass: !rated.isEmpty && rate >= config.passRate)
    }

    /// Beat This! one-per-beat grid for a track, mapped into playback-time, plus
    /// the clock offset used. nil when there is no raw-tap-start anchor.
    private static func resolveAudibleBeats(
        track: TrackSegment, rawTap: RawTapAnalysis,
        rawTapStartWallclockS: Double?, analyzer: DefaultBeatGridAnalyzer
    ) -> (beatsPt: [Double], offsetS: Double)? {
        guard let rawStart = rawTapStartWallclockS, let first = track.frames.first else {
            return nil
        }
        // Sync-independent clock offset (rawTapTime ≈ playbackTime + offsetS).
        let beatBass = beatBassOnsets(frames: track.frames)
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

    /// The pure per-track verdict: given the Beat This! audible beats already
    /// mapped into playback-time, measure them against `beatPhase01` wraps.
    static func evaluate(
        track: TrackSegment, audibleBeatsPt: [Double],
        offsetS: Double, config: VerifierConfig
    ) -> TrackResult {
        let context = makeContext(
            track: track,
            config: config,
            offsetS: offsetS,
            beatThisCount: audibleBeatsPt.count)
        guard track.hasGrid else {
            return degenerateResult(track, context, "no beat grid installed (reactive mode)")
        }
        guard context.windowGridBPM > 0 else {
            return degenerateResult(track, context, "no usable grid BPM in window")
        }
        let audible = audibleBeatsPt.filter {
            $0 >= context.firstPt && $0 <= context.windowEnd
        }
        guard audible.count >= minBeatsForRhythmic else {
            let reason = "Beat This! found only \(audible.count) beats in first "
                + "\(Int(config.firstWindowS)) s (rhythmless or analysis failed)"
            return degenerateResult(track, context, reason)
        }
        let visual = visualBeatTimes(frames: track.frames).filter {
            $0 >= context.firstPt && $0 <= context.windowEnd
        }
        let period = 60.0 / context.windowGridBPM
        let deltas = matchDeltas(
            audible: audible, visual: visual, period: period, config: config)
        return rateTrack(track: track, context: context, deltas: deltas, config: config)
    }

    // MARK: - Per-track stages

    private static func makeContext(
        track: TrackSegment, config: VerifierConfig,
        offsetS: Double, beatThisCount: Int
    ) -> TrackContext {
        let firstPt = track.firstPlaybackTimeS + config.windowStartS
        let windowEnd = firstPt + config.firstWindowS
        let windowFrames = track.frames.filter {
            $0.playbackTimeS >= firstPt && $0.playbackTimeS <= windowEnd
        }
        let bpms = windowFrames.map(\.gridBPM).filter { $0 > 0 }
        // `frame1DriftMs` = drift at the start of the measurement window. For
        // windowStartS = 0 this is true frame 1; for a post-snap window
        // (windowStartS ≈ 20) it is the drift right after the snap landed.
        let frame1Drift = windowFrames.first?.driftMs
            ?? track.frames.first?.driftMs
            ?? 0
        return TrackContext(
            frame1DriftMs: frame1Drift,
            windowGridBPM: bpms.isEmpty ? (track.installedBPM ?? 0) : median(bpms),
            lockReachedAtPt: track.frames.first { $0.lockState == 2 }?.playbackTimeS,
            firstPt: firstPt,
            windowEnd: windowEnd,
            clockOffsetS: offsetS,
            beatThisBeatCount: beatThisCount)
    }

    /// Match each windowed audible beat to its nearest visual beat.
    private static func matchDeltas(
        audible: [Double], visual: [Double], period: Double, config: VerifierConfig
    ) -> [BeatDelta] {
        let maxMatch = maxMatchFractionOfPeriod * period
        return audible.map { beat in
            if let nearest = nearestValue(to: beat, in: visual),
               abs(nearest - beat) <= maxMatch {
                let raw = (nearest - beat) * 1000.0
                return BeatDelta(
                    audibleBeatPt: beat,
                    visualBeatPt: nearest,
                    rawDeltaMs: raw,
                    correctedDeltaMs: raw + config.displayShiftMs)
            }
            return BeatDelta(
                audibleBeatPt: beat,
                visualBeatPt: nil,
                rawDeltaMs: nil,
                correctedDeltaMs: nil)
        }
    }

    private static func rateTrack(
        track: TrackSegment, context: TrackContext,
        deltas: [BeatDelta], config: VerifierConfig
    ) -> TrackResult {
        let matched = deltas.compactMap(\.correctedDeltaMs)
        let unmatched = deltas.count - matched.count
        // Within-tolerance fraction is over ALL windowed audible beats — an
        // unmatched beat (no visual beat near it) is a missed beat, a failure.
        let total = Double(max(deltas.count, 1))
        let withinPass = Double(matched.filter { abs($0) <= config.passWindowMs }.count) / total
        let withinTight = Double(matched.filter { abs($0) <= config.tightWindowMs }.count) / total
        let med = matched.isEmpty ? nil : median(matched)
        let mad = matched.isEmpty ? nil : median(matched.map { abs($0 - (med ?? 0)) })
        return TrackResult(
            track: track,
            verdict: withinPass >= config.passRate ? .pass : .fail,
            degenerateReason: nil,
            deltas: deltas,
            matchedCount: matched.count,
            unmatchedCount: unmatched,
            medianCorrectedMs: med,
            madMs: mad,
            withinPassPct: withinPass,
            withinTightPct: withinTight,
            frame1DriftMs: context.frame1DriftMs,
            windowGridBPM: context.windowGridBPM,
            lockReachedAtPt: context.lockReachedAtPt,
            clockOffsetS: context.clockOffsetS,
            beatThisBeatCount: context.beatThisBeatCount)
    }

    private static func degenerateResult(
        _ track: TrackSegment, _ context: TrackContext, _ reason: String
    ) -> TrackResult {
        TrackResult(
            track: track,
            verdict: .degenerate,
            degenerateReason: reason,
            deltas: [],
            matchedCount: 0,
            unmatchedCount: 0,
            medianCorrectedMs: nil,
            madMs: nil,
            withinPassPct: nil,
            withinTightPct: nil,
            frame1DriftMs: context.frame1DriftMs,
            windowGridBPM: context.windowGridBPM,
            lockReachedAtPt: context.lockReachedAtPt,
            clockOffsetS: context.clockOffsetS,
            beatThisBeatCount: context.beatThisBeatCount)
    }

    // MARK: - Onset / beat extraction

    /// `beatBass` onset times (playback-time) — rising edges crossing up past
    /// `beatBassOnsetThreshold`. Used only to pin the clock offset.
    static func beatBassOnsets(frames: [FeatureFrame]) -> [Double] {
        var onsets: [Double] = []
        var prev = 0.0
        for frame in frames {
            if frame.beatBass > beatBassOnsetThreshold, prev <= beatBassOnsetThreshold {
                onsets.append(frame.playbackTimeS)
            }
            prev = frame.beatBass
        }
        return onsets
    }

    /// Times (playback-time) at which `beatPhase01` wraps from ~1 back to ~0.
    /// The crossing is interpolated within the wrapping frame gap.
    static func visualBeatTimes(frames: [FeatureFrame]) -> [Double] {
        var beats: [Double] = []
        guard frames.count > 1 else { return beats }
        for idx in 1..<frames.count {
            let prev = frames[idx - 1]
            let cur = frames[idx]
            guard cur.beatPhase01 < prev.beatPhase01 - 0.5 else { continue }
            let advanceBefore = 1.0 - prev.beatPhase01
            let advanceAfter = cur.beatPhase01
            let total = advanceBefore + advanceAfter
            let frac = total > 1e-6 ? advanceBefore / total : 0.5
            beats.append(prev.playbackTimeS
                + frac * (cur.playbackTimeS - prev.playbackTimeS))
        }
        return beats
    }

    // MARK: - Numeric helpers

    static func nearestValue(to target: Double, in sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        var lo = 0
        var hi = sorted.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] < target { lo = mid + 1 } else { hi = mid }
        }
        let upper = sorted[lo]
        guard lo > 0 else { return upper }
        let lower = sorted[lo - 1]
        return abs(upper - target) < abs(lower - target) ? upper : lower
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let ordered = values.sorted()
        let mid = ordered.count / 2
        return ordered.count.isMultiple(of: 2)
            ? (ordered[mid - 1] + ordered[mid]) / 2
            : ordered[mid]
    }
}

// MARK: - Console summary

extension ColdStartAnalysisResult {
    func consoleSummary(config: VerifierConfig) -> String {
        var lines: [String] = []
        for result in tracks {
            let verdictText = result.verdict.rawValue.uppercased()
            var detail = ""
            if result.verdict == .degenerate {
                detail = result.degenerateReason ?? ""
            } else if let pct = result.withinPassPct, let med = result.medianCorrectedMs {
                detail = String(
                    format: "%.0f%% within ±%.0f ms, median %+.1f ms",
                    pct * 100,
                    config.passWindowMs,
                    med)
            }
            lines.append("  [\(verdictText)] \(result.track.label) — \(detail)")
        }
        let rated = tracks.filter { $0.verdict != .degenerate }.count
        let header = String(
            format: "CS.1 verdict: %@ — %.0f%% of %d rated track(s) pass (bar: %.0f%%)",
            overallPass ? "PASS" : "FAIL",
            aggregatePassRate * 100,
            rated,
            config.passRate * 100)
        return ([header] + lines).joined(separator: "\n")
    }
}
