// ClockOffset — Pin the raw-tap ↔ playback-time clock offset, sync-independently.
//
// `offsetS` is defined so that `rawTapTime ≈ playbackTime + offsetS`. It is a
// pure constant per track (both clocks are faithful real time — established
// 2026-05-22). It is estimated by pairing raw_tap BeatDetector onsets with
// features.csv `beatBass` onsets: the two are the SAME physical onsets detected
// by the SAME algorithm in two clocks, so the gap within a matched pair is
// purely the clock-origin difference — it carries no visual-vs-audible sync
// error, so estimating the offset this way cannot absorb (and hide) a real
// sync error. The wall-clock anchor (`coarseS`, ±1 s from 1-second log
// resolution) seeds the search; the histogram mode of (rawOnset − beatBassOnset)
// refines it to a few ms.

import Foundation

enum ClockOffset {

    /// Search radius around the coarse anchor (s) — covers the ±1 s log resolution.
    static let searchRadiusS = 1.5
    /// Histogram bin width for the offset mode (s).
    static let binS = 0.02

    /// Estimate `offsetS` where `rawTapTime ≈ playbackTime + offsetS`.
    static func estimate(
        rawOnsets: [Double], beatBassOnsets: [Double], coarseS: Double
    ) -> Double {
        var candidates: [Double] = []
        for bass in beatBassOnsets {
            let predicted = bass + coarseS
            for raw in rawOnsets where abs(raw - predicted) <= searchRadiusS {
                candidates.append(raw - bass)
            }
        }
        guard !candidates.isEmpty else { return coarseS }

        // Matched pairs cluster at the true offset; mismatched pairs spread
        // across ±beat-period. The densest histogram bin is the true offset.
        var bins: [Int: Int] = [:]
        for value in candidates {
            bins[Int((value / binS).rounded()), default: 0] += 1
        }
        guard let modeBin = bins.max(by: { $0.value < $1.value })?.key else {
            return coarseS
        }
        let center = Double(modeBin) * binS
        let inMode = candidates.filter { abs($0 - center) <= binS }
        return inMode.isEmpty ? center : inMode.reduce(0, +) / Double(inMode.count)
    }
}
