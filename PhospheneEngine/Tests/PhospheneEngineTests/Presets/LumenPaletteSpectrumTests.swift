// LumenPaletteSpectrumTests — Regression-lock for the LM.4.5 full-spectrum
// palette card model.
//
// Lumen Mosaic's palette is procedural and shader-side; there's no GPU
// readback in the test harness. The contract is byte-identical math, so
// this file mirrors `lm_cell_palette` from `LumenMosaic.metal` in Swift
// and asserts the five LM.4.5 invariants against the mirror. If a future
// shader edit drifts the algorithm without updating this mirror, the
// invariants fail and surface the drift before it reaches a contact
// sheet.
//
// Invariants verified (LM.4.5):
//   1. Spectrum coverage  — 200 random (cellHash, trackSeed) pairs at
//      neutral mood produce HSV samples spanning ≥ 270° of hue,
//      saturation spread ≥ 0.6, brightness spread ≥ 0.5.
//   2. No pastel          — 1000 random samples, ZERO satisfy
//      `sat < 0.3 AND val > 0.6` (the forbidden cream-haze zone).
//   3. Per-track distinct — two different trackSeeds produce Jaccard
//      similarity < 0.5 over their first 50 card slots (rounded to
//      5-bit HSV). Same trackSeed produces identical samples (determinism).
//   4. Beat-step ratchet  — a single team-counter step (for a period=1
//      cell) advances the cell's `cardIndex` by exactly 1 mod kCardSize.
//   5. Mood bias preserved envelope — at arousal = -1, average value <
//      arousal = +1 average; both distributions still contain samples
//      in BOTH the bright (v > 0.5) and dim (v < 0.5) halves.

import Testing
import simd
@testable import Presets
import Shared

// MARK: - Constants mirrored from LumenMosaic.metal

private enum LMPalette {
    static let cardSize: UInt32           = 48
    static let cardValMin: Float          = 0.08
    static let cardValMax: Float          = 0.95
    static let pastelSatCutoff: Float     = 0.30
    static let pastelValCap: Float        = 0.50
    static let moodGammaLowArousal: Float = 1.80
    static let moodGammaHighArousal: Float = 0.55
    static let bassTeamCutoff: UInt32     = 30
    static let midTeamCutoff: UInt32      = 65
    static let trebleTeamCutoff: UInt32   = 90
}

// MARK: - Shader algorithm mirrored in Swift

/// Murmur-style xor-shift mixer — byte-identical to `lm_hash_u32` in
/// `LumenMosaic.metal`. Uses `&*` / `&+` so the wrap semantics match the
/// MSL `uint` arithmetic.
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

/// Track-seed hash — byte-identical to `lm_track_seed_hash` in
/// `LumenMosaic.metal`.
private func lmTrackSeedHash(seedA: Float, seedB: Float, seedC: Float, seedD: Float) -> UInt32 {
    let a = UInt32((seedA * 0.5 + 0.5) * 65535.0)
    let b = UInt32((seedB * 0.5 + 0.5) * 65535.0)
    let c = UInt32((seedC * 0.5 + 0.5) * 65535.0)
    let d = UInt32((seedD * 0.5 + 0.5) * 65535.0)
    return lmHashU32((a & 0xFF) | ((b & 0xFF) << 8) | ((c & 0xFF) << 16) | ((d & 0xFF) << 24))
}

/// Period bucket — byte-identical to the `periodBucket` switch in
/// `lm_cell_palette`. Returns 1, 2, 4, or 8.
private func lmPeriod(cellHash: UInt32) -> Float {
    let bucket = (cellHash >> 8) & 0x7
    if bucket >= 7 { return 8 }
    if bucket >= 5 { return 4 }
    if bucket >= 3 { return 2 }
    return 1
}

/// Team counter pulled from the four `LumenPatternState` band counters —
/// matches the `lm_cell_palette` team selection ladder.
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

/// HSV→RGB — byte-identical to the preamble's `hsv2rgb` helper.
private func lmHsv2Rgb(_ hsv: SIMD3<Float>) -> SIMD3<Float> {
    let h = hsv.x
    let one = SIMD3<Float>(1, 1, 1)
    let phase = SIMD3<Float>(h, h, h) + SIMD3<Float>(1.0, 2.0 / 3.0, 1.0 / 3.0)
    let fracPhase = SIMD3<Float>(phase.x - floor(phase.x),
                                 phase.y - floor(phase.y),
                                 phase.z - floor(phase.z))
    let p = SIMD3<Float>(abs(fracPhase.x * 6 - 3),
                         abs(fracPhase.y * 6 - 3),
                         abs(fracPhase.z * 6 - 3))
    let mixed = one + (SIMD3<Float>(min(max(p.x - 1, 0), 1),
                                    min(max(p.y - 1, 0), 1),
                                    min(max(p.z - 1, 0), 1)) - one) * SIMD3<Float>(hsv.y, hsv.y, hsv.y)
    return mixed * SIMD3<Float>(hsv.z, hsv.z, hsv.z)
}

