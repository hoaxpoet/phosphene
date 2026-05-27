// StemAnalyzerDeviationSeedingTests — regression-locks the SAR.1 first-frame
// EMA seeding contract for the four per-stem deviation primitives
// (`vocalsEnergyDev`, `drumsEnergyDev`, `bassEnergyDev`, `otherEnergyDev`).
//
// Pre-SAR.1 the running-average backing store for the deviation EMA was
// initialised to zero and re-zeroed on `reset()`. Combined with the formula
// `deviation = (energy - runningAvg) * 2.0`, the first post-reset frame
// emitted `2 × energy` regardless of the stem's typical level — producing
// values 20–38× the declared `[0, 1]` ceiling at every track change
// (session 2026-05-27T19-52-42Z: bassEnergyDev ramped 0 → 7.81 → 16.05 →
// 27.18 → 37.69 over ~60 ms at the live-stems handoff, then slowly decayed
// back into range over ~30 s as the 10-second EMA converged).
//
// The fix self-seeds `stemRunningAvg[i]` from the first frame after a reset
// where stem `i` has non-zero energy. The deviation then starts at exactly 0
// ("no deviation from this song's typical energy") and the EMA evolves
// normally. Per-stem independence preserves the seed re-arm semantics for
// stems whose energy is zero on the first post-reset frame.

import Foundation
import Testing
import Shared
@testable import DSP

// MARK: - Helpers

/// 1024-sample window of a sustained 220 Hz sine at the given amplitude.
/// Lands energy primarily in the low-bass band of the analyzer's 6-band split.
private func sineWindow(amplitude: Float, sampleRate: Float = 44100) -> [Float] {
    let count = 1024
    var out = [Float](repeating: 0, count: count)
    for i in 0..<count {
        let phase = 2 * .pi * 220.0 * Float(i) / sampleRate
        out[i] = sin(phase) * amplitude
    }
    return out
}

private let silence = [Float](repeating: 0, count: 1024)

// MARK: - Test 1: First-frame deviation is 0, not 2 × energy

@Test
func stemAnalyzer_firstFrameAfterInit_deviationsAreZero() {
    let analyzer = StemAnalyzer(sampleRate: 44100)
    let stems = [
        sineWindow(amplitude: 0.5),  // vocals — non-zero energy
        sineWindow(amplitude: 0.5),  // drums  — non-zero energy
        sineWindow(amplitude: 0.5),  // bass   — non-zero energy
        sineWindow(amplitude: 0.5)   // other  — non-zero energy
    ]
    let features = analyzer.analyze(stemWaveforms: stems, fps: 60)

    // Pre-SAR.1 these would have been ~2 × stemEnergy (10+ for amplitude=0.5
    // input at low-bass band weighting). Post-SAR.1 they must be exactly 0:
    // the seed makes runningAvg = energy on this frame, so (energy - runningAvg)
    // is exactly 0, regardless of energy magnitude.
    #expect(features.vocalsEnergyDev == 0.0,
            "first-frame vocalsEnergyDev must be 0 (got \(features.vocalsEnergyDev))")
    #expect(features.drumsEnergyDev == 0.0,
            "first-frame drumsEnergyDev must be 0 (got \(features.drumsEnergyDev))")
    #expect(features.bassEnergyDev == 0.0,
            "first-frame bassEnergyDev must be 0 (got \(features.bassEnergyDev))")
    #expect(features.otherEnergyDev == 0.0,
            "first-frame otherEnergyDev must be 0 (got \(features.otherEnergyDev))")

    // Same contract on the signed deviation. With seeded runningAvg = energy,
    // (energy - runningAvg) is exactly 0 across both directions.
    #expect(features.vocalsEnergyRel == 0.0,
            "first-frame vocalsEnergyRel must be 0 (got \(features.vocalsEnergyRel))")
    #expect(features.drumsEnergyRel == 0.0,
            "first-frame drumsEnergyRel must be 0 (got \(features.drumsEnergyRel))")
    #expect(features.bassEnergyRel == 0.0,
            "first-frame bassEnergyRel must be 0 (got \(features.bassEnergyRel))")
    #expect(features.otherEnergyRel == 0.0,
            "first-frame otherEnergyRel must be 0 (got \(features.otherEnergyRel))")
}

// MARK: - Test 2: Subsequent frames respond to energy changes and stay bounded

@Test
func stemAnalyzer_steadyState_deviationsStayBounded() {
    let analyzer = StemAnalyzer(sampleRate: 44100)
    let stems = [
        sineWindow(amplitude: 0.5),
        sineWindow(amplitude: 0.5),
        sineWindow(amplitude: 0.5),
        sineWindow(amplitude: 0.5)
    ]

    // Run the same waveform for 30 frames. With seeded running averages,
    // deviation must stay within the declared `[0, 1]` ceiling even while the
    // BandEnergyProcessor's internal AGC is settling (which shifts per-band
    // weighting and thus total energy for a few frames). The pre-SAR.1 path
    // emitted 20–38× over the ceiling on the first frame alone.
    var maxAbsDev: Float = 0
    for _ in 0..<30 {
        let features = analyzer.analyze(stemWaveforms: stems, fps: 60)
        let values: [Float] = [
            features.vocalsEnergyDev, features.drumsEnergyDev,
            features.bassEnergyDev, features.otherEnergyDev
        ]
        for value in values {
            #expect(value.isFinite, "deviation must be finite (got \(value))")
            #expect(value >= 0 && value <= 1.0,
                    "deviation must stay in [0, 1] on a steady sine (got \(value))")
            maxAbsDev = max(maxAbsDev, value)
        }
    }
    // Sanity: the pre-SAR.1 first-frame alone produced 20+. A 30-frame max under
    // 1.0 is a 20× margin against that failure mode — relaxed assertion that
    // tolerates AGC settling on synthetic single-tone input.
    #expect(maxAbsDev < 1.0,
            "30-frame max deviation must stay within ceiling on unchanging input (got \(maxAbsDev))")
}

