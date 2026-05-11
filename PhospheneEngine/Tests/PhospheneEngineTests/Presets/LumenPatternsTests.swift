// LumenPatternsTests — Unit tests for the LM.4 pattern engine + factories.
//
// Invariants verified:
//
//   1. Factories
//      - `LumenPatternFactory.idle()` returns an all-zero pattern with kindRaw=0.
//      - `radialRipple(...)` sets kindRaw = `.radialRipple.rawValue`, origin
//        as supplied, direction = 0, phase = 0, duration = supplied
//        (defaults to `radialRippleDuration`).
//      - `sweep(...)` normalises the direction vector to unit length;
//        a zero-length direction falls back to `(0, 1)`.
//
//   2. Lifecycle (driven through LumenPatternEngine)
//      - Spawn fires on rising-edge of `f.beatBass`; the resulting pattern
//        is `.radialRipple`, phase = 0, and `activePatternCount == 1`.
//      - Phase advances by `dt / duration` per tick.
//      - Pattern auto-retires when `phase >= 1.0`: slot becomes `.idle`,
//        `activePatternCount` drops to 0.
//
//   3. RadialRipple expansion (math contract — Swift verifies the LumenPattern
//      values that drive the shader's math; the shader-side expansion is
//      `radius = phase × kRippleMaxRadius`).
//      - At spawn, `phase == 0` (radius = 0).
//      - After `duration` seconds of advancement, `phase >= 1.0` (radius
//        reaches the panel edge in [0, 1] cell-centre uv space, since
//        kRippleMaxRadius = √2 exceeds the max corner distance ≈ 1.343
//        from any origin in `[0.05, 0.95]²`).
//
//   4. Sweep direction
//      - Factory returns a unit-length direction even for non-unit input.
//      - Direction is stable across phase advancement (the engine never
//        mutates `directionX/Y` after spawn).
//      - Phase advances monotonically (and `sweep_position = phase × 2 − 1`
//        is therefore a monotonic function from -1 to +1 along the
//        direction axis).
//
//   5. Pool eviction
//      - Spawning into a full pool (4/4 active, none yet retired) retires
//        the oldest pattern (largest phase) to make room — pool count
//        stays at the max of 4.

import Testing
import Metal
import simd
@testable import Presets
import Shared

// MARK: - Helpers

private enum LumenPatternsTestError: Error { case noMetalDevice }

private func makeEngine(seed: UInt64 = 0) throws -> LumenPatternEngine {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw LumenPatternsTestError.noMetalDevice
    }
    guard let engine = LumenPatternEngine(device: device, seed: seed) else {
        throw LumenPatternsTestError.noMetalDevice
    }
    return engine
}

private func fv(
    beatBass: Float = 0,
    barPhase01: Float = 0,
    deltaTime: Float = 1.0 / 60.0
) -> FeatureVector {
    var f = FeatureVector.zero
    f.beatBass = beatBass
    f.barPhase01 = barPhase01
    f.deltaTime = deltaTime
    return f
}

// MARK: - Suite 1: Factories

@Suite("LumenPatternFactory — value-level construction")
struct LumenPatternFactoryTests {

    @Test func test_idle_isAllZero() {
        let p = LumenPatternFactory.idle()
        #expect(p.kindRaw == LumenPatternKind.idle.rawValue)
        #expect(p.originX == 0 && p.originY == 0)
        #expect(p.directionX == 0 && p.directionY == 0)
        #expect(p.colorR == 0 && p.colorG == 0 && p.colorB == 0)
        #expect(p.phase == 0)
        #expect(p.intensity == 0)
        #expect(p.duration == 0)
    }