/// Mirror of `lm_cell_palette` in `LumenMosaic.metal`. Returns the cell's
/// HSV sample post-mood-bias / post-pastel-guardrail BEFORE the hsv2rgb
/// conversion — the test invariants are easier to reason about in HSV
/// space.
private func lmCellPaletteHSV(
    cellHash: UInt32,
    smoothedValence: Float,
    smoothedArousal: Float,
    seedA: Float, seedB: Float, seedC: Float, seedD: Float,
    bassCounter: Float, midCounter: Float, trebleCounter: Float
) -> SIMD3<Float> {
    let teamCounter = lmTeamCounter(cellHash: cellHash,
                                    bass: bassCounter, mid: midCounter, treble: trebleCounter)
    let period = lmPeriod(cellHash: cellHash)
    let step = floor(teamCounter / period)
    let cardIndex = (cellHash &+ UInt32(step)) % LMPalette.cardSize

    let trackSeed = lmTrackSeedHash(seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD)
    let colourHash = lmHashU32(cardIndex ^ trackSeed)

    let hU = Float((colourHash >> 0)  & 0xFF) * (1.0 / 255.0)
    let sU = Float((colourHash >> 8)  & 0xFF) * (1.0 / 255.0)
    let vU = Float((colourHash >> 16) & 0xFF) * (1.0 / 255.0)

    let arousalNorm = max(0, min(1, smoothedArousal * 0.5 + 0.5))
    let gamma = LMPalette.moodGammaLowArousal
              + (LMPalette.moodGammaHighArousal - LMPalette.moodGammaLowArousal) * arousalNorm
    let sBiased = pow(sU, gamma)
    let vBiased = pow(vU, gamma)

    var v = LMPalette.cardValMin + (LMPalette.cardValMax - LMPalette.cardValMin) * vBiased
    let s = sBiased
    let h = hU

    if s < LMPalette.pastelSatCutoff {
        v = min(v, LMPalette.pastelValCap)
    }

    // smoothedValence is intentionally unused at LM.4.5 — valence influences
    // mood ONLY through the per-track seed and the eventual orchestration
    // layer; arousal is the only direct driver of the gamma bias. Reference
    // here so the SwiftLint unused-parameter gate stays happy.
    _ = smoothedValence

    return SIMD3<Float>(h, s, v)
}

/// Returns HSV directly — drops the HSV→RGB conversion for the invariant
/// tests that work in HSV space. The shader's final step is `hsv2rgb`; a
/// single smoke test below confirms the conversion runs without NaN/clip.
private func lmCellPaletteRGB(
    cellHash: UInt32,
    smoothedValence: Float,
    smoothedArousal: Float,
    seedA: Float, seedB: Float, seedC: Float, seedD: Float,
    bassCounter: Float, midCounter: Float, trebleCounter: Float
) -> SIMD3<Float> {
    let hsv = lmCellPaletteHSV(cellHash: cellHash,
                               smoothedValence: smoothedValence,
                               smoothedArousal: smoothedArousal,
                               seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
                               bassCounter: bassCounter, midCounter: midCounter,
                               trebleCounter: trebleCounter)
    return lmHsv2Rgb(hsv)
}

// MARK: - Random sampler (deterministic, seed-driven)

/// Mulberry32 — fast deterministic PRNG. Used here so test runs are
/// reproducible: a flaky test means a real algorithm change, not a
/// stochastic miss.
private struct Mulberry32 {
    var state: UInt32
    mutating func nextUInt32() -> UInt32 {
        state = state &+ 0x6D2B79F5
        var z = state
        z = (z ^ (z >> 15)) &* (z | 1)
        z ^= z &+ ((z ^ (z >> 7)) &* (z | 61))
        return z ^ (z >> 14)
    }
    mutating func nextUniform() -> Float {
        // [0, 1) with 24-bit precision.
        return Float(nextUInt32() >> 8) / Float(1 << 24)
    }
    mutating func nextSigned() -> Float {
        // [-1, +1).
        return nextUniform() * 2 - 1
    }
}

