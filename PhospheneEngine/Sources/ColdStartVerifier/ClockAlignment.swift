// ClockAlignment — Register raw_tap.wav against features.csv per track.
//
// features.csv (per-track `playback_time_s`) and raw_tap.wav (tap-sample clock)
// are independent clocks, but they are recordings of the SAME audio. A low-
// frequency energy-envelope cross-correlation recovers the true per-track offset
// `O` such that `playback_time_s ≈ raw_tap_time + O`. This is a measurement-tool
// alignment of a known-real relationship — not a fit to flatter the result.
//
// Tracks are aligned in chronological order, each constrained to begin after the
// previous one in raw-tap time, so a track cannot false-match a later track with
// a similar kick pattern. Per-track (not global) alignment also makes the result
// immune to any slow tap-vs-system clock skew across a long session.

import Foundation

/// Per-track raw_tap ↔ features alignment.
struct TrackAlignment {
    let trackIndex: Int
    /// `playback_time_s = raw_tap_time + offsetS`.
    let offsetS: Double
    /// Peak normalized cross-correlation [−1, 1] — alignment quality.
    let correlation: Double
    /// True when the envelope was long enough and the correlation strong enough
    /// to trust the offset. Low-confidence tracks are reported but not gated.
    let confident: Bool
}

enum ClockAlignment {

    /// Minimum envelope length for a confident alignment (~1.4 s at a 21 ms hop).
    static let minEnvelopeSamples = 64
    /// Minimum peak correlation for a confident alignment.
    static let minConfidentCorrelation = 0.5

    static func align(tracks: [TrackSegment], rawTap: RawTapAnalysis) -> [TrackAlignment] {
        let hop = rawTap.envelopeHopS
        let rawEnv = rawTap.lowEnvelope
        var results: [TrackAlignment] = []
        var searchFloor = 0   // raw-tap hop index this track must start at or after

        for track in tracks {
            let featEnv = buildFeatureEnvelope(track: track, hop: hop)
            guard featEnv.count >= 4, rawEnv.count > featEnv.count + searchFloor else {
                results.append(TrackAlignment(
                    trackIndex: track.index,
                    offsetS: 0,
                    correlation: 0,
                    confident: false))
                continue
            }
            let peak = bestLag(feat: featEnv, raw: rawEnv, minLag: searchFloor)
            let offset = track.firstPlaybackTimeS - peak.lag * hop
            let confident = peak.correlation >= minConfidentCorrelation
                && featEnv.count >= minEnvelopeSamples
            results.append(TrackAlignment(
                trackIndex: track.index,
                offsetS: offset,
                correlation: peak.correlation,
                confident: confident))
            searchFloor = Int(peak.lag) + featEnv.count
        }
        return results
    }

    // MARK: - Feature envelope

    /// Resample a track's `subBass` column onto a uniform `hop`-spaced grid in
    /// playback-time, by linear interpolation between recorded frames.
    private static func buildFeatureEnvelope(track: TrackSegment, hop: Double) -> [Double] {
        let frames = track.frames
        guard let first = frames.first, let last = frames.last, hop > 0 else { return [] }
        let span = last.playbackTimeS - first.playbackTimeS
        guard span > 0 else { return [] }
        let count = Int(span / hop) + 1
        var env = [Double](repeating: 0, count: count)
        var cursor = 0
        for idx in 0..<count {
            let time = first.playbackTimeS + Double(idx) * hop
            while cursor + 1 < frames.count && frames[cursor + 1].playbackTimeS < time {
                cursor += 1
            }
            let frameA = frames[cursor]
            let frameB = cursor + 1 < frames.count ? frames[cursor + 1] : frameA
            let gap = frameB.playbackTimeS - frameA.playbackTimeS
            let frac = gap > 0 ? max(0, min(1, (time - frameA.playbackTimeS) / gap)) : 0
            env[idx] = frameA.subBass + frac * (frameB.subBass - frameA.subBass)
        }
        return env
    }

    // MARK: - Cross-correlation

    /// Best integer-plus-fractional lag (in hops) maximizing the normalized
    /// cross-correlation of `feat` against a window of `raw`, searched from
    /// `minLag`. Returns the lag and its correlation.
    private static func bestLag(
        feat: [Double], raw: [Double], minLag: Int
    ) -> (lag: Double, correlation: Double) {
        let count = feat.count
        let featMean = feat.reduce(0, +) / Double(count)
        let featCentered = feat.map { $0 - featMean }
        let featNorm = (featCentered.reduce(0) { $0 + $1 * $1 }).squareRoot()
        guard featNorm > 0 else { return (Double(minLag), 0) }

        let maxLag = raw.count - count
        guard maxLag >= minLag else { return (Double(minLag), 0) }
        var corr = [Double]()
        corr.reserveCapacity(maxLag - minLag + 1)

        for lag in minLag...maxLag {
            var sum = 0.0
            var sumSq = 0.0
            for idx in 0..<count {
                let val = raw[lag + idx]
                sum += val
                sumSq += val * val
            }
            let mean = sum / Double(count)
            let norm = (sumSq - sum * mean).squareRoot()
            guard norm > 0 else { corr.append(0); continue }
            var dot = 0.0
            for idx in 0..<count { dot += featCentered[idx] * (raw[lag + idx] - mean) }
            corr.append(dot / (featNorm * norm))
        }

        var bestIdx = 0
        for idx in corr.indices where corr[idx] > corr[bestIdx] { bestIdx = idx }
        let bestCorr = corr[bestIdx]

        // Parabolic interpolation of the peak for sub-hop precision.
        var frac = 0.0
        if bestIdx > 0, bestIdx < corr.count - 1 {
            let below = corr[bestIdx - 1]
            let here = corr[bestIdx]
            let above = corr[bestIdx + 1]
            let denom = below - 2 * here + above
            if abs(denom) > 1e-12 { frac = 0.5 * (below - above) / denom }
        }
        return (Double(minLag + bestIdx) + max(-0.5, min(0.5, frac)), bestCorr)
    }
}
