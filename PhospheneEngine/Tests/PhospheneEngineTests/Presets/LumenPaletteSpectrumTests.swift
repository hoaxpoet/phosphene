// LumenPaletteSpectrumTests — Regression-lock for LM.4.6 (uniform random
// RGB per cell) + LM.6 (cell-depth gradient + hot-spot) + LM.7
// (per-track RGB tint vector for aggregate-mean distinction).
//
// Mirror of `lm_cell_palette` + the LM.6 depth-gradient / hot-spot block
// in `LumenMosaic.metal`. Asserts:
//   1. Per-cell uniqueness — 1500 cells produce ≥ 500 distinct colours.
//   2. R/G/B coverage — each channel spans both halves of [0, 1].
//   3. Per-track distinctness — same cell on different trackSeeds → different RGB.
//   4. Determinism — same inputs → same RGB.
//   5. Beat-step change — single team-counter step on a period=1 cell changes RGB.
//   6. Section boundary — bassCounter crossing kSectionBeatLength changes RGB.
//   7. Within-section stable — within the same section bucket + step, RGB is constant.
//   8. LM.6 cell-depth gradient — centre brighter than edge.
//   9. LM.6 hot-spot — multiplier peaks at f1=0, decays to 1.0 past kHotSpotRadius × f2.
//  10. LM.6 depth gradient — monotonic decreasing across the cell radius.
//  11. LM.7 warm track — aggregate mean R high, B low.
//  12. LM.7 cool track — aggregate mean R low, B high.
//  13. LM.7 distinct tracks — different trackSeeds produce visibly different aggregate means.
//  14. LM.7 neutral track — zero trackSeeds produce mean near middle-gray.

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

    // LM.7 — per-track RGB tint magnitude. Mirror the .metal constant.
    static let tintMagnitude: Float          = 0.25
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

/// Mirror of `lm_cell_palette` (LM.4.6) — pure uniform random RGB.
private func lmCellPaletteRGB(
    cellHash: UInt32,
    seedA: Float, seedB: Float, seedC: Float, seedD: Float,
    bassCounter: Float, midCounter: Float, trebleCounter: Float
) -> SIMD3<Float> {
    let teamCounter = lmTeamCounter(cellHash: cellHash,
                                    bass: bassCounter, mid: midCounter, treble: trebleCounter)
    let period = lmPeriod(cellHash: cellHash)
    let step = floor(teamCounter / period)
    let sectionSalt = UInt32(floor(bassCounter / LMPalette.sectionBeatLength))
    let trackSeed = lmTrackSeedHash(seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD)

    let stepMix: UInt32     = UInt32(step) &* 0x9E37_79B9
    let sectionMix: UInt32  = sectionSalt &* 0xCC9E_2D51
    let colourHash = lmHashU32(cellHash ^ stepMix ^ trackSeed ^ sectionMix)

    let r = Float((colourHash >>  0) & 0xFF) * (1.0 / 255.0)
    let g = Float((colourHash >>  8) & 0xFF) * (1.0 / 255.0)
    let b = Float((colourHash >> 16) & 0xFF) * (1.0 / 255.0)

    // LM.7 — per-track RGB tint, projected onto the chromatic plane
    // (mean subtracted) so achromatic-aligned seeds don't produce
    // toward-white / toward-black wash. saturate-clamped.
    let rawTint = SIMD3<Float>(seedA, seedB, seedC)
    let meanShift = (rawTint.x + rawTint.y + rawTint.z) / 3.0
    let trackTint = (rawTint - SIMD3<Float>(repeating: meanShift)) * LMPalette.tintMagnitude
    let tinted = SIMD3<Float>(r, g, b) + trackTint
    return SIMD3<Float>(
        max(0, min(1, tinted.x)),
        max(0, min(1, tinted.y)),
        max(0, min(1, tinted.z))
    )
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

// MARK: - Suite 1: Per-cell uniqueness

@Suite("LM.4.6 — per-cell uniqueness")
struct LumenPaletteUniquenessTests {

    @Test func test_1500cells_produceManyDistinctColours() {
        var rng = Mulberry32(state: 0x1234_ABCD)
        var samples: Set<UInt32> = []
        for _ in 0..<1500 {
            let cellHash = rng.nextUInt32()
            let rgb = lmCellPaletteRGB(cellHash: cellHash,
                                       seedA: 0.3, seedB: 0.1, seedC: -0.2, seedD: 0.5,
                                       bassCounter: 0, midCounter: 0, trebleCounter: 0)
            let r6 = UInt32(min(max(rgb.x, 0), 0.999) * 64)
            let g6 = UInt32(min(max(rgb.y, 0), 0.999) * 64)
            let b6 = UInt32(min(max(rgb.z, 0), 0.999) * 64)
            samples.insert((r6 << 12) | (g6 << 6) | b6)
        }
        #expect(samples.count > 500,
                "only \(samples.count) distinct colours from 1500 cells")
    }
}