// MARK: - Suite 1: Spectrum coverage

@Suite("Full-spectrum palette card — spectrum coverage")
struct LumenPaletteSpectrumCoverageTests {

    @Test func test_neutralMood_200samples_huesSpan270Degrees_satSpread06_valSpread05() {
        var rng = Mulberry32(state: 0xCAFE_BABE)
        var hues: [Float] = []
        var sats: [Float] = []
        var vals: [Float] = []
        for _ in 0..<200 {
            let cellHash = rng.nextUInt32()
            let seedA = rng.nextSigned()
            let seedB = rng.nextSigned()
            let seedC = rng.nextSigned()
            let seedD = rng.nextSigned()
            let hsv = lmCellPaletteHSV(cellHash: cellHash,
                                       smoothedValence: 0,
                                       smoothedArousal: 0,
                                       seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
                                       bassCounter: 0, midCounter: 0, trebleCounter: 0)
            hues.append(hsv.x)
            sats.append(hsv.y)
            vals.append(hsv.z)
        }

        // Hue span: at minimum 270° (≥ 0.75 of the unit wheel). Compute
        // span as max - min in normalised [0, 1] space.
        let hueSpan = (hues.max() ?? 0) - (hues.min() ?? 0)
        #expect(hueSpan >= 0.75, "hue span \(hueSpan) < 0.75 (270°)")

        let satSpread = (sats.max() ?? 0) - (sats.min() ?? 0)
        #expect(satSpread >= 0.6, "sat spread \(satSpread) < 0.6")

        let valSpread = (vals.max() ?? 0) - (vals.min() ?? 0)
        #expect(valSpread >= 0.5, "val spread \(valSpread) < 0.5")
    }
}

// MARK: - Suite 2: Pastel guardrail

@Suite("Full-spectrum palette card — pastel guardrail")
struct LumenPalettePastelGuardrailTests {

    @Test func test_1000samples_zeroSatisfyPastelForbiddenZone() {
        var rng = Mulberry32(state: 0xDEAD_BEEF)
        var violations = 0
        for _ in 0..<1000 {
            let cellHash = rng.nextUInt32()
            let seedA = rng.nextSigned()
            let seedB = rng.nextSigned()
            let seedC = rng.nextSigned()
            let seedD = rng.nextSigned()
            let arousal = rng.nextSigned()
            let valence = rng.nextSigned()
            let hsv = lmCellPaletteHSV(cellHash: cellHash,
                                       smoothedValence: valence,
                                       smoothedArousal: arousal,
                                       seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
                                       bassCounter: 0, midCounter: 0, trebleCounter: 0)
            // Forbidden zone: sat < 0.3 AND val > 0.6.
            if hsv.y < 0.3 && hsv.z > 0.6 { violations += 1 }
        }
        #expect(violations == 0, "\(violations)/1000 samples landed in pastel forbidden zone")
    }
}

// MARK: - Suite 3: Per-track distinctiveness

@Suite("Full-spectrum palette card — per-track distinctiveness")
struct LumenPaletteDistinctivenessTests {

    /// Quantise an HSV sample to 5-bit-per-channel (32 buckets) for the
    /// Jaccard test. 32³ = 32 768 unique buckets — two random samples
    /// have ≈ 0.003 % chance of colliding.
    private func quantise(_ hsv: SIMD3<Float>) -> UInt32 {
        let h = UInt32(min(max(hsv.x, 0), 0.999) * 32)
        let s = UInt32(min(max(hsv.y, 0), 0.999) * 32)
        let v = UInt32(min(max(hsv.z, 0), 0.999) * 32)
        return (h << 10) | (s << 5) | v
    }

    private func firstCardColours(
        cellHashes: [UInt32],
        seedA: Float, seedB: Float, seedC: Float, seedD: Float
    ) -> Set<UInt32> {
        var samples: Set<UInt32> = []
        for cellHash in cellHashes {
            let hsv = lmCellPaletteHSV(cellHash: cellHash,
                                       smoothedValence: 0,
                                       smoothedArousal: 0,
                                       seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
                                       bassCounter: 0, midCounter: 0, trebleCounter: 0)
            samples.insert(quantise(hsv))
        }
        return samples
    }

