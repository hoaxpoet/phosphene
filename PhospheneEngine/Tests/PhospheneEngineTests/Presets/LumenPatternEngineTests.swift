// LumenPatternEngineTests — Unit tests for LumenPatternEngine (Phase LM.2).
//
// Tests exercise the public Swift API + a single internal test seam
// (`setAgentBasePositionForTesting`) used to verify the contract §P.2 inset
// clamp by pushing an agent's base outside the visible-area inset.
//
// Invariants verified:
//   1. Struct layout: LumenPatternState is exactly 376 bytes (LM.3.2 — added the
//      four band counters bassCounter / midCounter / trebleCounter / barCounter
//      on top of the LM.3 layout).
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
//  11. LM.3.2 band counters: each rising-edge of f.beatBass / f.beatMid /
//      f.beatTreble increments the matching counter exactly once (debounced 80 ms),
//      scaled by `beatStrength = clamp(0.3 + 1.4 × max(bass,mid,treble), 0.3, 1.0)`.
//      barCounter advances on f.barPhase01 wrap (1.0→0.0) or every 4 bass beats
//      when no grid is installed. reset() and setTrackSeed() both zero the counters.

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
    bass: Float = 0,
    mid: Float = 0,
    treble: Float = 0,
    beatBass: Float = 0,
    beatMid: Float = 0,
    beatTreble: Float = 0,
    bassDev: Float = 0,
    beatPhase01: Float = 0,
    barPhase01: Float = 0,
    deltaTime: Float = 1.0 / 60.0
) -> FeatureVector {
    var f = FeatureVector.zero
    f.valence = valence
    f.arousal = arousal
    f.bass = bass
    f.mid = mid
    f.treble = treble
    f.beatBass = beatBass
    f.beatMid = beatMid
    f.beatTreble = beatTreble
    f.bassDev = bassDev
    f.beatPhase01 = beatPhase01
    f.barPhase01 = barPhase01
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

    @Test func test_lumenPatternState_strideIs376() {
        // Contract: lights (4 × 32 = 128) + patterns (4 × 48 = 192) + 14 × 4-byte
        // trailing fields (activeLightCount, activePatternCount, ambientFloorIntensity,
        // smoothedValence, smoothedArousal, pad0, trackPaletteSeed{A,B,C,D},
        // bassCounter, midCounter, trebleCounter, barCounter) = 376.
        // LM.3.2 grew the struct from 360 → 376 bytes (added the four band
        // counters bassCounter/midCounter/trebleCounter/barCounter on top of
        // the LM.3 layout). The RayMarchPipeline.lumenPlaceholderBuffer
        // literal must match — if this test trips, update both this
        // assertion AND the placeholder size in RayMarchPipeline.swift, AND
        // the matching MSL struct in PresetLoader+Preamble.swift.
        #expect(MemoryLayout<LumenPatternState>.stride == 376)
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

    /// LM.3: the `ambientFloorIntensity` field stays on the struct for ABI
    /// continuity but is unused — the silence-floor semantics moved to a
    /// shader-side `kSilenceIntensity` constant (`LumenMosaic.metal`). The
    /// engine writes 0 to keep the field deterministic. If a future
    /// increment finds a use for this field it should make sure both sides
    /// of the GPU contract agree on the new semantics.
    @Test func test_silence_ambientFloorIntensity_isZero_atLM3() throws {
        let engine = try makeEngine()
        driveSteady(engine, seconds: 0.5, features: fv(), stems: StemFeatures.zero)
        let snapshot = engine.snapshot()
        #expect(snapshot.ambientFloorIntensity == 0,
                "ambientFloorIntensity should be zero at LM.3 (silence floor moved to shader)")
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
        #expect(snapA.smoothedValence == snapB.smoothedValence)
        #expect(snapA.smoothedArousal == snapB.smoothedArousal)
    }
}

// MARK: - Suite 8: LM.3 GPU-state contract — smoothed mood + per-track seed

@Suite("LM.3 GPU state — smoothed mood + per-track seed")
struct LumenLM3StateTests {