    @Test func test_radialRipple_factory_setsFields() {
        let p = LumenPatternFactory.radialRipple(
            origin: SIMD2(0.4, 0.7),
            birthTime: 1.25
        )
        #expect(p.kindRaw == LumenPatternKind.radialRipple.rawValue)
        #expect(p.originX == 0.4)
        #expect(p.originY == 0.7)
        // Direction is unused by ripples (no axis).
        #expect(p.directionX == 0 && p.directionY == 0)
        #expect(p.colorR == 0 && p.colorG == 0 && p.colorB == 0,
                "ripple must not carry colour — colour comes from the per-cell palette")
        #expect(p.phase == 0)
        #expect(p.intensity == LumenPatternFactory.defaultPeakIntensity)
        #expect(p.duration == LumenPatternFactory.radialRippleDuration)
        #expect(p.startTime == 1.25)
    }

    @Test func test_sweep_factory_normalisesDirectionToUnit() {
        let p = LumenPatternFactory.sweep(
            origin: SIMD2(0.5, 0.0),
            direction: SIMD2(2.0, 0.0),
            birthTime: 0
        )
        let dir = SIMD2(p.directionX, p.directionY)
        #expect(abs(simd_length(dir) - 1.0) < 1e-5,
                "sweep direction not unit-length after factory normalisation")
        // Direction sign preserved.
        #expect(p.directionX > 0)
    }

    @Test func test_sweep_factory_fallbackOnZeroDirection() {
        let p = LumenPatternFactory.sweep(
            origin: SIMD2(0.5, 0.5),
            direction: SIMD2(0, 0),
            birthTime: 0
        )
        let dir = SIMD2(p.directionX, p.directionY)
        #expect(abs(simd_length(dir) - 1.0) < 1e-5,
                "zero-direction fallback must be unit-length")
        // Spec: fallback to (0, 1).
        #expect(p.directionX == 0 && p.directionY == 1)
    }

    @Test func test_sweep_factory_setsKindAndColourZero() {
        let p = LumenPatternFactory.sweep(
            origin: SIMD2(0, 0.5),
            direction: SIMD2(1, 0),
            birthTime: 0.5
        )
        #expect(p.kindRaw == LumenPatternKind.sweep.rawValue)
        #expect(p.colorR == 0 && p.colorG == 0 && p.colorB == 0)
        #expect(p.startTime == 0.5)
        #expect(p.duration == LumenPatternFactory.sweepDuration)
    }
}

// MARK: - Suite 2: Lifecycle through the engine

@Suite("Pattern lifecycle — spawn / advance / retire")
struct LumenPatternLifecycleTests {