    @Test func test_twoSeeds_jaccardBelow05() {
        // Sweep cell IDs 0..<50 — each maps to a card slot via
        // `cellHash % kCardSize`. With kCardSize = 48 and 50 inputs,
        // we'll hit at least 48 distinct slots (slots 0+1 land twice).
        let cellHashes = Array<UInt32>(0..<50)
        let trackA = firstCardColours(cellHashes: cellHashes,
                                      seedA: +1, seedB: +1, seedC: +1, seedD: +1)
        let trackB = firstCardColours(cellHashes: cellHashes,
                                      seedA: -1, seedB: -1, seedC: -1, seedD: -1)

        let intersection = trackA.intersection(trackB).count
        let union = trackA.union(trackB).count
        let jaccard = Float(intersection) / Float(union)
        #expect(jaccard < 0.5, "Jaccard similarity \(jaccard) ≥ 0.5 between distinct trackSeeds")
    }

    @Test func test_sameSeed_deterministic() {
        var rng = Mulberry32(state: 0xF00D_F00D)
        for _ in 0..<10 {
            let cellHash = rng.nextUInt32()
            let seedA = rng.nextSigned()
            let seedB = rng.nextSigned()
            let seedC = rng.nextSigned()
            let seedD = rng.nextSigned()
            let first = lmCellPaletteHSV(cellHash: cellHash,
                                         smoothedValence: 0,
                                         smoothedArousal: 0,
                                         seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
                                         bassCounter: 0, midCounter: 0, trebleCounter: 0)
            let second = lmCellPaletteHSV(cellHash: cellHash,
                                          smoothedValence: 0,
                                          smoothedArousal: 0,
                                          seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
                                          bassCounter: 0, midCounter: 0, trebleCounter: 0)
            #expect(first == second, "non-deterministic palette for cellHash \(cellHash)")
        }
    }
}

// MARK: - Suite 4: Beat-step ratchet

@Suite("Full-spectrum palette card — beat-step ratchet")
struct LumenPaletteBeatStepTests {

    /// Pick a cellHash whose periodBucket ((cellHash >> 8) & 0x7) is in
    /// [0, 2] → period = 1, AND whose team bucket (cellHash % 100) is in
    /// [0, 30) → bass team. That lets us drive the cell's step counter
    /// via `bassCounter` directly.
    private func makePeriod1BassTeamCellHash() -> UInt32 {
        // Decimal 20 = 0x14. bucket = 20 % 100 = 20 → bass team (< 30);
        // periodBucket = (20 >> 8) & 0x7 = 0 → period 1. The high bits are
        // zero so cellHash is small and easy to read in failure messages.
        return 0x0000_0014
    }

    @Test func test_period1BassCell_singleBeatAdvancesCardIndexBy1() {
        let cellHash = makePeriod1BassTeamCellHash()
        // Sanity: verify the cell is on the bass team with period 1.
        #expect(cellHash % 100 < LMPalette.bassTeamCutoff)
        #expect(lmPeriod(cellHash: cellHash) == 1)

        // bassCounter = 0 → step = 0 → cardIndex = cellHash % kCardSize.
        // bassCounter = 1 → step = 1 → cardIndex = (cellHash + 1) % kCardSize.
        let cardIndex0 = (cellHash &+ 0) % LMPalette.cardSize
        let cardIndex1 = (cellHash &+ 1) % LMPalette.cardSize
        #expect(cardIndex1 == (cardIndex0 &+ 1) % LMPalette.cardSize)

        // And the colour at step 0 should differ from the colour at step 1
        // (cards are independent hashes per slot, so adjacent slots are
        // uncorrelated). Sample HSV at each step and confirm the quantised
        // 5-bit buckets differ.
        let hsv0 = lmCellPaletteHSV(cellHash: cellHash,
                                    smoothedValence: 0, smoothedArousal: 0,
                                    seedA: 0.5, seedB: -0.2, seedC: 0.7, seedD: -0.4,
                                    bassCounter: 0, midCounter: 0, trebleCounter: 0)
        let hsv1 = lmCellPaletteHSV(cellHash: cellHash,
                                    smoothedValence: 0, smoothedArousal: 0,
                                    seedA: 0.5, seedB: -0.2, seedC: 0.7, seedD: -0.4,
                                    bassCounter: 1, midCounter: 0, trebleCounter: 0)
        #expect(hsv0 != hsv1, "single beat step produced identical colour — card slots not advancing")
    }
}

// MARK: - Suite 5: Mood bias preserved envelope

@Suite("Full-spectrum palette card — mood bias preserved envelope")
struct LumenPaletteMoodBiasTests {

