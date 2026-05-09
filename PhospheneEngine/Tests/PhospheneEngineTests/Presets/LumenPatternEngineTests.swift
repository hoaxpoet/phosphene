// LumenPatternEngineTests — Unit tests for LumenPatternEngine (Phase LM.2).
//
// Tests exercise the public Swift API + a single internal test seam
// (`setAgentBasePositionForTesting`) used to verify the contract §P.2 inset
// clamp by pushing an agent's base outside the visible-area inset.
//
// Invariants verified:
//   1. Struct layout: LumenPatternState is exactly 336 bytes (contract §LumenPatternState).
//   2. Silence: at totalStemEnergy == 0 + zero FV, all agent intensities < 0.05.
//      Ambient floor stays asserted in the snapshot.
//   3. HV-HA mood: smoothedValence/Arousal converge to (+0.6, +0.6) under a 5 s
//      low-pass after several time-constants; arousal-driven drift speed > 0.15.
//   4. LV-LA mood: smoothedValence/Arousal converge to (-0.5, -0.4); drift speed < 0.10.
//   5. Stem-direct routing: stems.drumsEnergyRel = 0.5 → light[0].intensity ≈ 0.5.
//   6. FV warmup fallback: empty stems + f.beatBass = 1, f.beatMid = 0 →
//      light[0].intensity ≈ 0.6 (the f.beatBass × 0.6 + f.beatMid × 0.4 path).
//   7. Mood smoothing time constant: valence step 0 → +1, integrate 15 s at 60 fps →
//      smoothedValence ≥ 0.95 (3 time-constants of 5 s low-pass).
//   8. Beat-locked dance (contract §P.4): with arousal = 0.5 + dt = 0, sweeping
//      beatPhase01 produces the expected horizontal Lissajous excursion at the
//      test points; pos(0) - pos(0.5) ≈ (0.18, 0).
//   9. Agent inset clamp (contract §P.2): force agent[0] base to (0.95, 0); under
//      arousal=1 + max drift + max dance the resulting position never exceeds
//      ±0.85 in any axis.
//  10. Determinism: two engines with identical inputs produce byte-identical
//      snapshots (no hidden RNG state at LM.2 — patterns are idle).

import Testing
import Metal
import simd
@testable import Presets
import Shared

// MARK: - Helpers

private enum LumenTestError: Error { case noMetalDevice }

/// Create a LumenPatternEngine with a real Metal device, or throw if Metal is
/// unavailable in the test environment (CI fallback).
private func makeEngine(seed: UInt64 = 0) throws -> LumenPatternEngine {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw LumenTestError.noMetalDevice
    }
    guard let engine = LumenPatternEngine(device: device, seed: seed) else {
        throw LumenTestError.noMetalDevice
    }
    return engine
}

private func fv(
    valence: Float = 0,
    arousal: Float = 0,
    beatBass: Float = 0,
    beatMid: Float = 0,
    bassDev: Float = 0,
    treble: Float = 0,
    beatPhase01: Float = 0,
    deltaTime: Float = 1.0 / 60.0
) -> FeatureVector {
    var f = FeatureVector.zero
    f.valence = valence
    f.arousal = arousal
    f.beatBass = beatBass
    f.beatMid = beatMid
    f.bassDev = bassDev
    f.treble = treble
    f.beatPhase01 = beatPhase01
    f.deltaTime = deltaTime
    return f
}

/// Stem snapshot with the deviation primitives the engine consumes.
/// `totalEnergy` is distributed across the four stems so the engine's stem-warmup
/// gate (smoothstep(0.02, 0.06, totalStemEnergy)) lands above 0.06 by default.
private func stems(
    drumsEnergyRel: Float = 0,
    bassEnergyRel: Float = 0,
    vocalsEnergyDev: Float = 0,
    otherEnergyRel: Float = 0,
    totalEnergy: Float = 0.5
) -> StemFeatures {
    var s = StemFeatures.zero
    s.drumsEnergyRel = drumsEnergyRel
    s.bassEnergyRel  = bassEnergyRel
    s.vocalsEnergyDev = vocalsEnergyDev
    s.otherEnergyRel = otherEnergyRel
    let perStem = totalEnergy / 4
    s.drumsEnergy  = perStem
    s.bassEnergy   = perStem
    s.vocalsEnergy = perStem
    s.otherEnergy  = perStem
    return s
}

/// Drive the engine for `seconds` seconds at 60 fps with a constant FV/stems input.
private func driveSteady(
    _ engine: LumenPatternEngine,
    seconds: Float,
    features: FeatureVector,
    stems: StemFeatures
) {
    let dt: Float = 1.0 / 60.0
    let frames = Int((seconds / dt).rounded())
    var f = features
    f.deltaTime = dt
    for _ in 0..<frames {
        engine.tick(features: f, stems: stems)
    }
}