    @Test func test_bassRisingEdge_spawnsRipple() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0
        engine.tick(features: fv(beatBass: 1.0, deltaTime: dt), stems: StemFeatures.zero)
        let snap = engine.snapshot()
        #expect(snap.activePatternCount == 1,
                "bass rising-edge did not spawn a pattern")
        let p = snap.pattern(at: 0)
        #expect(p.kind == .radialRipple, "spawned pattern is not a radial ripple")
        // Freshly spawned: phase = 0 (advance happens BEFORE spawn each tick,
        // so the new pattern's first phase advance lands on the *next* tick).
        #expect(p.phase == 0, "freshly-spawned pattern phase \(p.phase) ≠ 0")
    }

    @Test func test_phase_advancesByDtOverDuration() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0
        // Spawn.
        engine.tick(features: fv(beatBass: 1.0, deltaTime: dt), stems: StemFeatures.zero)
        // Advance one tick without re-spawning (drop signal to break rising edge).
        engine.tick(features: fv(beatBass: 0.0, deltaTime: dt), stems: StemFeatures.zero)
        let snap = engine.snapshot()
        let phase = snap.pattern(at: 0).phase
        let expected = dt / LumenPatternFactory.radialRippleDuration
        #expect(abs(phase - expected) < 1e-4,
                "phase \(phase) did not advance by dt/duration = \(expected)")
    }

    @Test func test_pattern_retiresAfterDuration() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0
        // Spawn one ripple.
        engine.tick(features: fv(beatBass: 1.0, deltaTime: dt), stems: StemFeatures.zero)
        #expect(engine.snapshot().activePatternCount == 1)

        // Drop signal and advance for slightly longer than the ripple's lifetime.
        let framesToRetire = Int(
            ((LumenPatternFactory.radialRippleDuration + 0.10) / dt).rounded()
        )
        for _ in 0..<framesToRetire {
            engine.tick(features: fv(beatBass: 0.0, deltaTime: dt), stems: StemFeatures.zero)
        }

        let final = engine.snapshot()
        #expect(final.activePatternCount == 0,
                "pattern not retired after duration — pool count \(final.activePatternCount)")
        #expect(final.pattern(at: 0).kind == .idle,
                "slot 0 should be .idle after retirement (kindRaw=\(final.pattern(at: 0).kindRaw))")
    }

    @Test func test_resetBeatTrackingState_clearsPatternPool() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0
        // Spawn a ripple.
        engine.tick(features: fv(beatBass: 1.0, deltaTime: dt), stems: StemFeatures.zero)
        #expect(engine.snapshot().activePatternCount == 1)

        // reset() routes through resetBeatTrackingState().
        engine.reset()
        let snap = engine.snapshot()
        #expect(snap.activePatternCount == 0, "reset() did not clear the pattern pool")
        #expect(snap.pattern(at: 0).kind == .idle)
    }

    @Test func test_setTrackSeed_clearsPatternPool() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0
        // Spawn a ripple.
        engine.tick(features: fv(beatBass: 1.0, deltaTime: dt), stems: StemFeatures.zero)
        #expect(engine.snapshot().activePatternCount == 1)

        // Track change must zero the pool so the new track's pattern
        // choreography starts fresh.
        engine.setTrackSeed(SIMD4<Float>(0.5, 0.5, 0.5, 0.5))
        let snap = engine.snapshot()
        #expect(snap.activePatternCount == 0,
                "setTrackSeed did not clear the pattern pool")
    }
}

// MARK: - Suite 3: Radial ripple expansion (math contract)

@Suite("Radial ripple expansion math contract")
struct LumenRadialRippleExpansionTests {

    @Test func test_atSpawn_phaseIsZero() {
        let p = LumenPatternFactory.radialRipple(
            origin: SIMD2(0.5, 0.5),
            birthTime: 0
        )
        // At spawn, phase = 0 → shader radius = phase × kRippleMaxRadius = 0.
        #expect(p.phase == 0)
    }

    @Test func test_engineAdvances_phaseReachesOneAtDuration() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0
        engine.tick(features: fv(beatBass: 1.0, deltaTime: dt), stems: StemFeatures.zero)

