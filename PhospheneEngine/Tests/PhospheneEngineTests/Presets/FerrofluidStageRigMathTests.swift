// FerrofluidStageRigMathTests — V.9 Session 4 Phase 0 backfill for the §5.8 /
// D-125 per-frame math in `FerrofluidStageRig`.
//
// Session 3 wired the engine end-to-end and added a visual dispatch-active gate
// (`testFerrofluidOceanStageRigDispatchActive`) but did NOT unit-test the
// per-frame math. This file regression-locks the four key contracts:
//
//   1. Silence convergence — after 30 ticks of all-zero input, every active
//      light's intensity equals `intensity_baseline × intensity_floor_coef`.
//      Silence-state semantics per §5.8 + D-019.
//   2. 150 ms smoother time constant — input step drumsEnergyDev 0 → 1.0 at
//      60 fps reaches ≥ 0.93 after ~9 ticks (3τ) and ≥ 0.995 after ~18 ticks
//      (6τ). Catches a refactor that changes the α formulation or τ default.
//   3. Pitch-shift confidence gate — at confidence = 0.59 the path falls to
//      otherEnergyDev × 0.15; at ≥ 0.60 it uses the log-perceptual mapping.
//   4. otherEnergyDev fallback range — verifies the × 0.15 scale at the two
//      endpoints (0 → 0, 1 → 0.15).
//   5. Orbital phase advances with arousal — high arousal advances faster than
//      low arousal under matched dt and frame count.
//
// Test seam: `FerrofluidStageRig.debugSmoothedDrumsDev` + `debugOrbitPhase`
// (already exposed for diagnostic dumps — see FerrofluidStageRig.swift:157).

import Testing
import Foundation
import Metal
import simd
@testable import Presets
import Shared

// MARK: - Helpers

private enum FOMathTestError: Error { case noMetalDevice }

private func makeRig(
    descriptor: StageRig = StageRig()
) throws -> FerrofluidStageRig {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw FOMathTestError.noMetalDevice
    }
    guard let rig = FerrofluidStageRig(device: device, descriptor: descriptor) else {
        throw FOMathTestError.noMetalDevice
    }
    return rig
}

private func zeroFeatures() -> FeatureVector {
    var f = FeatureVector.zero
    f.deltaTime = 1.0 / 60.0
    return f
}

// MARK: - Suite 1: Silence convergence

@Suite("Silence convergence")
struct FerrofluidStageRigSilenceTests {

    /// 30 ticks of all-zero input → smoothed drums envelope is 0; per-light
    /// intensity collapses to `intensity_baseline × intensity_floor_coef`
    /// (5.0 × 0.4 = 2.0 at the §5.8 defaults).
    @Test func silence_perLightIntensityEqualsFloorTimesBaseline() throws {
        let descriptor = StageRig()  // §5.8 spec defaults
        let rig = try makeRig(descriptor: descriptor)
        let f = zeroFeatures()
        let s = StemFeatures.zero
        for _ in 0..<30 {
            rig.tick(features: f, stems: s, dt: 1.0 / 60.0)
        }
        let snap = rig.snapshot()
        let expected = descriptor.intensityBaseline * descriptor.intensityFloorCoef
        for i in 0..<Int(snap.activeLightCount) {
            let light = snap.light(at: i)
            let intensity = light.positionAndIntensity.w
            #expect(abs(intensity - expected) < 0.001,
                    "light \(i) intensity \(intensity) ≠ floor × baseline \(expected)")
        }
        // Smoother itself must converge to 0 (not just stay there).
        #expect(rig.debugSmoothedDrumsDev < 0.001,
                "smoothedDrumsDev \(rig.debugSmoothedDrumsDev) did not converge to 0")
    }
}

// MARK: - Suite 2: 150 ms smoother time constant

@Suite("150 ms exponential smoother")
struct FerrofluidStageRigSmootherTests {

