// LumenPaletteSpectrumTests — Contract regression for LM.4.7 (curated
// 18-palette library + per-song mood-biased selection) + LM.6 (cell-depth
// gradient + hot-spot) + LM.9 pale-tone-share gate (D-LM-cream-rescission).
//
// Mirrors the post-LM.4.7 `lm_cell_palette` in Swift and asserts:
//   1. Palette membership — every produced cell colour is byte-equal to
//      one of the active palette's 12 entries.
//   2. Per-song selection determinism — same (mood, recentIndices,
//      trackSeed) → same drawn index.
//   3. Anti-repeat — selectPalette never returns any palette in the
//      `recentPaletteIndices` set, validated across a window-sized
//      grid sweep (D-LM-palette-library 2026-05-18 amendment widened
//      the window from N=1 to N=3).
//   4. Mood-weighted distribution shape — relative ordering of warm /
//      cool / dark / bright palettes matches the README quadrant
//      groupings under high-VA and low-VA moods.
//   5. Pale-tone-share gate (LM.9) — for each of the 18 palettes, the
//      sampled cell pale-share is ≤ 0.30 (`min(R,G,B) > 0.65` predicate).
//      Cathedral Lights is the calibration palette (~16.7 % nominal).
//   6. Track-change reproducibility — a scripted (trackSeed × mood)
//      sequence with anti-repeat applied produces a reproducible
//      sequence of drawn palette indices. The window-size policy
//      (`kAntiRepeatWindow = 3`) is enforced — no palette repeats
//      within any 3-track sliding window.
//
// LM.6 cell-depth gradient + hot-spot tests are preserved verbatim
// (the LM.6 albedo modulation block in `sceneMaterial` is unchanged
// by LM.4.7). The LM.7-era `test_achromaticAlignedSeed_doesNotWash`
// test is removed — the failure mode it locked cannot occur on the
// palette-table path (cells sample from a curated 12-entry table that
// by construction avoids the achromatic-axis wash).

import Testing
import simd
@testable import Presets
import Shared

// MARK: - Constants mirrored from LumenMosaic.metal

private enum LMPalette {
    static let bassTeamCutoff: UInt32        = 30
    static let midTeamCutoff: UInt32         = 65
    static let trebleTeamCutoff: UInt32      = 90
    static let sectionBeatLength: Float      = 64.0

    // LM.6 — cell-depth gradient + hot-spot. Mirror the .metal constants.
    static let cellEdgeDarkness: Float       = 0.55
    static let depthGradientFalloff: Float   = 1.0
    static let hotSpotRadius: Float          = 0.15
    static let hotSpotShape: Float           = 4.0
    static let hotSpotIntensity: Float       = 0.30

    // LM.9 — pale-tone-share gate (D-LM-cream-rescission / §12.7).
    static let palePredicateThreshold: Float = 0.65
    static let palePanelShareCeiling: Float  = 0.30
}

// MARK: - Shader algorithm mirrored in Swift

private func lmHashU32(_ input: UInt32) -> UInt32 {
    var x = input
    x ^= 61
    x ^= (x >> 16)
    x = x &* 0x7feb352d
    x ^= (x >> 15)
    x = x &* 0x846ca68b
    x ^= (x >> 16)
    return x
}

private func lmTrackSeedHash(seedA: Float, seedB: Float, seedC: Float, seedD: Float) -> UInt32 {
    let a = UInt32((seedA * 0.5 + 0.5) * 65535.0)
    let b = UInt32((seedB * 0.5 + 0.5) * 65535.0)
    let c = UInt32((seedC * 0.5 + 0.5) * 65535.0)
    let d = UInt32((seedD * 0.5 + 0.5) * 65535.0)
    return lmHashU32((a & 0xFF) | ((b & 0xFF) << 8) | ((c & 0xFF) << 16) | ((d & 0xFF) << 24))
}

/// Inverse of `LumenMosaicPaletteLibrary.srgbToLinear` — convert one
/// linear-RGB channel back to sRGB for the LM.9 pale-tone-share gate.
/// The pale predicate is defined against the perceptually-normalised
/// (sRGB-encoded) representation of the colour — the form the eye sees
/// on screen and the form the README calibration math uses (F2DEAC has
/// sRGB min channel 0.675, which is what classifies it as pale).
private func lmLinearToSRGB(_ x: Float) -> Float {
    let c = max(0, min(1, x))
    if c <= 0.0031308 { return c * 12.92 }
    return 1.055 * powf(c, 1 / 2.4) - 0.055
}