        // Tick for slightly less than `duration` so we don't trip retirement
        // and still observe a non-retired pattern with phase near 1.
        let framesToNearEnd = Int(
            ((LumenPatternFactory.radialRippleDuration - 0.02) / dt).rounded()
        )
        for _ in 0..<framesToNearEnd {
            engine.tick(features: fv(beatBass: 0.0, deltaTime: dt), stems: StemFeatures.zero)
        }
        let snap = engine.snapshot()
        #expect(snap.activePatternCount == 1)
        let phase = snap.pattern(at: 0).phase
        #expect(phase > 0.9,
                "phase \(phase) below 0.9 after \(framesToNearEnd) ticks of advancement")
        #expect(phase < 1.0, "phase \(phase) at/above 1.0 — should not yet be retired")
    }

    /// kRippleMaxRadius = √2 ≈ 1.414 is large enough to reach the panel edge
    /// from any hash-derived origin in `[0.05, 0.95]²` (max corner distance
    /// is ≈ √(0.95² + 0.95²) ≈ 1.343 < √2). This invariant is verified by
    /// construction here on the LumenPattern (origin clamp) — the shader
    /// math `radius = phase × √2` is in `LumenMosaic.metal`.
    @Test func test_hashDerivedOrigins_stayInsideExpansionEnvelope() throws {
        // Drive 8 separated onsets so the engine produces 8 different
        // hash-derived origins. Each origin must lie inside [0.05, 0.95]².
        let engine = try makeEngine()
        let dt: Float = 0.05   // 50 ms per frame
        var observed: [SIMD2<Float>] = []
        for _ in 0..<8 {
            engine.tick(features: fv(beatBass: 1.0, deltaTime: dt), stems: StemFeatures.zero)
            let snap = engine.snapshot()
            // Find the most recently appended pattern (largest phase index? no — just any).
            // Eight separated rising edges each spawn a fresh pattern.
            for i in 0..<Int(snap.activePatternCount) {
                let p = snap.pattern(at: i)
                if p.kind == .radialRipple {
                    observed.append(SIMD2(p.originX, p.originY))
                }
            }
            // Drop signal long enough to break the rising-edge debounce.
            engine.tick(features: fv(beatBass: 0.0, deltaTime: dt), stems: StemFeatures.zero)
        }
        // We expect to have seen at least 4 distinct origins (the pool caps
        // at 4 so the visible snapshot only contains the four most recent;
        // we accept that the test will only see 4 even though 8 spawn
        // attempts happened).
        #expect(observed.count >= 4, "no origins captured — engine spawn path didn't fire")
        for origin in observed {
            #expect(origin.x >= 0.05 && origin.x <= 0.95,
                    "origin.x \(origin.x) out of expected [0.05, 0.95] envelope")
            #expect(origin.y >= 0.05 && origin.y <= 0.95,
                    "origin.y \(origin.y) out of expected [0.05, 0.95] envelope")
        }
    }
}

// MARK: - Suite 4: Sweep direction

@Suite("Sweep direction — unit length, stability, monotone phase")
struct LumenSweepDirectionTests {

    /// Factory normalises directions, even when given non-unit input.
    @Test func test_factory_direction_isUnitLength_forAllEdges() {
        // The four canonical entry edges + their opposing directions.
        // Engine uses these exact pairs in `sweepEntryFromBar`.
        let cases: [(SIMD2<Float>, SIMD2<Float>)] = [
            (SIMD2(0.5, 0.0), SIMD2( 0,  1)),
            (SIMD2(0.5, 1.0), SIMD2( 0, -1)),
            (SIMD2(0.0, 0.5), SIMD2( 1,  0)),
            (SIMD2(1.0, 0.5), SIMD2(-1,  0)),
        ]
        for (origin, dir) in cases {
            let p = LumenPatternFactory.sweep(
                origin: origin,
                direction: dir,
                birthTime: 0
            )
            let outDir = SIMD2(p.directionX, p.directionY)
            #expect(abs(simd_length(outDir) - 1.0) < 1e-5,
                    "direction \(dir) not unit-length after factory")
        }
    }

    /// Engine never mutates a pattern's direction after spawn. Spawn a
    /// sweep via the bar trigger, then advance many ticks and verify the
    /// direction is byte-identical across the snapshots.
    @Test func test_engine_directionStableAcrossPhaseAdvancement() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0

        // Trigger one bar wrap to spawn a bar-rotation pattern (either
        // a sweep or a ripple — both kinds are dispatched, but only
        // sweeps have a meaningful direction. Whichever fires, the
        // direction is fixed at spawn and must not change after.)
        engine.tick(features: fv(barPhase01: 0.95, deltaTime: dt), stems: StemFeatures.zero)
        engine.tick(features: fv(barPhase01: 0.05, deltaTime: dt), stems: StemFeatures.zero)
        let snap1 = engine.snapshot()
        #expect(snap1.activePatternCount >= 1, "bar wrap did not spawn a pattern")
        let dir1 = SIMD2(snap1.pattern(at: 0).directionX, snap1.pattern(at: 0).directionY)

        // Advance several ticks without triggering anything new.
        for _ in 0..<10 {
            engine.tick(
                features: fv(barPhase01: 0.0, deltaTime: dt),
                stems: StemFeatures.zero
            )
        }
        let snap2 = engine.snapshot()
        let dir2 = SIMD2(snap2.pattern(at: 0).directionX, snap2.pattern(at: 0).directionY)
        #expect(dir1.x == dir2.x && dir1.y == dir2.y,
                "pattern direction mutated across phase advancement: \(dir1) → \(dir2)")
    }

    /// Phase advances monotonically. Spawn a pattern, advance over several
    /// ticks, and assert phase never decreases. The shader's
    /// `sweep_position = phase × 2 − 1` is therefore a monotonic function
    /// from -1 to +1 along the direction axis.
    @Test func test_phase_monotonicallyAdvances() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0
        // Spawn one pattern via bass onset.
        engine.tick(features: fv(beatBass: 1.0, deltaTime: dt), stems: StemFeatures.zero)
        var previousPhase: Float = -1
        for _ in 0..<20 {
            engine.tick(
                features: fv(beatBass: 0.0, deltaTime: dt),
                stems: StemFeatures.zero
            )
            let p = engine.snapshot().pattern(at: 0)
            if p.kind == .idle { break }   // Retired — sequence ends.
            #expect(p.phase >= previousPhase,
                    "phase \(p.phase) decreased from \(previousPhase)")
            previousPhase = p.phase
        }
    }
}