    /// Smoothed mood values must reach the GPU buffer (the shader needs them
    /// for palette parameter interpolation). Without this, `LumenMosaic.metal`
    /// reads zero mood every frame and the palette stays stuck at the
    /// neutral midpoint.
    @Test func test_smoothedValenceArousal_writtenToSnapshot() throws {
        let engine = try makeEngine()
        // Saturate the 5 s low-pass in one tick by passing dt = 5.0.
        engine.tick(features: fv(valence: 0.6, arousal: 0.4, deltaTime: 5.0),
                    stems: StemFeatures.zero)
        let snap = engine.snapshot()
        #expect(abs(snap.smoothedValence - 0.6) < 0.05,
                "smoothedValence not written to GPU snapshot — got \(snap.smoothedValence)")
        #expect(abs(snap.smoothedArousal - 0.4) < 0.05,
                "smoothedArousal not written to GPU snapshot — got \(snap.smoothedArousal)")
    }

    /// `setTrackSeed(_ seed:)` writes the four perturbation components into
    /// the GPU buffer and clamps each to [-1, +1].
    @Test func test_setTrackSeed_directInjection() throws {
        let engine = try makeEngine()
        engine.setTrackSeed(SIMD4<Float>(0.5, -0.25, 0.75, -0.5))
        let snap = engine.snapshot()
        #expect(snap.trackPaletteSeedA == 0.5)
        #expect(snap.trackPaletteSeedB == -0.25)
        #expect(snap.trackPaletteSeedC == 0.75)
        #expect(snap.trackPaletteSeedD == -0.5)
    }

    /// Out-of-range seed components must clamp to [-1, +1].
    @Test func test_setTrackSeed_clampsToUnitRange() throws {
        let engine = try makeEngine()
        engine.setTrackSeed(SIMD4<Float>(2.0, -3.0, 1.0, -1.0))
        let snap = engine.snapshot()
        #expect(snap.trackPaletteSeedA == 1.0, "trackPaletteSeedA above 1.0 not clamped")
        #expect(snap.trackPaletteSeedB == -1.0, "trackPaletteSeedB below -1.0 not clamped")
        #expect(snap.trackPaletteSeedC == 1.0, "trackPaletteSeedC at boundary changed")
        #expect(snap.trackPaletteSeedD == -1.0, "trackPaletteSeedD at boundary changed")
    }

    /// `setTrackSeed(fromHash:)` derives all four components from the 64-bit
    /// hash deterministically. Same hash → same seed; different hashes →
    /// different seeds (across at least one component).
    @Test func test_setTrackSeedFromHash_deterministic() throws {
        let a = try makeEngine()
        let b = try makeEngine()
        a.setTrackSeed(fromHash: 0xDEAD_BEEF_CAFE_F00D)
        b.setTrackSeed(fromHash: 0xDEAD_BEEF_CAFE_F00D)
        #expect(a.snapshot().trackPaletteSeedA == b.snapshot().trackPaletteSeedA)
        #expect(a.snapshot().trackPaletteSeedB == b.snapshot().trackPaletteSeedB)
        #expect(a.snapshot().trackPaletteSeedC == b.snapshot().trackPaletteSeedC)
        #expect(a.snapshot().trackPaletteSeedD == b.snapshot().trackPaletteSeedD)
    }

    @Test func test_setTrackSeedFromHash_distinguishesHashes() throws {
        let a = try makeEngine()
        let b = try makeEngine()
        a.setTrackSeed(fromHash: 0xDEAD_BEEF_CAFE_F00D)
        b.setTrackSeed(fromHash: 0x1234_5678_9ABC_DEF0)
        let snapA = a.snapshot()
        let snapB = b.snapshot()
        let differs =
            snapA.trackPaletteSeedA != snapB.trackPaletteSeedA ||
            snapA.trackPaletteSeedB != snapB.trackPaletteSeedB ||
            snapA.trackPaletteSeedC != snapB.trackPaletteSeedC ||
            snapA.trackPaletteSeedD != snapB.trackPaletteSeedD
        #expect(differs, "different hashes produced byte-identical seeds")
    }

    /// `tick(...)` must NOT clear the per-track seed. The seed is set on
    /// track change and must persist across all subsequent frames in that
    /// track. If a future refactor accidentally zeroes the seed in `_tick`,
    /// every Lumen Mosaic track would look the same.
    @Test func test_tickDoesNotClearTrackSeed() throws {
        let engine = try makeEngine()
        engine.setTrackSeed(SIMD4<Float>(0.7, 0.3, -0.5, 0.9))
        for _ in 0..<60 {
            engine.tick(features: fv(deltaTime: 1.0 / 60.0), stems: StemFeatures.zero)
        }
        let snap = engine.snapshot()
        #expect(snap.trackPaletteSeedA == 0.7, "tick() cleared trackPaletteSeedA")
        #expect(snap.trackPaletteSeedB == 0.3, "tick() cleared trackPaletteSeedB")
        #expect(snap.trackPaletteSeedC == -0.5, "tick() cleared trackPaletteSeedC")
        #expect(snap.trackPaletteSeedD == 0.9, "tick() cleared trackPaletteSeedD")
    }
}