private func lmPeriod(cellHash: UInt32) -> Float {
    let bucket = (cellHash >> 8) & 0x7
    if bucket >= 7 { return 8 }
    if bucket >= 5 { return 4 }
    if bucket >= 3 { return 2 }
    return 1
}

private func lmTeamCounter(
    cellHash: UInt32,
    bass: Float, mid: Float, treble: Float
) -> Float {
    let bucket = cellHash % 100
    if bucket < LMPalette.bassTeamCutoff   { return bass }
    if bucket < LMPalette.midTeamCutoff    { return mid }
    if bucket < LMPalette.trebleTeamCutoff { return treble }
    return 0 // static team
}

/// Mirror of `lm_cell_palette` (LM.4.7) — palette-table lookup.
/// `palette` is the 12-entry per-song colour table (linear RGB).
private func lmCellPaletteRGB(
    cellHash: UInt32,
    palette: [SIMD3<Float>],
    seedA: Float, seedB: Float, seedC: Float, seedD: Float,
    bassCounter: Float, midCounter: Float, trebleCounter: Float
) -> SIMD3<Float> {
    precondition(palette.count == 12)
    let teamCounter = lmTeamCounter(cellHash: cellHash,
                                    bass: bassCounter, mid: midCounter, treble: trebleCounter)
    let period = lmPeriod(cellHash: cellHash)
    let step = floor(teamCounter / period)
    let sectionSalt = UInt32(floor(bassCounter / LMPalette.sectionBeatLength))
    let trackSeed = lmTrackSeedHash(seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD)

    let stepMix: UInt32     = UInt32(step) &* 0x9E37_79B9
    let sectionMix: UInt32  = sectionSalt &* 0xCC9E_2D51
    let h = lmHashU32(cellHash ^ stepMix ^ trackSeed ^ sectionMix)
    let idx = Int(h % 12)
    return palette[idx]
}

// MARK: - Random sampler

private struct Mulberry32 {
    var state: UInt32
    mutating func nextUInt32() -> UInt32 {
        state = state &+ 0x6D2B79F5
        var z = state
        z = (z ^ (z >> 15)) &* (z | 1)
        z ^= z &+ ((z ^ (z >> 7)) &* (z | 61))
        return z ^ (z >> 14)
    }
    mutating func nextUniform() -> Float { Float(nextUInt32() >> 8) / Float(1 << 24) }
    mutating func nextSigned() -> Float  { nextUniform() * 2 - 1 }
}

// MARK: - Suite 1: Palette membership

@Suite("LM.4.7 — palette membership")
struct LumenPaletteMembershipTests {

    /// Every cell colour the shader produces under any combination of
    /// (cellHash, step, trackSeed, sectionSalt) must be byte-equal (within
    /// float epsilon) to one of the 12 entries of the bound palette. This
    /// is the structural contract of the LM.4.7 path — cells never
    /// synthesise colour outside the curated table.
    @Test func test_everyCellSample_matchesActivePaletteEntry() {
        for palette in LumenMosaicPaletteLibrary.all {
            let colours = palette.colors
            #expect(colours.count == 12,
                    "palette \(palette.name) must have 12 colours, got \(colours.count)")
            var rng = Mulberry32(state: 0x1234_ABCD)
            for _ in 0..<1000 {
                let cellHash = rng.nextUInt32()
                let seedA = rng.nextSigned()
                let seedB = rng.nextSigned()
                let seedC = rng.nextSigned()
                let seedD = rng.nextSigned()
                let bC = rng.nextUniform() * 200
                let mC = rng.nextUniform() * 200
                let tC = rng.nextUniform() * 200
                let rgb = lmCellPaletteRGB(
                    cellHash: cellHash,
                    palette: colours,
                    seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
                    bassCounter: bC, midCounter: mC, trebleCounter: tC
                )
                let match = colours.contains { entry in
                    abs(entry.x - rgb.x) < 1e-6 &&
                    abs(entry.y - rgb.y) < 1e-6 &&
                    abs(entry.z - rgb.z) < 1e-6
                }
                #expect(match,
                        "palette \(palette.name): produced \(rgb) outside the 12-entry table")
            }
        }
    }
}

// MARK: - Suite 2: Per-song selection determinism

@Suite("LM.4.7 — per-song selection determinism")
struct LumenPaletteSelectionDeterminismTests {