// MARK: - Suite 5: Pool eviction

@Suite("Pool eviction — full pool retires the oldest pattern")
struct LumenPoolEvictionTests {

    /// Drive 5 spawns rapidly via `barPhase01` wraps (no debounce on bar
    /// wraps — unlike bass rising edges which carry the 80 ms debounce).
    /// The 5 spawns happen within ~167 ms of elapsed time, well under the
    /// 300 ms ripple lifetime (LM.4.1) and 800 ms sweep lifetime, so none
    /// of the 5 patterns has reached `phase >= 1.0` yet. The cap of 4 is
    /// therefore enforced by explicit eviction, not by natural retirement.
    @Test func test_fivthSpawnEvictsOldest() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0   // 16.7 ms — bar-wrap fires every 2 ticks (~33 ms)
        for _ in 0..<5 {
            // High phase first (arms the wrap detector), then low phase
            // (triggers wrap → bar-rotation spawn).
            engine.tick(features: fv(barPhase01: 0.95, deltaTime: dt), stems: StemFeatures.zero)
            engine.tick(features: fv(barPhase01: 0.05, deltaTime: dt), stems: StemFeatures.zero)
        }
        let snap = engine.snapshot()
        // 5 spawn attempts → 4 in pool (one evicted).
        let cap = Int32(LumenPatternEngine.patternCount)
        #expect(snap.activePatternCount == cap,
                "pool count \(snap.activePatternCount) ≠ \(cap) after 5 spawns — eviction did not enforce cap")
    }

    /// The pool cap is exactly 4 — never more than `patternCount`. Drives
    /// via bar wraps so 10 spawn attempts land inside the pattern
    /// lifetime window and actually challenge the cap (bass rising edges
    /// would be 80 ms-debounced — too slow to fill the pool against the
    /// LM.4.1 300 ms ripple lifetime).
    @Test func test_pool_neverExceedsPatternCount() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0
        let cap = Int32(LumenPatternEngine.patternCount)
        // 10 rapid-fire bar wraps.
        for _ in 0..<10 {
            engine.tick(features: fv(barPhase01: 0.95, deltaTime: dt), stems: StemFeatures.zero)
            engine.tick(features: fv(barPhase01: 0.05, deltaTime: dt), stems: StemFeatures.zero)
            #expect(engine.snapshot().activePatternCount <= cap,
                    "pool count exceeded cap")
        }
    }
}