// MARK: - Suite 9: LM.4.3 — BeatGrid-driven band counters

/// **LM.4.3 supersedes LM.3.2's FFT-band counter triggers.** The band
/// counters now advance on `f.beatPhase01` wrap (each grid beat) and
/// `f.barPhase01` wrap (each grid downbeat). The three rates are:
/// `bassCounter` every grid beat, `midCounter` every 2 grid beats,
/// `trebleCounter` every 4 grid beats. Each advance is uniform +1.0
/// (no energy modulation — the LM.3.2 `beatStrength` scaling is
/// retired). FFT-band rising edges (`f.beatBass / beatMid / beatTreble`)
/// no longer participate.
@Suite("LM.4.3 band counters — beatPhase01 wrap drives all four")
struct LumenLM43CounterTests {

    /// Helper: drive one `f.beatPhase01` wrap (high → low).
    private func driveBeatWrap(_ engine: LumenPatternEngine, dt: Float = 1.0 / 60.0) {
        engine.tick(features: fv(beatPhase01: 0.95, deltaTime: dt), stems: StemFeatures.zero)
        engine.tick(features: fv(beatPhase01: 0.05, deltaTime: dt), stems: StemFeatures.zero)
    }

    /// Helper: drive one `f.barPhase01` wrap (high → low).
    private func driveBarWrap(_ engine: LumenPatternEngine, dt: Float = 1.0 / 60.0) {
        engine.tick(features: fv(barPhase01: 0.95, deltaTime: dt), stems: StemFeatures.zero)
        engine.tick(features: fv(barPhase01: 0.05, deltaTime: dt), stems: StemFeatures.zero)
    }