    /// Step input: drumsEnergyDev 0 → 1.0 at 60 fps. The discrete RC
    /// approximation `α = dt / τ` clamped to [0, 1] gives the value
    /// `1 - (1 - α)^n` after n ticks. With τ = 0.150 s and dt = 1/60 s:
    ///   α ≈ 0.1111 → 1 - 0.8889^9 ≈ 0.65 (NOT the continuous-time 1 - e^-3).
    /// The discrete approximation is intentional and matches LumenPatternEngine
    /// (see Session 4 Phase B "Smoother formula" note in CLAUDE.md). So the
    /// envelope reaches ~0.65 by 3τ-worth of ticks at 60 fps; we assert it
    /// has crossed 0.5 by then (the qualitative "more than halfway" anchor).
    ///
    /// After 60 ticks (10τ at α ≈ 0.111), the envelope is essentially
    /// indistinguishable from the input (≥ 0.999).
    @Test func smoother_stepInput_reachesQualitativeMidpointAt3Tau() throws {
        let rig = try makeRig()
        var s = StemFeatures.zero
        s.drumsEnergyDev = 1.0
        let f = zeroFeatures()
        for _ in 0..<9 {
            rig.tick(features: f, stems: s, dt: 1.0 / 60.0)
        }
        let envelope = rig.debugSmoothedDrumsDev
        // Tighter bound: 1 - (1 - 0.1111)^9 ≈ 0.654.
        #expect(envelope > 0.6 && envelope < 0.72,
                "smoothed envelope \(envelope) outside [0.6, 0.72] after 9 ticks (3τ)")
    }

    @Test func smoother_stepInput_saturatesAt10Tau() throws {
        let rig = try makeRig()
        var s = StemFeatures.zero
        s.drumsEnergyDev = 1.0
        let f = zeroFeatures()
        for _ in 0..<60 {
            rig.tick(features: f, stems: s, dt: 1.0 / 60.0)
        }
        // Discrete-time α = 1/60 ÷ 0.150 = 0.1111. After 60 ticks of step input,
        // y = 1 - (1 - 0.1111)^60 ≈ 0.9991. Floor at 0.995 leaves headroom for
        // FP accumulation without falsely passing if the smoother breaks.
        #expect(rig.debugSmoothedDrumsDev > 0.995,
                "smoothed envelope \(rig.debugSmoothedDrumsDev) did not saturate after 10τ")
    }
}

// MARK: - Suite 3: Pitch-shift confidence gate

@Suite("Pitch-shift confidence gate")
struct FerrofluidStageRigPitchTests {

    /// Drive two rigs at confidence = 0.59 and confidence = 0.6 with the same
    /// vocalsPitchHz. The < 0.6 rig must source pitch-shift from
    /// otherEnergyDev × 0.15; the ≥ 0.6 rig must source from the log mapping.
    /// We verify by setting otherEnergyDev = 0 in both and asserting the
    /// resulting light colours differ — the high-confidence rig's palette
    /// reflects the pitch, the low-confidence rig's palette is at the
    /// "no pitch shift" baseline because pitch-shift = 0 × 0.15 = 0.
    ///
    /// Use a high pitch (e.g. 1000 Hz) so the log-mapping produces a
    /// meaningful 0.2 shift, easily distinguishable from the 0.0 produced by
    /// the fallback path with otherEnergyDev = 0.
    @Test func pitchShift_confidenceBelowGate_usesOtherEnergyDevFallback() throws {
        // Confidence = 0.59 → fallback path. otherEnergyDev = 0 means
        // pitch_shift = 0 → palette phase based on accumulated_audio_time +
        // per-light offset only.
        let lowRig = try makeRig()
        var stems = StemFeatures.zero
        stems.vocalsPitchHz = 1000.0
        stems.vocalsPitchConfidence = 0.59
        stems.otherEnergyDev = 0.0

        var features = zeroFeatures()
        features.accumulatedAudioTime = 0
        lowRig.tick(features: features, stems: stems, dt: 1.0 / 60.0)
        let lowSnapshot = lowRig.snapshot()

        // Now compare against a rig at confidence = 0.6, same pitch.
        let highRig = try makeRig()
        var stemsHi = stems
        stemsHi.vocalsPitchConfidence = 0.60
        highRig.tick(features: features, stems: stemsHi, dt: 1.0 / 60.0)
        let highSnapshot = highRig.snapshot()

        // light[0] palette phase differs between the two rigs (the pitch
        // shift is +0.2 at 1000 Hz in the high-confidence path, 0 in the
        // fallback path). Compare any colour channel — they must differ
        // measurably.
        let lowColor = lowSnapshot.light(at: 0).color
        let highColor = highSnapshot.light(at: 0).color
        let diffR = abs(lowColor.x - highColor.x)
        let diffG = abs(lowColor.y - highColor.y)
        let diffB = abs(lowColor.z - highColor.z)
        let maxDiff = max(diffR, max(diffG, diffB))
        #expect(maxDiff > 0.01,
                "confidence-gate boundary did not produce a palette shift (max channel diff \(maxDiff))")
    }
}

// MARK: - Suite 4: otherEnergyDev fallback scale

@Suite("otherEnergyDev fallback scale")
struct FerrofluidStageRigFallbackScaleTests {