// MARK: - Test 3: Reset re-arms the seeding

@Test
func stemAnalyzer_resetReArmsSeeding() {
    let analyzer = StemAnalyzer(sampleRate: 44100)
    let stems05 = [
        sineWindow(amplitude: 0.5),
        sineWindow(amplitude: 0.5),
        sineWindow(amplitude: 0.5),
        sineWindow(amplitude: 0.5)
    ]
    let stems08 = [
        sineWindow(amplitude: 0.8),
        sineWindow(amplitude: 0.8),
        sineWindow(amplitude: 0.8),
        sineWindow(amplitude: 0.8)
    ]

    // Warm up at amplitude 0.5 — first frame seeds the running averages.
    for _ in 0..<10 {
        _ = analyzer.analyze(stemWaveforms: stems05, fps: 60)
    }

    // Reset clears running averages back to sentinel zero.
    analyzer.reset()

    // First frame after reset at a DIFFERENT amplitude must still produce
    // zero deviation — the seed re-fires from the new energy level. If
    // running averages survived the reset, deviation would be ~2 × (E08 − E05).
    let features = analyzer.analyze(stemWaveforms: stems08, fps: 60)
    #expect(features.vocalsEnergyDev == 0.0,
            "post-reset vocalsEnergyDev must be 0 (got \(features.vocalsEnergyDev))")
    #expect(features.drumsEnergyDev == 0.0,
            "post-reset drumsEnergyDev must be 0 (got \(features.drumsEnergyDev))")
    #expect(features.bassEnergyDev == 0.0,
            "post-reset bassEnergyDev must be 0 (got \(features.bassEnergyDev))")
    #expect(features.otherEnergyDev == 0.0,
            "post-reset otherEnergyDev must be 0 (got \(features.otherEnergyDev))")
}

// MARK: - Test 4: Per-stem seeding is independent

@Test
func stemAnalyzer_perStemSeedingIsIndependent() {
    let analyzer = StemAnalyzer(sampleRate: 44100)
    let tone = sineWindow(amplitude: 0.5)

    // Frame 1: only vocals has energy. Vocals seeds; the other three stay
    // unseeded (their energy is zero so the seeding guard skips them).
    let frame1: [[Float]] = [tone, silence, silence, silence]
    let f1 = analyzer.analyze(stemWaveforms: frame1, fps: 60)
    #expect(f1.vocalsEnergyDev == 0.0,
            "frame 1 vocalsEnergyDev seeded to 0 (got \(f1.vocalsEnergyDev))")
    // Silent stems also produce 0 deviation trivially because energy == 0.
    #expect(f1.drumsEnergyDev == 0.0,
            "frame 1 drumsEnergyDev on silent stem (got \(f1.drumsEnergyDev))")
    #expect(f1.bassEnergyDev == 0.0,
            "frame 1 bassEnergyDev on silent stem (got \(f1.bassEnergyDev))")
    #expect(f1.otherEnergyDev == 0.0,
            "frame 1 otherEnergyDev on silent stem (got \(f1.otherEnergyDev))")

    // Frame 2: drums/bass/other receive non-zero energy for the first time.
    // Each must seed independently right now and emit deviation 0.
    // Vocals (already seeded last frame) continues at near-zero deviation
    // since its input is unchanged.
    let frame2: [[Float]] = [tone, tone, tone, tone]
    let f2 = analyzer.analyze(stemWaveforms: frame2, fps: 60)
    #expect(f2.drumsEnergyDev == 0.0,
            "frame 2 drumsEnergyDev: drums seed on first non-zero frame (got \(f2.drumsEnergyDev))")
    #expect(f2.bassEnergyDev == 0.0,
            "frame 2 bassEnergyDev: bass seed on first non-zero frame (got \(f2.bassEnergyDev))")
    #expect(f2.otherEnergyDev == 0.0,
            "frame 2 otherEnergyDev: other seed on first non-zero frame (got \(f2.otherEnergyDev))")
    // Vocals stays bounded — same input as frame 1, running average barely
    // changed across one frame of the τ ≈ 10 s EMA.
    #expect(f2.vocalsEnergyDev.isFinite && f2.vocalsEnergyDev >= 0 && f2.vocalsEnergyDev <= 1.0,
            "frame 2 vocalsEnergyDev stays in [0, 1] (got \(f2.vocalsEnergyDev))")
}
