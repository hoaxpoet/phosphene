// ColdStartAnalysis — The CS.1 measurement.
//
// For each track, for the first `firstWindowS` seconds, compare visual beat
// times (beatPhase01 sawtooth wraps in features.csv) against audible beat times
// (raw_tap.wav sub-bass onsets, mapped into playback-time via ClockAlignment).
//
// Per-track verdict (kickoff step 4):
//   pass       — non-degenerate; ≥ passRate of matched audible beats land within
//                ±passWindowMs of a visual beat (display-shift-corrected).
//   fail       — non-degenerate; below passRate.
//   degenerate — no grid installed (reactive mode), too few audible onsets
//                (rhythmless), or too many onsets off-grid (syncopated). The
//                "beat-synced from frame 1" bar does not cleanly apply.

import Foundation

// MARK: - Result model

enum TrackVerdict: String {
    case pass, fail, degenerate
}

/// One audible beat and its nearest visual beat.
struct BeatDelta {
    let onsetPt: Double
    let visualBeatPt: Double?
    /// visual − audible, ms. nil when unmatched.
    let rawDeltaMs: Double?
    /// rawDeltaMs + displayShiftMs — the latency-corrected calibration error.
    let correctedDeltaMs: Double?
}

struct TrackResult {
    let track: TrackSegment
    let alignment: TrackAlignment
    let verdict: TrackVerdict
    let degenerateReason: String?
    let deltas: [BeatDelta]            // first-window, audible-beat order
    let matchedCount: Int
    let unmatchedCount: Int
    let medianCorrectedMs: Double?
    let madMs: Double?                 // median absolute deviation of corrected delta
    let withinPassPct: Double?
    let withinTightPct: Double?
    let frame1DriftMs: Double
    let windowGridBPM: Double
    let lockReachedAtPt: Double?
}

struct ColdStartAnalysisResult {
    let tracks: [TrackResult]
    let aggregatePassRate: Double      // over non-degenerate tracks
    let overallPass: Bool
}

/// Per-track setup values reused across the degenerate / rated paths.
private struct TrackContext {
    let frame1DriftMs: Double
    let windowGridBPM: Double
    let lockReachedAtPt: Double?
    let windowEnd: Double
}

// MARK: - Analysis

enum ColdStartAnalysis {

    /// Onset is matched to a visual beat when within this fraction of a beat
    /// period. Beyond it the onset is "off-grid" (syncopation / detector noise).
    static let maxMatchFractionOfPeriod = 0.6
    /// A non-reactive track with more than this fraction of windowed onsets
    /// off-grid is reclassified `degenerate` (syncopated) rather than failed.
    static let degenerateOffGridFraction = 0.35
    /// Fewer than this many audible onsets in the window → degenerate (rhythmless).
    static let minOnsetsForRhythmic = 4
    /// Seconds of slack beyond the cold-start window used for clock alignment.
    /// The alignment envelope = `firstWindowS + this` — long enough to register
    /// unambiguously, short enough to stay inside a 30 s `raw_tap.wav`.
    static let alignmentSlackS = 12.0

    static func run(
        tracks: [TrackSegment], rawTap: RawTapAnalysis, config: VerifierConfig
    ) -> ColdStartAnalysisResult {
        let alignments = ClockAlignment.align(
            tracks: tracks,
            rawTap: rawTap,
            alignmentWindowS: config.firstWindowS + alignmentSlackS)
        let alignByIndex = Dictionary(uniqueKeysWithValues: alignments.map { ($0.trackIndex, $0) })

        var results: [TrackResult] = []
        for track in tracks {
            let alignment = alignByIndex[track.index]
                ?? TrackAlignment(
                    trackIndex: track.index,
                    offsetS: 0,
                    correlation: 0,
                    confident: false)
            results.append(analyzeTrack(
                track: track, alignment: alignment, rawTap: rawTap, config: config))
        }

        let rated = results.filter { $0.verdict != .degenerate }
        let passed = rated.filter { $0.verdict == .pass }.count
        let rate = rated.isEmpty ? 0 : Double(passed) / Double(rated.count)
        return ColdStartAnalysisResult(
            tracks: results,
            aggregatePassRate: rate,
            overallPass: !rated.isEmpty && rate >= config.passRate)
    }