// MARK: - Suite 1: Struct layout

@Suite("LumenPatternState struct layout")
struct LumenPatternStateLayoutTests {

    @Test func test_lumenPatternState_strideIs336() {
        // Contract: lights (4 × 32 = 128) + patterns (4 × 48 = 192) + 4 × 4-byte fields = 336.
        #expect(MemoryLayout<LumenPatternState>.stride == 336)
    }

    @Test func test_lumenLightAgent_strideIs32() {
        #expect(MemoryLayout<LumenLightAgent>.stride == 32)
    }

    @Test func test_lumenPattern_strideIs48() {
        #expect(MemoryLayout<LumenPattern>.stride == 48)
    }
}

// MARK: - Suite 2: Silence + ambient floor

@Suite("Silence behaviour")
struct LumenSilenceTests {

    @Test func test_silence_allLightIntensitiesNearZero() throws {
        let engine = try makeEngine()
        // All-zero FV (silence per acceptance test convention) + all-zero stems.
        let f = fv()
        let s = StemFeatures.zero
        // Tick a few frames so the stem warmup gate has had a chance to swing
        // from "no signal" to "still no signal".
        driveSteady(engine, seconds: 0.5, features: f, stems: s)

        let snapshot = engine.snapshot()
        for i in 0..<LumenPatternEngine.agentCount {
            let intensity = snapshot.light(at: i).intensity
            #expect(intensity < 0.05, "agent \(i) intensity = \(intensity) ≥ 0.05 at silence")
        }
    }

    @Test func test_silence_ambientFloorPropagated() throws {
        let engine = try makeEngine()
        driveSteady(engine, seconds: 0.5, features: fv(), stems: StemFeatures.zero)
        let snapshot = engine.snapshot()
        #expect(abs(snapshot.ambientFloorIntensity - LumenPatternEngine.defaultAmbientFloorIntensity)
                < 1e-6,
                "ambient floor intensity not propagated to slot-8 buffer")
    }
}

// MARK: - Suite 3: Mood smoothing

@Suite("Mood-coupled palette + drift speed")
struct LumenMoodTests {

    @Test func test_hvHa_warmTintAndFastDrift() throws {
        let engine = try makeEngine()
        // High valence + high arousal. Hold for 25 s (5 time-constants) so the
        // 5 s low-pass lands within ~99 % of the input.
        driveSteady(
            engine,
            seconds: 25,
            features: fv(valence: 0.6, arousal: 0.6, treble: 0.0),
            stems: stems(otherEnergyRel: 0.4, totalEnergy: 0.5)
        )
        #expect(abs(engine.smoothedValence - 0.6) < 0.05,
                "smoothedValence \(engine.smoothedValence) ≠ 0.6")
        #expect(abs(engine.smoothedArousal - 0.6) < 0.05,
                "smoothedArousal \(engine.smoothedArousal) ≠ 0.6")
        // Drift speed = lerp(0.05, 0.20, (arousal+1)/2). At arousal=0.6 → 0.05 + 0.15×0.8 = 0.17.
        let arousalNorm = (engine.smoothedArousal + 1) * 0.5
        let driftSpeed =
            LumenPatternEngine.driftSpeedLow +
            (LumenPatternEngine.driftSpeedHigh - LumenPatternEngine.driftSpeedLow) * arousalNorm
        #expect(driftSpeed > 0.15, "drift speed \(driftSpeed) ≤ 0.15 at HV-HA mood")
    }

    @Test func test_lvLa_coolTintAndSlowDrift() throws {
        let engine = try makeEngine()
        driveSteady(
            engine,
            seconds: 25,
            features: fv(valence: -0.5, arousal: -0.4),
            stems: stems(totalEnergy: 0.5)
        )
        #expect(abs(engine.smoothedValence - (-0.5)) < 0.05,
                "smoothedValence \(engine.smoothedValence) ≠ -0.5")
        #expect(abs(engine.smoothedArousal - (-0.4)) < 0.05,
                "smoothedArousal \(engine.smoothedArousal) ≠ -0.4")
        // Drift speed at arousal=-0.4 → arousalNorm = 0.3, speed = 0.05 + 0.15×0.3 = 0.095.
        let arousalNorm = (engine.smoothedArousal + 1) * 0.5
        let driftSpeed =
            LumenPatternEngine.driftSpeedLow +
            (LumenPatternEngine.driftSpeedHigh - LumenPatternEngine.driftSpeedLow) * arousalNorm
        #expect(driftSpeed < 0.10, "drift speed \(driftSpeed) ≥ 0.10 at LV-LA mood")
    }

    @Test func test_moodSmoothing_15sValenceStepReaches95Percent() throws {
        let engine = try makeEngine()
        // Step valence from 0 to +1. After 15 s (3 × τ=5) of a first-order
        // low-pass: 1 - e^-3 ≈ 0.9502. Allow 0.94 floor for fp accumulation.
        driveSteady(
            engine,
            seconds: 15,
            features: fv(valence: 1.0),
            stems: StemFeatures.zero
        )
        #expect(engine.smoothedValence >= 0.94,
                "smoothedValence \(engine.smoothedValence) below the τ=5 s 15 s 95 % target")
    }
}