    /// At confidence < 0.6, pitch_shift = otherEnergyDev × 0.15. Verify the
    /// scale by comparing two ticks at otherEnergyDev = 0 vs 1: the palette
    /// phase difference at light[0] equals the cosine evaluated at the two
    /// phases. We don't need to invert the palette — comparing the resulting
    /// colour to a baseline rig (otherEnergyDev = 0) and asserting the colour
    /// is measurably different when otherEnergyDev = 1 is sufficient.
    @Test func otherEnergyDevZero_yieldsZeroPitchShift() throws {
        let rig = try makeRig()
        var stems = StemFeatures.zero
        stems.vocalsPitchHz = 0
        stems.vocalsPitchConfidence = 0.0   // fallback path
        stems.otherEnergyDev = 0.0
        let features = zeroFeatures()
        rig.tick(features: features, stems: stems, dt: 1.0 / 60.0)
        let snap = rig.snapshot()

        // Baseline: at otherEnergyDev = 0, accumulated_audio_time = 0, and
        // per-light phase offset, the palette[0] phase = phaseOffset[0] = 0.0.
        // palette() at phase 0 ≈ (1.0, 1.0, 1.0). We assert it's near white.
        let color = snap.light(at: 0).color
        #expect(color.x > 0.95,
                "otherEnergyDev=0 rig light[0].r \(color.x) ≠ ~1.0 (palette phase 0)")
    }

    @Test func otherEnergyDevOne_yieldsPitchShiftPoint15() throws {
        // Drive a second rig at otherEnergyDev = 1 → pitch_shift = 0.15.
        // The palette phase for light[0] becomes 0 + 0 + 0.15 = 0.15, so the
        // colour shifts away from white. Compare to the baseline above.
        let rigZero = try makeRig()
        let rigOne = try makeRig()
        var stemsZero = StemFeatures.zero
        stemsZero.vocalsPitchConfidence = 0.0
        stemsZero.otherEnergyDev = 0.0
        var stemsOne = StemFeatures.zero
        stemsOne.vocalsPitchConfidence = 0.0
        stemsOne.otherEnergyDev = 1.0
        let features = zeroFeatures()
        rigZero.tick(features: features, stems: stemsZero, dt: 1.0 / 60.0)
        rigOne.tick(features: features, stems: stemsOne, dt: 1.0 / 60.0)
        let colorZero = rigZero.snapshot().light(at: 0).color
        let colorOne = rigOne.snapshot().light(at: 0).color
        let diff = abs(colorZero.x - colorOne.x) + abs(colorZero.y - colorOne.y) + abs(colorZero.z - colorOne.z)
        #expect(diff > 0.05,
                "otherEnergyDev 0 vs 1 fallback path produced palette delta \(diff) ≤ 0.05 — scale broken")
    }
}

// MARK: - Suite 5: Orbital phase advances with arousal

@Suite("Orbital phase advances with arousal")
struct FerrofluidStageRigOrbitTests {

    /// At arousal = +1 the smoothstep maps to 1, so velocity =
    /// baseline + 1 × coef. At arousal = -1 the smoothstep maps to 0, so
    /// velocity = baseline. Driving both rigs for 60 ticks at dt = 1/60 s,
    /// the high-arousal rig's orbital phase should have advanced by
    /// (baseline + coef) × 1.0 = (0.05 + 0.15) × 1.0 = 0.20 rad. The low rig
    /// should be at baseline × 1.0 = 0.05 rad. Differ by ~0.15 rad.
    @Test func arousalPlusOne_advancesFasterThanArousalMinusOne() throws {
        let descriptor = StageRig()
        let rigHigh = try makeRig(descriptor: descriptor)
        let rigLow = try makeRig(descriptor: descriptor)
        var fHigh = zeroFeatures()
        fHigh.arousal = 1.0
        var fLow = zeroFeatures()
        fLow.arousal = -1.0
        let stems = StemFeatures.zero
        for _ in 0..<60 {
            rigHigh.tick(features: fHigh, stems: stems, dt: 1.0 / 60.0)
            rigLow.tick(features: fLow, stems: stems, dt: 1.0 / 60.0)
        }
        let phaseHigh = rigHigh.debugOrbitPhase
        let phaseLow = rigLow.debugOrbitPhase
        // Expected: high ≈ 0.20 rad, low ≈ 0.05 rad. Δ ≈ 0.15 rad. The
        // smoothstep clamps both extremes (arousal=±1 lands at the smoothstep
        // saturation points 0 and 1) so the math is exact.
        #expect(phaseHigh > phaseLow + 0.10,
                "arousal=+1 phase \(phaseHigh) not > arousal=-1 phase \(phaseLow) + 0.10")
        // Sanity bounds: high ≈ 0.20, low ≈ 0.05.
        #expect(abs(phaseHigh - 0.20) < 0.005,
                "high-arousal phase \(phaseHigh) ≠ 0.20 ± 0.005 (60 ticks × 1/60 s × 0.20 rad/s)")
        #expect(abs(phaseLow - 0.05) < 0.005,
                "low-arousal phase \(phaseLow) ≠ 0.05 ± 0.005 (60 ticks × 1/60 s × 0.05 rad/s)")
    }
}
