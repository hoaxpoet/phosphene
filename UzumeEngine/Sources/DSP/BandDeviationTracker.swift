// BandDeviationTracker — per-band running-average pivot for FeatureVector deviation primitives.
//
// D-146 / BUG-027. The deviation primitives (bassRel/bassDev, midRel/midDev, trebRel/trebDev,
// and the *AttRel family) were derived against a FIXED 0.5 pivot. But BandEnergyProcessor's AGC
// normalises the TOTAL 6-band energy to 0.5, so each individual band centres well below 0.5
// (measured AGC2.1: bass ~0.25, mid ~0.04, treble ~0.005). The fixed-0.5 pivot therefore left
// midDev/trebDev structurally dead — firing ~0% on all music, both capture paths, even on
// genuinely mid-rich and treble-rich tracks.
//
// The fix mirrors the per-stem EMA pattern StemAnalyzer already ships (and which fires healthily,
// 56-77%): each band's deviation is measured against the band's OWN recent average via a per-band
// EMA, seed-from-first-non-zero (SAR.1) to avoid the cold-start dev = 2x inflation, reset on track
// change. The total-energy AGC is untouched, so the raw f.bass/f.mid/f.treble values and the
// cross-band relative-energy information are unchanged — only the *Rel/*Dev derivation moves off
// the 0.5 pivot.
//
// Formula (additive, mirroring StemAnalyzer.updateEMAsAndComputeDeviations): chosen over a
// scale-free `x/ema - 1` form because additive preserves the existing [-1, 1]-ish *Rel convention
// (presets clamp/smoothstep against it) and avoids the unbounded spikes the scale-free form
// produces on low-energy bands (AGC2.3 prototype: scale-free bass dev p90 reached 7.2). Trade-off:
// mid/treble deviations carry smaller absolute amplitude than bass (those bands are quieter
// post-AGC) — authors driving motion from midDev/trebDev may need a larger gain than for bassDev.
// See docs/SHADER_CRAFT.md §14.1.

import Foundation

// MARK: - BandDeviationTracker

/// Holds per-band running averages and derives the FeatureVector deviation primitives against
/// each band's own average instead of a fixed 0.5 pivot (D-146 / BUG-027).
struct BandDeviationTracker {

    /// Steady-state EMA decay per analysis frame. Mirrors `StemAnalyzer.stemEMADecay` so the band
    /// running averages adapt over the same window as the per-stem running averages.
    static let decay: Float = 0.9989

    /// Faster decay during the cold-start warmup (AGC2.4.1). At session start the first audio after
    /// silence explodes the AGC scale, so the band values spike many× normal (the live M7 saw bass
    /// = 3.688 vs a steady ~0.25). Seeding the slow-only EMA from that spike left it poisoned for
    /// ~3-4 minutes. The warmup decay converges the running average THROUGH the spike within a
    /// couple of seconds, then locks to the slow steady-state decay. Mirrors BandEnergyProcessor's
    /// own two-speed AGC warmup.
    static let warmupDecay: Float = 0.9
    /// Audio-present frames to run the warmup decay before locking to `decay`.
    static let warmupFrames = 180
    /// Ceiling on the band value fed to the average + deviation, so a cold-start AGC spike (the M7
    /// saw 3.69; a pathological silence→onset can be far higher) cannot poison the running average
    /// or produce an unbounded startup flash. Above any realistic loud-band value (~1.2).
    static let valueCeiling: Float = 2.0

    /// Per-band running averages. Order: bass, mid, treble, bassAtt, midAtt, trebleAtt.
    /// Sentinel 0 means "unseeded" (set at construction and by `reset()`).
    private(set) var runningAvg: [Float] = [0, 0, 0, 0, 0, 0]

    /// Count of audio-present frames since the last reset, capped at `warmupFrames`. Drives the
    /// two-speed warmup so the cold-start spike doesn't strand the average high.
    private var warmupCounter = 0

    // MARK: Output

    /// Deviation primitives derived for one frame.
    struct Output {
        var bassRel: Float
        var bassDev: Float
        var midRel: Float
        var midDev: Float
        var trebRel: Float
        var trebDev: Float
        var bassAttRel: Float
        var midAttRel: Float
        var trebAttRel: Float
    }

    /// The six AGC-normalised band values one frame contributes (3-band instant + attenuated).
    struct BandEnergies {
        var bass: Float
        var mid: Float
        var treble: Float
        var bassAtt: Float
        var midAtt: Float
        var trebleAtt: Float
    }

    // MARK: Lifecycle

    /// Reset all running averages to the unseeded sentinel. Call on track change so the next
    /// track's deviations are measured against its own audio, not the previous track's average.
    mutating func reset() {
        runningAvg = [0, 0, 0, 0, 0, 0]
        warmupCounter = 0
    }

    /// Update the per-band EMAs with this frame's AGC-normalised band values and return the
    /// deviation primitives measured against each band's own running average.
    ///
    /// The first post-reset frame seeds the running average from the band's value (when non-zero),
    /// so its deviation is exactly 0 rather than 2x the value (SAR.1 — same as StemAnalyzer).
    mutating func derive(_ bands: BandEnergies) -> Output {
        // Bound the values fed to the average + deviation so a cold-start AGC spike can neither
        // poison the running average nor produce an unbounded startup flash (AGC2.4.1).
        let values = [bands.bass, bands.mid, bands.treble, bands.bassAtt, bands.midAtt, bands.trebleAtt]
            .map { min(max($0, 0), Self.valueCeiling) }
        // Two-speed warmup: fast decay until the running average has converged through the
        // cold-start spike, then the slow steady-state decay.
        if values.contains(where: { $0 > 0 }) && warmupCounter < Self.warmupFrames { warmupCounter += 1 }
        let decay = warmupCounter < Self.warmupFrames ? Self.warmupDecay : Self.decay
        for i in 0..<6 {
            if runningAvg[i] == 0 && values[i] > 0 { runningAvg[i] = values[i] }
            runningAvg[i] = runningAvg[i] * decay + values[i] * (1 - decay)
        }
        let bassRel = (values[0] - runningAvg[0]) * 2.0
        let midRel = (values[1] - runningAvg[1]) * 2.0
        let trebRel = (values[2] - runningAvg[2]) * 2.0
        return Output(
            bassRel: bassRel,
            bassDev: max(0, bassRel),
            midRel: midRel,
            midDev: max(0, midRel),
            trebRel: trebRel,
            trebDev: max(0, trebRel),
            bassAttRel: (values[3] - runningAvg[3]) * 2.0,
            midAttRel: (values[4] - runningAvg[4]) * 2.0,
            trebAttRel: (values[5] - runningAvg[5]) * 2.0
        )
    }
}