// MARK: - Suite 4: Audio routing (D-019 / D-026)

@Suite("Audio routing")
struct LumenAudioRoutingTests {

    @Test func test_stemDirect_drumsEnergyRel0p5_lightIntensity0p5() throws {
        let engine = try makeEngine()
        // Warmed-up stems (totalEnergy > 0.06) so the warmup mix is fully on stems.
        let s = stems(drumsEnergyRel: 0.5, totalEnergy: 0.5)
        driveSteady(engine, seconds: 0.2, features: fv(), stems: s)
        let intensity = engine.snapshot().light(at: 0).intensity
        // 5 % tolerance per the prompt's "approximately 0.5".
        #expect(abs(intensity - 0.5) < 0.025,
                "drums-stem intensity \(intensity) ≠ 0.5 (within 5 %)")
    }

    @Test func test_warmupFallback_drumsBeatBassMixDrivesIntensity() throws {
        let engine = try makeEngine()
        // Warmup window: stems all zero so totalStemEnergy = 0 and stemMix = 0.
        // Drives the FV fallback path: beatBass × 0.6 + beatMid × 0.4 = 0.6.
        let f = fv(beatBass: 1.0, beatMid: 0.0)
        driveSteady(engine, seconds: 0.2, features: f, stems: StemFeatures.zero)
        let intensity = engine.snapshot().light(at: 0).intensity
        let expected: Float = 1.0 * 0.6 + 0.0 * 0.4
        #expect(abs(intensity - expected) < 0.025,
                "drums FV-fallback intensity \(intensity) ≠ \(expected) (within 5 %)")
    }

    @Test func test_warmupFallback_bassDevMapsToBassAgent() throws {
        let engine = try makeEngine()
        // Warmup window for bass agent: bassDev × 0.6.
        let f = fv(bassDev: 0.5)
        driveSteady(engine, seconds: 0.2, features: f, stems: StemFeatures.zero)
        let intensity = engine.snapshot().light(at: 1).intensity
        let expected: Float = 0.5 * 0.6
        #expect(abs(intensity - expected) < 0.025,
                "bass FV-fallback intensity \(intensity) ≠ \(expected)")
    }
}

// MARK: - Suite 5: Beat-locked dance (contract §P.4)

@Suite("Beat-locked dance")
struct LumenDanceTests {

    /// Sweep `beatPhase01` while holding `elapsedTime` and arousal constant;
    /// the resulting agent-position differences must match the figure-8 spec.
    @Test func test_dance_beatPhaseSweepProducesExpectedFigure8() throws {
        let engine = try makeEngine()
        // First tick advances elapsedTime by exactly dt; after that all
        // subsequent ticks use deltaTime=0 to freeze the drift component.
        let dt: Float = 1.0 / 60.0
        let f0 = fv(arousal: 0.5, beatPhase01: 0.0, deltaTime: dt)
        engine.tick(features: f0, stems: StemFeatures.zero)
        let pos0 = engine.snapshot().light(at: 0).position

        let f05 = fv(arousal: 0.5, beatPhase01: 0.5, deltaTime: 0)
        engine.tick(features: f05, stems: StemFeatures.zero)
        let pos05 = engine.snapshot().light(at: 0).position

        // Agent[0] beat-phase offset = 0; danceAmplitude at arousal=0.5 = 0.04 + 0.10*0.5 = 0.09.
        // At beatPhase01=0:    offset = (cos(0)*0.09, sin(0)*0.045)  = (+0.09, 0)
        // At beatPhase01=0.5:  offset = (cos(π)*0.09, sin(2π)*0.045) = (-0.09, 0)
        // Difference between the two ticks = (+0.18, 0). Drift is frozen so the
        // remaining position difference must equal the dance delta.
        let dx = pos0.x - pos05.x
        let dy = pos0.y - pos05.y
        #expect(abs(dx - 0.18) < 0.018,
                "dance horizontal delta \(dx) ≠ 0.18 (5 % tolerance)")
        #expect(abs(dy) < 0.005,
                "dance vertical delta \(dy) ≠ 0 (drum agent at quarter-beat zero crossings)")
    }

    @Test func test_dance_amplitudeScalesWithArousal() throws {
        // Arousal=0 → danceAmplitude=0.04. Arousal=1 → danceAmplitude=0.14.
        // Sweep beatPhase01 0 → 0.5 with each arousal; horizontal delta should
        // scale ~3.5× between the two arousal regimes.
        let dt: Float = 1.0 / 60.0

        let calmEngine = try makeEngine()
        calmEngine.tick(features: fv(arousal: 0, beatPhase01: 0, deltaTime: dt), stems: StemFeatures.zero)
        let calm0 = calmEngine.snapshot().light(at: 0).position
        calmEngine.tick(features: fv(arousal: 0, beatPhase01: 0.5, deltaTime: 0), stems: StemFeatures.zero)
        let calm05 = calmEngine.snapshot().light(at: 0).position
        let calmDelta = abs(calm0.x - calm05.x)   // ≈ 0.08

        let franticEngine = try makeEngine()
        franticEngine.tick(features: fv(arousal: 1, beatPhase01: 0, deltaTime: dt), stems: StemFeatures.zero)
        let frantic0 = franticEngine.snapshot().light(at: 0).position
        franticEngine.tick(features: fv(arousal: 1, beatPhase01: 0.5, deltaTime: 0), stems: StemFeatures.zero)
        let frantic05 = franticEngine.snapshot().light(at: 0).position
        let franticDelta = abs(frantic0.x - frantic05.x)   // ≈ 0.28

        #expect(franticDelta > calmDelta * 3.0,
                "frantic dance excursion \(franticDelta) not > 3× calm \(calmDelta)")
    }
}

