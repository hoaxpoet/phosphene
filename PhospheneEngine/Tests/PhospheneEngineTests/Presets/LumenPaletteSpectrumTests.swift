// LumenPaletteSpectrumTests — Regression-lock for LM.4.6 (pure uniform
// random RGB per cell).
//
// Mirror of `lm_cell_palette` in `LumenMosaic.metal`. Asserts:
//   1. Per-cell uniqueness — 1500 cells produce ≥ 500 distinct colours.
//   2. R/G/B coverage — each channel spans both halves of [0, 1].
//   3. Per-track distinctness — same cell on different trackSeeds → different RGB.
//   4. Determinism — same inputs → same RGB.
//   5. Beat-step change — single team-counter step on a period=1 cell changes RGB.
//   6. Section boundary — bassCounter crossing kSectionBeatLength changes RGB.
//   7. Within-section stable — within the same section bucket + step, RGB is constant.

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
    return SIMD3<Float>(r, g, b)
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
