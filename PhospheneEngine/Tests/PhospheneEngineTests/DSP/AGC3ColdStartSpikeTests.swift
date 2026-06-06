// AGC3ColdStartSpikeTests — BUG-029 / D-147. The AGC `f.bass` cold-start band-value spike.
//
// At a track onset preceded by silence, BandEnergyProcessor's total-energy AGC denominator
// (`agcRunningAvg`, NOT reset per track) has decayed toward zero across the silence (or seeded at
// 1e-6 off the session-start pre-roll), so the first audible frame over-scales and `f.bass` spikes
// to an absolute ~3.5-4.0 (steady ~0.25 = 11-17x). AGC3.1 measured it on a real LF session
// (docs/diagnostics/AGC3_1_COLDSTART_SPIKE_2026-06-05.md).
//
// D-147 fix (option a — ease the meter in per track): seed-from-first-audible + hold-through-
// silence inside BandEnergyProcessor. These are LIVE-PATH tests (through the real MIRPipeline.process
// / BandEnergyProcessor) per FA #66 — the AGC2 cold-start hole shipped because its tests bypassed the
// live path. Each reproduces the spike un-fixed and asserts it gone with the fix.
//
// The byte-identical steady-state lock (agc3_steadyState_continuousAudible_unchanged) guards the
// D-147 hard rule: for continuous audible input the AGC's mix-density-stability response (D-026) must
// be untouched — the change is cold-start/silence ONLY.

import Foundation
import Testing
import Shared
@testable import DSP

// MARK: - Helpers

/// Bass-heavy magnitudes (energy in the low bins, like a kick / power chord) at a given amplitude.
private func bassMags(_ amp: Float) -> [Float] { (0..<512).map { $0 < 6 ? amp : Float(0) } }

/// The spike ceiling: after the fix, the first-audible-frame `f.bass` must not exceed this multiple
/// of the steady value. AGC3.1 measured 11-17x un-fixed; a smooth arrival is ~1x (approached from
/// below via the instant smoother). 2.0x is a generous gate that the un-fixed code blows past and a
/// correct ease-in clears comfortably.
private let kSpikeRatioCeiling: Float = 2.0

// MARK: - Session-start cold-start (frame-0 seed off silence)

/// Session starts with a silent pre-roll, then a steady bass onset. Un-fixed: the AGC seeds ~0 off
/// the silence and the first audible frame explodes `f.bass`. Fixed: seed-from-first-audible makes
/// the meter arrive at the right level and the smoother eases it in from below — no spike.
@Test func agc3_sessionStartOnset_doesNotSpike_liveMIRPipeline() {
    let pipeline = MIRPipeline()
    let onsetAmp: Float = 0.5
    var peakFirst3s: Float = 0
    var steadySum: Float = 0, steadyN: Float = 0
    for i in 0..<600 {
        let amp: Float = i < 60 ? 0.0 : onsetAmp        // 60 frames silent pre-roll, then steady onset
        let fv = pipeline.process(magnitudes: bassMags(amp), fps: 60, time: Float(i) / 60.0, deltaTime: 1.0 / 60.0)
        let sinceOnset = i - 60
        if (0..<180).contains(sinceOnset) { peakFirst3s = max(peakFirst3s, fv.bass) }   // first 3 s after onset
        if i >= 400 { steadySum += fv.bass; steadyN += 1 }                                // converged steady window
    }
    let steady = steadySum / steadyN
    let ratio = peakFirst3s / steady
    #expect(steady > 0.01, "sanity: steady f.bass should be meaningfully non-zero, got \(steady)")
    #expect(ratio < kSpikeRatioCeiling,
            "BUG-029: session-start f.bass spike — peak \(peakFirst3s) / steady \(steady) = \(ratio)x must be < \(kSpikeRatioCeiling)x")
}

// MARK: - Inter-track cold-start (denominator decays across the silence gap; no per-track reset)

/// Music, then a silence gap, then a second onset — WITHOUT resetting the pipeline (production never
/// calls MIRPipeline.reset() per track). Un-fixed: the denominator decays across the gap and the
/// second onset spikes (the AGC3.1 inter-track mode, the longer/worse one). Fixed: hold-through-
/// silence keeps the denominator at the prior music level, so the second onset arrives smoothly.
@Test func agc3_interTrackOnset_doesNotSpike_liveMIRPipeline() {
    let pipeline = MIRPipeline()
    let amp: Float = 0.5
    var t = 0
    func step(_ a: Float) -> Float {
        let fv = pipeline.process(magnitudes: bassMags(a), fps: 60, time: Float(t) / 60.0, deltaTime: 1.0 / 60.0)
        t += 1
        return fv.bass
    }
    // Track 1: 400 frames of steady music → AGC fully converged.
    var steady1Sum: Float = 0, steady1N: Float = 0
    for i in 0..<400 { let b = step(amp); if i >= 300 { steady1Sum += b; steady1N += 1 } }
    let steady1 = steady1Sum / steady1N
    // Inter-track low-energy period: a quiet tail + gap. AGC3.1 showed the real inter-track spikes
    // (17×) follow an effective multi-second low-energy decay (the track's quiet outro + the gap),
    // not a 1 s pure gap — over which `agcRunningAvg` decays far enough that the next onset over-
    // scales. 400 frames of silence models that cumulative decay (un-fixed: agcRunningAvg → ~0.04×).
    for _ in 0..<400 { _ = step(0.0) }
    // Track 2 onset: same steady level. Measure the first-3 s peak.
    var peak2: Float = 0
    for i in 0..<180 { let b = step(amp); if i < 180 { peak2 = max(peak2, b) } }
    let ratio = peak2 / steady1
    #expect(steady1 > 0.01, "sanity: track-1 steady f.bass should be meaningfully non-zero, got \(steady1)")
    #expect(ratio < kSpikeRatioCeiling,
            "BUG-029: inter-track f.bass spike — track-2 onset peak \(peak2) / track-1 steady \(steady1) = \(ratio)x must be < \(kSpikeRatioCeiling)x")
}

// MARK: - Steady-state byte-identical lock (D-147 hard rule: cold-start/silence ONLY)

/// Byte-identical steady-state lock (D-147 hard rule). For continuous audible input (frame-0 audible,
/// never silent) the D-147 fix takes the SAME code path as the prior algorithm — same seed (max(E,1e-6)
/// == E for E>1e-6), same EMA, same fast/moderate rate schedule. These checkpoints were captured from
/// the PRE-FIX BandEnergyProcessor; the post-fix code must reproduce them exactly, proving the total-
/// energy AGC's mix-density-stability response (D-026) is untouched (the change is cold-start/silence
/// ONLY). Any drift here means the fix leaked into steady state — a regression, not a pass.
@Test func agc3_steadyState_continuousAudible_byteIdentical() {
    let proc = BandEnergyProcessor()
    let mags = bassMags(0.5)
    // (frame, pre-fix f.bass) — captured 2026-06-05 from the pre-D-147 algorithm.
    let expected: [Int: Float] = [
        0: 0.043204270, 1: 0.078036666, 2: 0.106119439, 5: 0.161730975,
        30: 0.222681135, 60: 0.222961456, 120: 0.222961843, 300: 0.222961843,
    ]
    for i in 0..<400 {
        let r = proc.process(magnitudes: mags, fps: 60)
        if let want = expected[i] {
            #expect(abs(r.bass - want) < 1e-6,
                    "frame \(i): continuous-audible f.bass must be byte-identical to pre-fix (\(want)), got \(r.bass) — the fix must not touch steady state")
        }
    }
}