    @Test func test_sameTriple_returnsSameIndex_acrossManySeeds() {
        var rng = Mulberry32(state: 0xF00D_F00D)
        for _ in 0..<32 {
            let mood = SIMD2<Float>(rng.nextSigned() * 0.8, rng.nextSigned() * 0.8)
            let recent = [Int(rng.nextUInt32() % 18),
                          Int(rng.nextUInt32() % 18),
                          Int(rng.nextUInt32() % 18)]
            let seed = UInt64(rng.nextUInt32()) | (UInt64(rng.nextUInt32()) << 32)
            let first = LumenMosaicPaletteLibrary.selectPalette(
                mood: mood, recentPaletteIndices: recent, trackSeed: seed)
            let second = LumenMosaicPaletteLibrary.selectPalette(
                mood: mood, recentPaletteIndices: recent, trackSeed: seed)
            #expect(first == second,
                    "selectPalette non-deterministic for mood=\(mood) recent=\(recent) seed=\(seed): \(first) vs \(second)")
        }
    }

    @Test func test_firstSong_emptyRecent_drawsFromFullLibrary() {
        // No recent palettes → all 18 are candidates. A sweep over many
        // seeds should cover most of the library.
        var seenIndices: Set<Int> = []
        for seed in 0..<5000 {
            let idx = LumenMosaicPaletteLibrary.selectPalette(
                mood: SIMD2<Float>(0, 0),
                recentPaletteIndices: [],
                trackSeed: UInt64(seed))
            seenIndices.insert(idx)
        }
        #expect(seenIndices.count >= 10,
                "first-song draw at mid-mood should cover ≥ 10 palettes across 5000 seeds, saw \(seenIndices.count)")
    }

    @Test func test_antiRepeatWindow_isThree() {
        // Lock the documented policy. If we change the window size we
        // should update this assertion AND the carry-forward in
        // D-LM-palette-library.
        #expect(LumenMosaicPaletteLibrary.kAntiRepeatWindow == 3)
    }
}

// MARK: - Suite 3: Anti-repeat

@Suite("LM.4.7 — anti-repeat (window = 3)")
struct LumenPaletteAntiRepeatTests {

    /// Single-item exclusion case — the N=1 contract from the original
    /// D-LM-palette-library spec must still hold under the widened window.
    @Test func test_selectPalette_neverReturnsImmediatelyPreviousIndex() {
        let moods: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0.7, 0.7), SIMD2(-0.7, 0.7),
            SIMD2(-0.7, -0.7), SIMD2(0.7, -0.7), SIMD2(0.3, -0.4)
        ]
        for prev in 0..<18 {
            for mood in moods {
                for seedBase in 0..<20 {
                    let seed = UInt64(prev * 10_000 + seedBase) ^ 0xDEAD_BEEF_DEAD_F00D
                    let idx = LumenMosaicPaletteLibrary.selectPalette(
                        mood: mood, recentPaletteIndices: [prev], trackSeed: seed)
                    #expect(idx != prev,
                            "anti-repeat-1 violated: prev=\(prev) returned \(idx) at mood=\(mood) seed=\(seed)")
                    #expect(idx >= 0 && idx < 18,
                            "selectPalette returned out-of-bounds index \(idx)")
                }
            }
        }
    }

    /// Full-window exclusion case (the post-amendment N=3 contract): a
    /// recent-3 sliding window must be excluded in its entirety on every
    /// draw, across a mood × seed sweep.
    @Test func test_selectPalette_excludesEntireRecentWindow() {
        let moods: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0.7, 0.7), SIMD2(-0.7, 0.7),
            SIMD2(-0.7, -0.7), SIMD2(0.7, -0.7), SIMD2(0.3, -0.4)
        ]
        // Sample a handful of representative recent-3 windows. Permutations
        // matter to the deterministic-PRNG draw, not to the exclusion
        // semantics, so a small set covers the contract.
        let windows: [[Int]] = [
            [0, 1, 2], [5, 6, 7], [10, 11, 12], [15, 16, 17],
            [3, 9, 14], [4, 8, 13], [0, 8, 17], [7, 13, 2]
        ]
        for window in windows {
            let excluded = Set(window)
            for mood in moods {
                for seedBase in 0..<25 {
                    let seed = UInt64(seedBase * 137) ^ 0xCAFE_BABE_FEED_0BAD
                    let idx = LumenMosaicPaletteLibrary.selectPalette(
                        mood: mood, recentPaletteIndices: window, trackSeed: seed)
                    #expect(!excluded.contains(idx),
                            "anti-repeat-N=3 violated: returned \(idx) ∈ window \(window) at mood=\(mood) seed=\(seed)")
                    #expect(idx >= 0 && idx < 18,
                            "selectPalette returned out-of-bounds index \(idx)")
                }
            }
        }
    }
}