    /// A single `f.beatPhase01` wrap increments `bassCounter` by exactly 1.0.
    @Test func test_beatPhase01Wrap_incrementsBassCounterByOne() throws {
        let engine = try makeEngine()
        let before = engine.snapshot().bassCounter
        driveBeatWrap(engine)
        let after = engine.snapshot().bassCounter
        #expect(after == before + 1.0,
                "bassCounter \(after) ≠ \(before) + 1.0 on beatPhase01 wrap")
    }

    /// `f.beatPhase01` held high (no wrap) does NOT advance any counter.
    @Test func test_beatPhase01HeldHigh_doesNotIncrement() throws {
        let engine = try makeEngine()
        engine.tick(features: fv(beatPhase01: 0.95), stems: StemFeatures.zero)
        engine.tick(features: fv(beatPhase01: 0.95), stems: StemFeatures.zero)
        engine.tick(features: fv(beatPhase01: 0.95), stems: StemFeatures.zero)
        let snap = engine.snapshot()
        #expect(snap.bassCounter == 0,
                "bassCounter advanced while signal was held above threshold")
    }

    /// `midCounter` advances every 2 grid beats; `trebleCounter` every 4.
    @Test func test_midAndTrebleTickAtSubdividedRates() throws {
        let engine = try makeEngine()
        // 4 beat wraps in a row.
        for _ in 0..<4 {
            driveBeatWrap(engine)
        }
        let snap = engine.snapshot()
        #expect(snap.bassCounter == 4.0,
                "bassCounter \(snap.bassCounter) ≠ 4 after 4 beat wraps")
        #expect(snap.midCounter == 2.0,
                "midCounter \(snap.midCounter) ≠ 2 after 4 beat wraps (expected every-2 cadence)")
        #expect(snap.trebleCounter == 1.0,
                "trebleCounter \(snap.trebleCounter) ≠ 1 after 4 beat wraps (expected every-4 cadence)")
    }

    /// `f.barPhase01` wrap increments `barCounter` by 1.0.
    @Test func test_barPhase01Wrap_incrementsBarCounter() throws {
        let engine = try makeEngine()
        let before = engine.snapshot().barCounter
        driveBarWrap(engine)
        let after = engine.snapshot().barCounter
        #expect(after == before + 1.0,
                "barCounter \(after) ≠ \(before) + 1.0 on barPhase01 wrap")
    }

    /// LM.4.3: no FFT fallback. `barPhase01` held at 0 forever (no grid)
    /// must NOT advance `barCounter` from any combination of FFT inputs.
    /// The LM.3.2 "every 4 bass beats" fallback was retired with the
    /// rest of the FFT trigger path.
    @Test func test_noGridSignal_noBarCounterAdvance() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0
        // Drive 8 grid beats but no bar wrap.
        for _ in 0..<8 {
            driveBeatWrap(engine, dt: dt)
        }
        let snap = engine.snapshot()
        #expect(snap.bassCounter == 8.0,
                "bassCounter should have advanced 8 times")
        #expect(snap.barCounter == 0,
                "barCounter \(snap.barCounter) ≠ 0 — LM.4.3 should have NO bar fallback")
    }

    /// `f.beatBass` (FFT) no longer participates in any counter. Drive a
    /// classic LM.3.2 rising edge with no grid signal — nothing must advance.
    @Test func test_fftBeatBass_aloneDoesNotAdvanceAnyCounter() throws {
        let engine = try makeEngine()
        var f = FeatureVector.zero
        f.beatBass = 1.0   // FFT rising edge
        f.deltaTime = 1.0 / 60.0
        engine.tick(features: f, stems: StemFeatures.zero)
        let snap = engine.snapshot()
        #expect(snap.bassCounter == 0,
                "LM.4.3: FFT beatBass must not advance bassCounter")
        #expect(snap.midCounter == 0)
        #expect(snap.trebleCounter == 0)
        #expect(snap.barCounter == 0)
    }

    /// `reset()` zeroes all four band counters and the phase-subdivision state.
    @Test func test_reset_zerosBandCounters() throws {
        let engine = try makeEngine()
        for _ in 0..<3 { driveBeatWrap(engine) }
        driveBarWrap(engine)
        let beforeReset = engine.snapshot()
        #expect(beforeReset.bassCounter > 0)
        #expect(beforeReset.barCounter > 0)

        engine.reset()
        let afterReset = engine.snapshot()
        #expect(afterReset.bassCounter == 0, "reset() did not zero bassCounter")
        #expect(afterReset.midCounter == 0, "reset() did not zero midCounter")
        #expect(afterReset.trebleCounter == 0, "reset() did not zero trebleCounter")
        #expect(afterReset.barCounter == 0, "reset() did not zero barCounter")
    }

    /// `setTrackSeed(_:)` zeroes all four band counters (track change).
    /// Without this, an old track's high counter values would carry into
    /// the new track's first beat and the new track's cells would jump
    /// straight to a far-off palette index.
    @Test func test_setTrackSeed_zerosBandCounters() throws {
        let engine = try makeEngine()
        for _ in 0..<3 { driveBeatWrap(engine) }
        let before = engine.snapshot()
        #expect(before.bassCounter > 0,
                "bass counter \(before.bassCounter) did not advance — test setup invalid")

        engine.setTrackSeed(SIMD4<Float>(0.5, 0.5, 0.5, 0.5))
        let after = engine.snapshot()
        #expect(after.bassCounter == 0, "setTrackSeed did not zero bassCounter")
        #expect(after.midCounter == 0, "setTrackSeed did not zero midCounter")
        #expect(after.trebleCounter == 0, "setTrackSeed did not zero trebleCounter")
        #expect(after.barCounter == 0, "setTrackSeed did not zero barCounter")
        // Seeds were just set — verify those persisted.
        #expect(after.trackPaletteSeedA == 0.5,
                "setTrackSeed did not persist the seed it was passed")
    }
}