// MARK: - Suite 2: RGB channel coverage

@Suite("LM.4.6 — RGB channel coverage")
struct LumenPaletteChannelCoverageTests {

    @Test func test_1000samples_eachChannelSpansBothHalves() {
        var rng = Mulberry32(state: 0xCAFE_BABE)
        var rLow = 0, rHigh = 0
        var gLow = 0, gHigh = 0
        var bLow = 0, bHigh = 0
        for _ in 0..<1000 {
            let cellHash = rng.nextUInt32()
            let seedA = rng.nextSigned()
            let seedB = rng.nextSigned()
            let seedC = rng.nextSigned()
            let seedD = rng.nextSigned()
            let rgb = lmCellPaletteRGB(cellHash: cellHash,
                                       seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
                                       bassCounter: 0, midCounter: 0, trebleCounter: 0)
            if rgb.x < 0.5 { rLow += 1 } else { rHigh += 1 }
            if rgb.y < 0.5 { gLow += 1 } else { gHigh += 1 }
            if rgb.z < 0.5 { bLow += 1 } else { bHigh += 1 }
        }
        #expect(rLow >= 100 && rHigh >= 100, "R channel collapsed: low=\(rLow) high=\(rHigh)")
        #expect(gLow >= 100 && gHigh >= 100, "G channel collapsed: low=\(gLow) high=\(gHigh)")
        #expect(bLow >= 100 && bHigh >= 100, "B channel collapsed: low=\(bLow) high=\(bHigh)")
    }
}

// MARK: - Suite 3: Per-track distinctness + determinism

@Suite("LM.4.6 — per-track distinctness + determinism")
struct LumenPaletteTrackDistinctnessTests {

    @Test func test_sameCell_differentTrackSeeds_differentColour() {
        let cellHash: UInt32 = 0x1234_ABCD
        let trackA = lmCellPaletteRGB(cellHash: cellHash,
                                      seedA: +1, seedB: +1, seedC: +1, seedD: +1,
                                      bassCounter: 0, midCounter: 0, trebleCounter: 0)
        let trackB = lmCellPaletteRGB(cellHash: cellHash,
                                      seedA: -1, seedB: -1, seedC: -1, seedD: -1,
                                      bassCounter: 0, midCounter: 0, trebleCounter: 0)
        #expect(trackA != trackB, "same cell on different trackSeeds produced same colour")
    }

    @Test func test_sameSeed_deterministic() {
        var rng = Mulberry32(state: 0xF00D_F00D)
        for _ in 0..<10 {
            let cellHash = rng.nextUInt32()
            let seedA = rng.nextSigned()
            let seedB = rng.nextSigned()
            let seedC = rng.nextSigned()
            let seedD = rng.nextSigned()
            let first = lmCellPaletteRGB(cellHash: cellHash,
                                         seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
                                         bassCounter: 0, midCounter: 0, trebleCounter: 0)
            let second = lmCellPaletteRGB(cellHash: cellHash,
                                          seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
                                          bassCounter: 0, midCounter: 0, trebleCounter: 0)
            #expect(first == second, "non-deterministic palette for cellHash \(cellHash)")
        }
    }
}

// MARK: - Suite 4: Beat-step change

@Suite("LM.4.6 — beat-step change")
struct LumenPaletteBeatStepTests {

    /// cellHash 0x14: bucket = 20 (bass team), periodBucket = 0 → period 1.
    private let period1BassCell: UInt32 = 0x0000_0014