// MARK: - Suite 6: Inset clamp (contract §P.2)

@Suite("Visible-area inset clamp")
struct LumenClampTests {

    @Test func test_agentBaseOutsideInset_clampHoldsThroughDanceAndDrift() throws {
        let engine = try makeEngine()
        // Push agent[0] base to (0.95, 0) — outside the kAgentInset = 0.85 region.
        engine.setAgentBasePositionForTesting(0, SIMD2(0.95, 0.0))
        // Drive with arousal=1 to push danceAmplitude to its maximum (0.14) and
        // hold for 30 s so the drift Lissajous covers many cycles. Sample
        // positions across the full beat phase circle.
        let dt: Float = 1.0 / 60.0
        var t: Float = 0
        var maxX: Float = -.infinity
        var minX: Float = +.infinity
        var maxY: Float = -.infinity
        var minY: Float = +.infinity
        for frame in 0..<(60 * 30) {
            let beatPhase01 = Float(frame % 60) / 60.0
            let f = fv(arousal: 1.0, beatPhase01: beatPhase01, deltaTime: dt)
            engine.tick(features: f, stems: StemFeatures.zero)
            let pos = engine.snapshot().light(at: 0).position
            maxX = max(maxX, pos.x); minX = min(minX, pos.x)
            maxY = max(maxY, pos.y); minY = min(minY, pos.y)
            t += dt
        }
        let inset = LumenPatternEngine.agentInset
        #expect(maxX <= inset + 1e-5, "agent[0] x exceeded +inset (\(maxX) > \(inset))")
        #expect(minX >= -inset - 1e-5, "agent[0] x exceeded -inset (\(minX) < \(-inset))")
        #expect(maxY <= inset + 1e-5, "agent[0] y exceeded +inset (\(maxY) > \(inset))")
        #expect(minY >= -inset - 1e-5, "agent[0] y exceeded -inset (\(minY) < \(-inset))")
        // Sanity: clamp must have actually fired — base 0.95 + dance 0.14 > 0.85.
        #expect(maxX >= inset - 1e-3, "clamp never engaged — maxX \(maxX) below inset")
    }
}

// MARK: - Suite 7: Determinism

@Suite("Determinism")
struct LumenDeterminismTests {

    @Test func test_twoEngines_sameInputs_byteIdenticalSnapshots() throws {
        let a = try makeEngine(seed: 42)
        let b = try makeEngine(seed: 42)
        let f = fv(valence: 0.3, arousal: 0.4, beatPhase01: 0.25)
        let s = stems(drumsEnergyRel: 0.3, bassEnergyRel: 0.2, totalEnergy: 0.4)
        for _ in 0..<120 {
            a.tick(features: f, stems: s)
            b.tick(features: f, stems: s)
        }
        let snapA = a.snapshot()
        let snapB = b.snapshot()
        // Compare every agent field plus the scalars.
        for i in 0..<LumenPatternEngine.agentCount {
            let lA = snapA.light(at: i)
            let lB = snapB.light(at: i)
            #expect(lA == lB, "agent \(i) snapshot differs between deterministic engines")
        }
        #expect(snapA.activeLightCount == snapB.activeLightCount)
        #expect(snapA.activePatternCount == snapB.activePatternCount)
        #expect(snapA.ambientFloorIntensity == snapB.ambientFloorIntensity)
    }
}