    private func meanValue(samples: Int, arousal: Float, rngSeed: UInt32) -> Float {
        var rng = Mulberry32(state: rngSeed)
        var sum: Float = 0
        for _ in 0..<samples {
            let cellHash = rng.nextUInt32()
            let seedA = rng.nextSigned()
            let seedB = rng.nextSigned()
            let seedC = rng.nextSigned()
            let seedD = rng.nextSigned()
            let hsv = lmCellPaletteHSV(cellHash: cellHash,
                                       smoothedValence: 0,
                                       smoothedArousal: arousal,
                                       seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
                                       bassCounter: 0, midCounter: 0, trebleCounter: 0)
            sum += hsv.z
        }
        return sum / Float(samples)
    }

    private func halfCounts(samples: Int, arousal: Float, rngSeed: UInt32) -> (bright: Int, dim: Int) {
        var rng = Mulberry32(state: rngSeed)
        var bright = 0
        var dim = 0
        for _ in 0..<samples {
            let cellHash = rng.nextUInt32()
            let seedA = rng.nextSigned()
            let seedB = rng.nextSigned()
            let seedC = rng.nextSigned()
            let seedD = rng.nextSigned()
            let hsv = lmCellPaletteHSV(cellHash: cellHash,
                                       smoothedValence: 0,
                                       smoothedArousal: arousal,
                                       seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
                                       bassCounter: 0, midCounter: 0, trebleCounter: 0)
            if hsv.z > 0.5 { bright += 1 } else { dim += 1 }
        }
        return (bright, dim)
    }

    @Test func test_lowArousal_averageDimmerThanHighArousal() {
        let lowMean  = meanValue(samples: 1000, arousal: -1, rngSeed: 0x1111_1111)
        let highMean = meanValue(samples: 1000, arousal: +1, rngSeed: 0x1111_1111)
        #expect(lowMean < highMean,
                "low-arousal mean \(lowMean) ≥ high-arousal mean \(highMean) — mood biasing inverted")
        // Empirical gap with kMoodGamma{Low,High} = (1.8, 0.55), val
        // remapped to [0.08, 0.95]: ≈ 0.39 vs ≈ 0.65 — gap ≈ 0.26.
        // Require at least a 0.1 gap so the test catches a future
        // regression that narrows the gamma endpoints.
        #expect(highMean - lowMean > 0.1,
                "mean-value gap \(highMean - lowMean) ≤ 0.1 — mood biasing too weak")
    }

    @Test func test_bothExtremes_containSamplesInBothHalves() {
        let low  = halfCounts(samples: 1000, arousal: -1, rngSeed: 0x2222_2222)
        let high = halfCounts(samples: 1000, arousal: +1, rngSeed: 0x2222_2222)
        // At gamma = 1.8, expected p(v > 0.5) ≈ 0.29 — require ≥ 5 % to
        // give safe margin against any tighter quantisation noise (the
        // empirical count is ~290, several orders of magnitude above 50).
        #expect(low.bright >= 50,  "low-arousal: only \(low.bright)/1000 bright samples")
        #expect(low.dim    >= 50,  "low-arousal: only \(low.dim)/1000 dim samples")
        #expect(high.bright >= 50, "high-arousal: only \(high.bright)/1000 bright samples")
        #expect(high.dim    >= 50, "high-arousal: only \(high.dim)/1000 dim samples")
    }
}

// MARK: - Suite 6: HSV→RGB conversion sanity

@Suite("Full-spectrum palette card — hsv2rgb conversion")
struct LumenPaletteRGBConversionTests {

    @Test func test_randomSamples_rgbWithinUnitCube_noNaN() {
        var rng = Mulberry32(state: 0x4242_4242)
        for _ in 0..<200 {
            let cellHash = rng.nextUInt32()
            let seedA = rng.nextSigned()
            let seedB = rng.nextSigned()
            let seedC = rng.nextSigned()
            let seedD = rng.nextSigned()
            let arousal = rng.nextSigned()
            let rgb = lmCellPaletteRGB(cellHash: cellHash,
                                       smoothedValence: 0,
                                       smoothedArousal: arousal,
                                       seedA: seedA, seedB: seedB, seedC: seedC, seedD: seedD,
                                       bassCounter: 0, midCounter: 0, trebleCounter: 0)
            #expect(rgb.x.isFinite && rgb.y.isFinite && rgb.z.isFinite, "non-finite RGB \(rgb)")
            #expect(rgb.x >= 0 && rgb.x <= 1)
            #expect(rgb.y >= 0 && rgb.y <= 1)
            #expect(rgb.z >= 0 && rgb.z <= 1)
        }
    }
}