    @Test func test_singleBeatChangesColour() {
        let cellHash = period1BassCell
        let rgb0 = lmCellPaletteRGB(cellHash: cellHash,
                                    seedA: 0.5, seedB: -0.2, seedC: 0.7, seedD: -0.4,
                                    bassCounter: 0, midCounter: 0, trebleCounter: 0)
        let rgb1 = lmCellPaletteRGB(cellHash: cellHash,
                                    seedA: 0.5, seedB: -0.2, seedC: 0.7, seedD: -0.4,
                                    bassCounter: 1, midCounter: 0, trebleCounter: 0)
        #expect(rgb0 != rgb1, "single beat step produced identical colour")
    }
}

// MARK: - Suite 5: Section boundary mutation

@Suite("LM.4.6 — section salt mutation")
struct LumenPaletteSectionTests {

    /// Static-team cell (bucket >= 90): teamCounter is always 0, so step
    /// stays 0 regardless of bassCounter; only sectionSalt drives the
    /// colour change at the boundary.
    private let staticCell: UInt32 = 0x0000_005A

    @Test func test_sectionBoundary_changesColour() {
        let bC0: Float = 32   // section bucket 0
        let bC1: Float = 96   // section bucket 1 (crossed 64-beat boundary)
        let rgb0 = lmCellPaletteRGB(cellHash: staticCell,
                                    seedA: 0.5, seedB: -0.2, seedC: 0.7, seedD: -0.4,
                                    bassCounter: bC0, midCounter: 0, trebleCounter: 0)
        let rgb1 = lmCellPaletteRGB(cellHash: staticCell,
                                    seedA: 0.5, seedB: -0.2, seedC: 0.7, seedD: -0.4,
                                    bassCounter: bC1, midCounter: 0, trebleCounter: 0)
        #expect(rgb0 != rgb1, "section boundary did not change colour")
    }

    @Test func test_withinSection_colourStable() {
        let rgbA = lmCellPaletteRGB(cellHash: staticCell,
                                    seedA: 0.1, seedB: 0.2, seedC: 0.3, seedD: 0.4,
                                    bassCounter: 10, midCounter: 0, trebleCounter: 0)
        let rgbB = lmCellPaletteRGB(cellHash: staticCell,
                                    seedA: 0.1, seedB: 0.2, seedC: 0.3, seedD: 0.4,
                                    bassCounter: 50, midCounter: 0, trebleCounter: 0)
        #expect(rgbA == rgbB, "colour drifted within section bucket")
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

// MARK: - Suite 6: LM.6 — Cell-depth gradient

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
        // At f1=0 the hot-spot is at peak: multiplier = 1 + 1×kHotSpotIntensity.
        let peakMul = lmHotSpotMultiplier(f1: 0, f2: f2)
        let expectedPeak: Float = 1.0 + LMPalette.hotSpotIntensity
        #expect(abs(peakMul - expectedPeak) < 1e-5,
                "hot-spot peak multiplier should be \(expectedPeak), got \(peakMul)")

        // At f1 > kHotSpotRadius × f2 the hot-spot has fully decayed.
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
        // Endpoint sanity (re-validate Suite 6.1 invariants on this sample grid).
        #expect(abs(factors.first! - 1.0) < 1e-5)
        #expect(abs(factors.last!  - LMPalette.cellEdgeDarkness) < 1e-5)
    }
}

// MARK: - Suite 7: LM.7 — Per-track aggregate-mean tint

/// Aggregate the mean RGB over many independent cells on a single track.
/// Mirrors what an observer perceives looking at a panel of ~30 visible
/// cells but uses 2000 samples for a stable statistic.
private func aggregateMean(
    seedA: Float, seedB: Float, seedC: Float, seedD: Float,
    sampleCount: Int = 2000,
    rngState: UInt32 = 0xABCD_1234
) -> SIMD3<Float> {
    var rng = Mulberry32(state: rngState)
    var sum = SIMD3<Float>(0, 0, 0)
    for _ in 0..<sampleCount {
        let cellHash = rng.nextUInt32()
        let rgb = lmCellPaletteRGB(
            cellHash: cellHash,
            seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
            bassCounter: 0, midCounter: 0, trebleCounter: 0
        )
        sum += rgb
    }
    return sum / Float(sampleCount)
}

@Suite("LM.7 — per-track aggregate-mean tint")
struct LumenTrackTintTests {