// MARK: - Suite 4: Mood-weighted distribution shape

@Suite("LM.4.7 — mood-weighted distribution shape")
struct LumenPaletteMoodDistributionTests {

    private func drawCounts(
        mood: SIMD2<Float>,
        trials: Int = 10_000,
        seedSalt: UInt64 = 0
    ) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for s in 0..<trials {
            let seed = UInt64(s) ^ seedSalt
            let idx = LumenMosaicPaletteLibrary.selectPalette(
                mood: mood, recentPaletteIndices: [], trackSeed: seed)
            counts[idx, default: 0] += 1
        }
        return counts
    }

    /// Per README: high-valence high-arousal favours Carnival(6),
    /// Holi(7), Tropical Aviary(10), Refn Glow(1) over Rothko Chapel(9),
    /// Tenebrism(16), Cathedral Lights(13).
    @Test func test_highVA_favoursWarmHighEnergyPalettes() {
        let counts = drawCounts(mood: SIMD2<Float>(0.7, 0.7))
        let favouredSum = (counts[1] ?? 0) + (counts[6] ?? 0)
                        + (counts[7] ?? 0) + (counts[10] ?? 0)
        let disfavouredSum = (counts[9] ?? 0) + (counts[13] ?? 0) + (counts[16] ?? 0)
        #expect(favouredSum > disfavouredSum * 2,
                "high-VA: favoured (Carnival/Holi/Aviary/Refn) sum \(favouredSum) not ≥ 2× disfavoured (Rothko/Cathedral/Tenebrism) \(disfavouredSum)")
    }

    /// Per README: low-valence low-arousal favours Rothko Chapel(9),
    /// Tenebrism(16), Cathedral Lights(13), Kintsugi(5) over Carnival(6),
    /// Holi(7), Tropical Aviary(10).
    @Test func test_lowVA_favoursDarkLowEnergyPalettes() {
        let counts = drawCounts(mood: SIMD2<Float>(-0.7, -0.7))
        let favouredSum = (counts[5] ?? 0) + (counts[9] ?? 0)
                        + (counts[13] ?? 0) + (counts[16] ?? 0)
        let disfavouredSum = (counts[6] ?? 0) + (counts[7] ?? 0) + (counts[10] ?? 0)
        #expect(favouredSum > disfavouredSum * 2,
                "low-VA: favoured (Kintsugi/Rothko/Cathedral/Tenebrism) sum \(favouredSum) not ≥ 2× disfavoured (Carnival/Holi/Aviary) \(disfavouredSum)")
    }
}

// MARK: - Suite 5: Pale-tone-share gate (LM.9 / D-LM-cream-rescission)

@Suite("LM.9 — pale-tone-share gate")
struct LumenPaletteCreamGateTests {

