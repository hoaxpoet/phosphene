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
//   2. Lifecycle (driven through LumenPatternEngine — LM.4.3 spawn path)
//      - Spawn fires on rising-edge of `f.barPhase01` wrap (the ONLY
//        spawn trigger at LM.4.3 — the LM.4 per-kick `f.beatBass`
//        spawn was retired); resulting pattern is `.radialRipple` or
//        `.sweep` (mood-weighted), phase = 0, `activePatternCount == 1`.
//      - `f.beatPhase01` wraps DO NOT spawn patterns; they only advance
//        the LM.3.2 cell-dance band counters.
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
    beatPhase01: Float = 0,
    barPhase01: Float = 0,
    deltaTime: Float = 1.0 / 60.0
) -> FeatureVector {
    var f = FeatureVector.zero
    f.beatPhase01 = beatPhase01
    f.barPhase01 = barPhase01
    f.deltaTime = deltaTime
    return f
}

/// Spawn a single bar-rotation pattern via a `barPhase01` wrap. Two ticks:
/// first arms the wrap detector (`barPhase01 = 0.95`), second triggers the
/// wrap (`barPhase01 = 0.05`). This is the LM.4.3 spawn entry point — no
/// per-kick spawn exists anymore.
private func spawnOnePatternViaBarWrap(
    _ engine: LumenPatternEngine,
    dt: Float = 1.0 / 60.0
) {
    engine.tick(features: fv(barPhase01: 0.95, deltaTime: dt), stems: StemFeatures.zero)
    engine.tick(features: fv(barPhase01: 0.05, deltaTime: dt), stems: StemFeatures.zero)
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

    /// LM.4.3: bar wraps are the ONLY pattern-spawn trigger. Per-kick
    /// `beatPhase01` wraps do not spawn anything (they only advance
    /// the band counter for the LM.3.2 cell dance).
    @Test func test_barWrap_spawnsBarRotationPattern() throws {
        let engine = try makeEngine()
        spawnOnePatternViaBarWrap(engine)
        let snap = engine.snapshot()
        #expect(snap.activePatternCount == 1,
                "bar wrap did not spawn a pattern")
        let p = snap.pattern(at: 0)
        // Mood is neutral (smoothedArousal ≈ 0), so the choice is 50/50
        // between ripple and sweep — accept either.
        #expect(p.kind == .radialRipple || p.kind == .sweep,
                "bar-rotation pattern kind \(p.kindRaw) is not ripple or sweep")
        // Freshly spawned: phase = 0.
        #expect(p.phase == 0, "freshly-spawned pattern phase \(p.phase) ≠ 0")
    }

    /// LM.4.3: `beatPhase01` wraps DO NOT spawn patterns — they only
    /// advance the LM.3.2 cell-dance counters. Patterns spawn on bar
    /// wraps only.
    @Test func test_beatPhase01Wrap_doesNotSpawnPattern() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0
        engine.tick(features: fv(beatPhase01: 0.95, deltaTime: dt), stems: StemFeatures.zero)
        engine.tick(features: fv(beatPhase01: 0.05, deltaTime: dt), stems: StemFeatures.zero)
        let snap = engine.snapshot()
        #expect(snap.activePatternCount == 0,
                "beat wrap (without bar wrap) spawned a pattern; only bar wraps should spawn at LM.4.3")
        #expect(snap.bassCounter > 0,
                "beat wrap did not advance bassCounter (LM.3.2 dance broken)")
    }

    @Test func test_phase_advancesByDtOverDuration() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0
        spawnOnePatternViaBarWrap(engine, dt: dt)
        // Spawn is a two-tick sequence; the second spawn-tick already
        // advanced any previously-active pattern by dt before spawning the
        // new one. The new pattern's phase is therefore 0 right after
        // spawn; advance one more tick to get the dt/duration delta.
        let phase0 = engine.snapshot().pattern(at: 0).phase
        let duration0 = engine.snapshot().pattern(at: 0).duration
        engine.tick(features: fv(barPhase01: 0.0, deltaTime: dt), stems: StemFeatures.zero)
        let phase1 = engine.snapshot().pattern(at: 0).phase
        let expected = dt / duration0
        let delta = phase1 - phase0
        #expect(abs(delta - expected) < 1e-4,
                "phase delta \(delta) did not advance by dt/duration = \(expected)")
    }

    @Test func test_pattern_retiresAfterDuration() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0
        spawnOnePatternViaBarWrap(engine, dt: dt)
        #expect(engine.snapshot().activePatternCount == 1)
        // Wait for the longer of the two kinds (sweep is 0.8 s; ripple is 0.6 s).
        let durationToWait = LumenPatternFactory.sweepDuration + 0.10
        let framesToRetire = Int((durationToWait / dt).rounded())
        for _ in 0..<framesToRetire {
            engine.tick(features: fv(barPhase01: 0.0, deltaTime: dt), stems: StemFeatures.zero)
        }
        let final = engine.snapshot()
        #expect(final.activePatternCount == 0,
                "pattern not retired after duration — pool count \(final.activePatternCount)")
        #expect(final.pattern(at: 0).kind == .idle,
                "slot 0 should be .idle after retirement (kindRaw=\(final.pattern(at: 0).kindRaw))")
    }

    @Test func test_resetBeatTrackingState_clearsPatternPool() throws {
        let engine = try makeEngine()
        spawnOnePatternViaBarWrap(engine)
        #expect(engine.snapshot().activePatternCount == 1)
        engine.reset()
        let snap = engine.snapshot()
        #expect(snap.activePatternCount == 0, "reset() did not clear the pattern pool")
        #expect(snap.pattern(at: 0).kind == .idle)
    }

    @Test func test_setTrackSeed_clearsPatternPool() throws {
        let engine = try makeEngine()
        spawnOnePatternViaBarWrap(engine)
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

    @Test func test_engineAdvances_phaseReachesNearOneAtDuration() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0
        spawnOnePatternViaBarWrap(engine, dt: dt)
        let duration = engine.snapshot().pattern(at: 0).duration
        // Tick for slightly less than `duration` so we don't trip retirement
        // and still observe a non-retired pattern with phase near 1.
        let framesToNearEnd = Int(((duration - 0.04) / dt).rounded())
        for _ in 0..<framesToNearEnd {
            engine.tick(features: fv(barPhase01: 0.0, deltaTime: dt), stems: StemFeatures.zero)
        }
        let snap = engine.snapshot()
        #expect(snap.activePatternCount == 1)
        let phase = snap.pattern(at: 0).phase
        #expect(phase > 0.9, "phase \(phase) below 0.9 after \(framesToNearEnd) ticks")
        #expect(phase < 1.0, "phase \(phase) at/above 1.0 — should not yet be retired")
    }

    /// kRippleMaxRadius = √2 ≈ 1.414 is large enough to reach the panel edge
    /// from any hash-derived ripple origin in `[0.05, 0.95]²` (max corner
    /// distance ≈ √(0.95² + 0.95²) ≈ 1.343 < √2). For sweeps, origins are
    /// edge midpoints — also inside [0, 1]². This test verifies origin
    /// values fall in the [0, 1]² envelope (where pattern math is defined).
    @Test func test_hashDerivedOrigins_stayInsideExpansionEnvelope() throws {
        let engine = try makeEngine()
        let dt: Float = 1.0 / 60.0
        var observed: [SIMD2<Float>] = []
        for _ in 0..<8 {
            spawnOnePatternViaBarWrap(engine, dt: dt)
            let snap = engine.snapshot()
            for i in 0..<Int(snap.activePatternCount) {
                let p = snap.pattern(at: i)
                if p.kind == .radialRipple || p.kind == .sweep {
                    observed.append(SIMD2(p.originX, p.originY))
                }
            }
        }
        // We expect to have seen at least 4 patterns in the snapshot (pool
        // caps at 4 — only the four most recent are visible).
        #expect(observed.count >= 4, "no origins captured — engine spawn path didn't fire")
        for origin in observed {
            #expect(origin.x >= 0.0 && origin.x <= 1.0,
                    "origin.x \(origin.x) out of [0, 1] uv envelope")
            #expect(origin.y >= 0.0 && origin.y <= 1.0,
                    "origin.y \(origin.y) out of [0, 1] uv envelope")
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
        spawnOnePatternViaBarWrap(engine, dt: dt)
        var previousPhase: Float = -1
        for _ in 0..<20 {
            engine.tick(
                features: fv(barPhase01: 0.0, deltaTime: dt),
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