    @Test func test_warmTrack_aggregateMeanLeansWarm() {
        // seedA = +1, seedC = -1 → tint ≈ (+0.25, 0, -0.25) → warm
        let mean = aggregateMean(seedA: +1, seedB: 0, seedC: -1, seedD: 0)
        #expect(mean.x > 0.60, "warm track mean R should lean high, got \(mean.x)")
        #expect(mean.z < 0.40, "warm track mean B should lean low, got \(mean.z)")
        #expect(mean.x > mean.z + 0.15,
                "warm track should have R−B gap > 0.15, got R=\(mean.x) B=\(mean.z)")
    }

    @Test func test_coolTrack_aggregateMeanLeansCool() {
        // seedA = -1, seedC = +1 → tint ≈ (-0.25, 0, +0.25) → cool
        let mean = aggregateMean(seedA: -1, seedB: 0, seedC: +1, seedD: 0)
        #expect(mean.x < 0.40, "cool track mean R should lean low, got \(mean.x)")
        #expect(mean.z > 0.60, "cool track mean B should lean high, got \(mean.z)")
        #expect(mean.z > mean.x + 0.15,
                "cool track should have B−R gap > 0.15, got R=\(mean.x) B=\(mean.z)")
    }

    @Test func test_distinctTracks_haveDistinctAggregateMeans() {
        let trackA = aggregateMean(seedA: +0.8, seedB: -0.3, seedC: +0.1, seedD: 0)
        let trackB = aggregateMean(seedA: -0.5, seedB: +0.7, seedC: -0.6, seedD: 0)
        let trackC = aggregateMean(seedA: -0.2, seedB: -0.6, seedC: +0.9, seedD: 0)
        let distAB = simd_distance(trackA, trackB)
        let distAC = simd_distance(trackA, trackC)
        let distBC = simd_distance(trackB, trackC)
        #expect(distAB > 0.20, "tracks A,B aggregate-mean distance \(distAB) too small")
        #expect(distAC > 0.20, "tracks A,C aggregate-mean distance \(distAC) too small")
        #expect(distBC > 0.20, "tracks B,C aggregate-mean distance \(distBC) too small")
    }

    @Test func test_neutralTrack_aggregateMeanNearMiddleGray() {
        // All seeds zero → tint = (0,0,0) → behaviour identical to LM.4.6.
        // Aggregate mean should land near (0.5, 0.5, 0.5).
        let mean = aggregateMean(seedA: 0, seedB: 0, seedC: 0, seedD: 0)
        let dist = simd_distance(mean, SIMD3<Float>(0.5, 0.5, 0.5))
        #expect(dist < 0.05,
                "neutral track mean should be near middle gray, got \(mean) dist=\(dist)")
    }

    /// Regression-lock the chromatic-projection fix (Matt 2026-05-12).
    /// Seeds aligned along the achromatic axis (all-positive or
    /// all-negative) would, without the mean-subtraction projection,
    /// shift the panel toward white (washed) or black (muddy). With
    /// the projection in place, achromatic-aligned seeds collapse to
    /// the chromatic plane — the panel reads as neutral-middle-gray
    /// rather than washed/muddy.
    @Test func test_achromaticAlignedSeed_doesNotWash() {
        // All-positive seeds — what produced the track_v1 wash before
        // the fix.
        let allPos = aggregateMean(seedA: +1, seedB: +1, seedC: +1, seedD: 0)
        #expect(allPos.x < 0.60,
                "achromatic-+ track must not wash toward white (got R=\(allPos.x))")
        #expect(allPos.y < 0.60,
                "achromatic-+ track must not wash toward white (got G=\(allPos.y))")
        #expect(allPos.z < 0.60,
                "achromatic-+ track must not wash toward white (got B=\(allPos.z))")

        // All-negative seeds — would push toward black under the
        // unprojected tint.
        let allNeg = aggregateMean(seedA: -1, seedB: -1, seedC: -1, seedD: 0)
        #expect(allNeg.x > 0.40,
                "achromatic-− track must not collapse toward black (got R=\(allNeg.x))")
        #expect(allNeg.y > 0.40,
                "achromatic-− track must not collapse toward black (got G=\(allNeg.y))")
        #expect(allNeg.z > 0.40,
                "achromatic-− track must not collapse toward black (got B=\(allNeg.z))")
    }
}