    /// For each of the 18 palettes, sample N cells via the post-LM.4.7
    /// `lm_cell_palette` path and assert the pale-cell share is ≤ 0.30.
    /// Cathedral Lights — the calibration palette — has 2 of 12 pale
    /// entries by the rule's mechanical definition, so its empirical
    /// share lands near 2/12 ≈ 0.167 well under the 0.30 ceiling.
    @Test func test_every_palette_passes_paleShareCeiling() {
        for palette in LumenMosaicPaletteLibrary.all {
            let colours = palette.colors
            var rng = Mulberry32(state: 0x5A5A_AAAA)
            let n = 1500
            var paleCount = 0
            for _ in 0..<n {
                let cellHash = rng.nextUInt32()
                let seedA = rng.nextSigned()
                let seedB = rng.nextSigned()
                let seedC = rng.nextSigned()
                let seedD = rng.nextSigned()
                let bC = rng.nextUniform() * 200
                let mC = rng.nextUniform() * 200
                let tC = rng.nextUniform() * 200
                let rgb = lmCellPaletteRGB(
                    cellHash: cellHash,
                    palette: colours,
                    seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
                    bassCounter: bC, midCounter: mC, trebleCounter: tC
                )
                let srgbR = lmLinearToSRGB(rgb.x)
                let srgbG = lmLinearToSRGB(rgb.y)
                let srgbB = lmLinearToSRGB(rgb.z)
                let m = min(srgbR, min(srgbG, srgbB))
                if m > LMPalette.palePredicateThreshold { paleCount += 1 }
            }
            let share = Float(paleCount) / Float(n)
            #expect(share <= LMPalette.palePanelShareCeiling,
                    "palette \(palette.name) pale-share \(share) exceeds ceiling \(LMPalette.palePanelShareCeiling)")
        }
    }

    /// Cathedral Lights is the cream-rescission calibration point per
    /// D-LM-cream-rescission. Lock the expected ~16.7 % nominal share —
    /// hash-draw variance should keep it well below the 30 % ceiling.
    @Test func test_cathedralLights_calibrationPoint() {
        guard let palette = LumenMosaicPaletteLibrary.all.first(where: { $0.name == "Cathedral Lights" }) else {
            Issue.record("Cathedral Lights palette not found in library")
            return
        }
        let colours = palette.colors
        var rng = Mulberry32(state: 0xBEEF_BEEF)
        let n = 4000
        var paleCount = 0
        for _ in 0..<n {
            let cellHash = rng.nextUInt32()
            let bC = rng.nextUniform() * 200
            let rgb = lmCellPaletteRGB(
                cellHash: cellHash,
                palette: colours,
                seedA: 0, seedB: 0, seedC: 0, seedD: 0,
                bassCounter: bC, midCounter: 0, trebleCounter: 0
            )
            let srgbR = lmLinearToSRGB(rgb.x)
            let srgbG = lmLinearToSRGB(rgb.y)
            let srgbB = lmLinearToSRGB(rgb.z)
            let m = min(srgbR, min(srgbG, srgbB))
            if m > LMPalette.palePredicateThreshold { paleCount += 1 }
        }
        let share = Float(paleCount) / Float(n)
        // 2 / 12 = 0.1667 ± hash-draw variance (~0.02 at n=4000).
        #expect(share > 0.10 && share < 0.25,
                "Cathedral Lights calibration share \(share) outside expected [0.10, 0.25] window")
    }
}

// MARK: - Suite 6: Track-change reproducibility

@Suite("LM.4.7 — track-change reproducibility")
struct LumenPaletteTrackSequenceTests {

    /// A scripted sequence of (mood, trackSeed) pairs walked through
    /// `selectPalette` with the `kAntiRepeatWindow = 3` policy applied
    /// must reproduce the same sequence of palette indices every run —
    /// load-bearing for session replay. The same walk must also
    /// satisfy the policy: no palette repeats within any 3-track
    /// sliding window.
    @Test func test_scriptedTrackSequence_isReproducible() {
        struct Track { let mood: SIMD2<Float>; let seed: UInt64 }
        let script: [Track] = [
            Track(mood: SIMD2( 0.6,  0.6), seed: 0xA1B2_C3D4_E5F6_0708),
            Track(mood: SIMD2(-0.5, -0.5), seed: 0x1234_5678_9ABC_DEF0),
            Track(mood: SIMD2( 0.0,  0.0), seed: 0xDEAD_BEEF_F00D_F00D),
            Track(mood: SIMD2(-0.7,  0.5), seed: 0xCAFE_BABE_FACE_C0DE),
            Track(mood: SIMD2( 0.4, -0.5), seed: 0xBADD_CAFE_FEED_0BAD),
            Track(mood: SIMD2( 0.7,  0.7), seed: 0x0011_2233_4455_6677),
            Track(mood: SIMD2(-0.4,  0.3), seed: 0xF00D_BABE_C0DE_F00D),
            Track(mood: SIMD2( 0.2, -0.6), seed: 0xBEEF_BEEF_BEEF_BEEF),
        ]
        let cap = LumenMosaicPaletteLibrary.kAntiRepeatWindow

        func walk(_ script: [Track]) -> [Int] {
            var draws: [Int] = []
            var window: [Int] = []
            for track in script {
                let idx = LumenMosaicPaletteLibrary.selectPalette(
                    mood: track.mood, recentPaletteIndices: window, trackSeed: track.seed)
                draws.append(idx)
                window.append(idx)
                if window.count > cap {
                    window.removeFirst(window.count - cap)
                }
            }
            return draws
        }

        let pass1 = walk(script)
        let pass2 = walk(script)
        #expect(pass1 == pass2, "track-sequence draws diverged across runs: \(pass1) vs \(pass2)")

        // Anti-repeat-N=3 applied across the scripted walk — no palette
        // repeats within any 3-track sliding window.
        for i in 1..<pass1.count {
            let windowStart = max(0, i - cap)
            let recent = Array(pass1[windowStart..<i])
            #expect(!recent.contains(pass1[i]),
                    "anti-repeat-3 violated at step \(i): \(pass1[i]) appears in recent \(recent); full sequence \(pass1)")
        }
    }
}