    private static func analyzeTrack(
        track: TrackSegment, alignment: TrackAlignment,
        rawTap: RawTapAnalysis, config: VerifierConfig
    ) -> TrackResult {
        let context = makeContext(track: track, config: config)

        guard track.hasGrid else {
            return degenerateResult(track, alignment, context, "no beat grid installed (reactive mode)")
        }
        guard context.windowGridBPM > 0 else {
            return degenerateResult(track, alignment, context, "no usable grid BPM in window")
        }
        // Without a confident raw_tap↔features alignment the deltas are not
        // trustworthy — mark un-verifiable rather than emit a garbage verdict.
        // The common cause is raw_tap.wav not covering this track (30 s default
        // cap — capture with PHOSPHENE_FULL_RAW_TAP=1 for a multi-track session).
        guard alignment.confident else {
            let corr = String(format: "%.2f", alignment.correlation)
            let reason = "raw_tap↔features alignment unreliable (correlation \(corr)) "
                + "— track audio likely outside raw_tap.wav coverage"
            return degenerateResult(track, alignment, context, reason)
        }

        // Audible beats: raw_tap onsets mapped into playback-time, windowed.
        let onsets = rawTap.onsets
            .map { $0 + alignment.offsetS }
            .filter { $0 >= track.firstPlaybackTimeS && $0 <= context.windowEnd }
            .sorted()
        guard onsets.count >= minOnsetsForRhythmic else {
            let reason = "only \(onsets.count) audible onsets in first "
                + "\(Int(config.firstWindowS)) s (rhythmless)"
            return degenerateResult(track, alignment, context, reason)
        }

        // Visual beats: beatPhase01 sawtooth wraps, windowed.
        let visualBeats = visualBeatTimes(frames: track.frames)
            .filter { $0 >= track.firstPlaybackTimeS && $0 <= context.windowEnd }
            .sorted()

        let period = 60.0 / context.windowGridBPM
        let deltas = matchDeltas(
            onsets: onsets, visualBeats: visualBeats, period: period, config: config)
        let matched = deltas.compactMap(\.correctedDeltaMs)
        let unmatched = deltas.count - matched.count

        if Double(unmatched) / Double(deltas.count) > degenerateOffGridFraction {
            let reason = "\(unmatched)/\(deltas.count) audible onsets off-grid "
                + "(syncopated — bar does not cleanly apply)"
            return degenerateResult(track, alignment, context, reason)
        }
        guard !matched.isEmpty else {
            return degenerateResult(
                track, alignment, context, "no audible beat matched a visual beat")
        }
        return rateTrack(
            track: track,
            alignment: alignment,
            context: context,
            deltas: deltas,
            config: config)
    }

    // MARK: - Per-track stages

    private static func makeContext(
        track: TrackSegment, config: VerifierConfig
    ) -> TrackContext {
        let windowEnd = track.firstPlaybackTimeS + config.firstWindowS
        let windowFrames = track.frames.filter { $0.playbackTimeS <= windowEnd }
        let bpms = windowFrames.map(\.gridBPM).filter { $0 > 0 }
        return TrackContext(
            frame1DriftMs: track.frames.first?.driftMs ?? 0,
            windowGridBPM: bpms.isEmpty ? (track.installedBPM ?? 0) : median(bpms),
            lockReachedAtPt: track.frames.first { $0.lockState == 2 }?.playbackTimeS,
            windowEnd: windowEnd)
    }

    /// Match each windowed audible onset to its nearest visual beat.
    private static func matchDeltas(
        onsets: [Double], visualBeats: [Double], period: Double, config: VerifierConfig
    ) -> [BeatDelta] {
        let maxMatch = maxMatchFractionOfPeriod * period
        return onsets.map { onset in
            if let nearest = nearestValue(to: onset, in: visualBeats),
               abs(nearest - onset) <= maxMatch {
                let raw = (nearest - onset) * 1000.0
                return BeatDelta(
                    onsetPt: onset,
                    visualBeatPt: nearest,
                    rawDeltaMs: raw,
                    correctedDeltaMs: raw + config.displayShiftMs)
            }
            return BeatDelta(
                onsetPt: onset, visualBeatPt: nil, rawDeltaMs: nil, correctedDeltaMs: nil)
        }
    }

    private static func rateTrack(
        track: TrackSegment, alignment: TrackAlignment, context: TrackContext,
        deltas: [BeatDelta], config: VerifierConfig
    ) -> TrackResult {
        let matched = deltas.compactMap(\.correctedDeltaMs)
        let unmatched = deltas.count - matched.count
        let med = median(matched)
        let mad = median(matched.map { abs($0 - med) })
        let withinPass = Double(matched.filter { abs($0) <= config.passWindowMs }.count)
            / Double(matched.count)
        let withinTight = Double(matched.filter { abs($0) <= config.tightWindowMs }.count)
            / Double(matched.count)
        return TrackResult(
            track: track,
            alignment: alignment,
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
            lockReachedAtPt: context.lockReachedAtPt)
    }

    private static func degenerateResult(
        _ track: TrackSegment, _ alignment: TrackAlignment,
        _ context: TrackContext, _ reason: String
    ) -> TrackResult {
        TrackResult(
            track: track,
            alignment: alignment,
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
            lockReachedAtPt: context.lockReachedAtPt)
    }

    // MARK: - Visual beats

    /// Times (playback-time) at which `beatPhase01` wraps from ~1 back to ~0 —
    /// i.e. a beat lands. The crossing is interpolated within the wrapping frame
    /// gap from the phase advance on each side.
    private static func visualBeatTimes(frames: [FeatureFrame]) -> [Double] {
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

    private static func nearestValue(to target: Double, in sorted: [Double]) -> Double? {
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