// MARK: - LM.6 helpers — mirror of the depth-gradient + hot-spot block in
// `sceneMaterial`. Pure scalar arithmetic; same math the shader applies
// per-pixel to `cell_hue` between palette lookup and frost diffusion.

private func lmSmoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    if edge0 >= edge1 { return x < edge0 ? 0 : 1 }
    let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
}

private func lmMix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

/// Per-pixel multiplier the LM.6 depth gradient applies to `cell_hue`.
/// 1.0 at centre (`f1 = 0`); `kCellEdgeDarkness` at edge (`f1 = f2`).
private func lmCellDepthFactor(f1: Float, f2: Float) -> Float {
    let cellRadius = f2 * LMPalette.depthGradientFalloff
    let depth01 = 1.0 - lmSmoothstep(0, cellRadius, f1)
    return lmMix(LMPalette.cellEdgeDarkness, 1.0, depth01)
}

/// Per-pixel multiplier the LM.6 hot-spot applies to `cell_hue`. The
/// shader form `cell_hue += hotSpot × intensity × cell_hue` is
/// equivalent to `cell_hue *= (1 + hotSpot × intensity)`; we return
/// that scalar so the test can compare directly.
private func lmHotSpotMultiplier(f1: Float, f2: Float) -> Float {
    let edge = LMPalette.hotSpotRadius * f2
    let raw = 1.0 - lmSmoothstep(0, edge, f1)
    let shaped = pow(raw, LMPalette.hotSpotShape)
    return 1.0 + shaped * LMPalette.hotSpotIntensity
}

// MARK: - Suite 7: LM.6 — Cell-depth gradient (preserved verbatim)

@Suite("LM.6 — cell-depth gradient")
struct LumenCellDepthGradientTests {

    @Test func test_cellCentre_isBrighterThanEdge() {
        let f2: Float = 0.1
        let centre = lmCellDepthFactor(f1: 0,  f2: f2)
        let edge   = lmCellDepthFactor(f1: f2, f2: f2)
        #expect(centre > edge, "centre factor \(centre) not > edge factor \(edge)")
        #expect(abs(centre - 1.0) < 1e-5, "centre depth factor should be 1.0, got \(centre)")
        #expect(abs(edge - LMPalette.cellEdgeDarkness) < 1e-5,
                "edge factor should be kCellEdgeDarkness (\(LMPalette.cellEdgeDarkness)), got \(edge)")
    }

    @Test func test_hotSpot_brightensCellCentre() {
        let f2: Float = 0.1
        let peakMul = lmHotSpotMultiplier(f1: 0, f2: f2)
        let expectedPeak: Float = 1.0 + LMPalette.hotSpotIntensity
        #expect(abs(peakMul - expectedPeak) < 1e-5,
                "hot-spot peak multiplier should be \(expectedPeak), got \(peakMul)")

        let outsideMul = lmHotSpotMultiplier(f1: LMPalette.hotSpotRadius * f2 + 1e-3, f2: f2)
        #expect(abs(outsideMul - 1.0) < 1e-5,
                "hot-spot multiplier outside kHotSpotRadius × f2 should be 1.0, got \(outsideMul)")
    }

    @Test func test_depthGradient_smoothAcrossRadius() {
        let f2: Float = 0.1
        let samples: [Float] = [0, 0.25 * f2, 0.5 * f2, 0.75 * f2, f2]
        let factors = samples.map { lmCellDepthFactor(f1: $0, f2: f2) }
        for i in 1..<factors.count {
            let prev = factors[i - 1]
            let curr = factors[i]
            #expect(curr < prev - 1e-6,
                    "depth gradient not monotonic at sample \(i): \(prev) → \(curr)")
        }
        #expect(abs(factors.first! - 1.0) < 1e-5)
        #expect(abs(factors.last!  - LMPalette.cellEdgeDarkness) < 1e-5)
    }
}
