// RelDevTests — Contract tests for MV-1 deviation primitives in FeatureVector + StemFeatures.
//
// D-026 defines the rule: preset shaders must drive visuals from deviation-from-average
// (bassRel, bassDev, etc.) rather than absolute energy values (f.bass, f.bass_att).
//
// D-146 / BUG-027 (2026-06-05): the FeatureVector band deviations were derived against a FIXED
// 0.5 pivot, but the total-energy AGC centres each band well below 0.5 — so midDev/trebDev fired
// ~0% on all music (structural starvation, measured AGC2.1). The pivot is now each band's OWN
// running average (per-band EMA in BandDeviationTracker), mirroring StemAnalyzer's per-stem EMA.
// The contract tests below were updated to that semantics: the old `bassRel == (bass - 0.5) * 2`
// formula pin is replaced by `BandDeviationTracker` unit tests (the component that now owns the
// formula) + an integration check that `*Dev == max(0, *Rel)` still holds end-to-end, plus the
// BUG-027 firing gate on a recorded bass-dominant fixture.
//
// These tests pin the surviving invariants:
//   1. The deviation primitives are mix-density-stable (AGC amplitude-independence).
//   2. bassDev / midDev / trebDev are always non-negative — the positive-only invariant.
//   3. The band deviation pivots on each band's own running average (D-146 formula).
//   4. On recorded bass-dominant music the above-average primitive fires >= 20% (BUG-027 gate).
//   5. Stem energyDev fields are always non-negative.
//
// See docs/MILKDROP_ARCHITECTURE.md §2, docs/DECISIONS.md D-026 + D-146,
// docs/diagnostics/AGC2_1_DEVIATION_CENTRING_2026-06-05.md.

import Foundation
import Testing
import Shared
@testable import DSP

// MARK: - FeatureVector Rel/Dev Invariants

/// The AGC's amplitude-stability property: the same spectral shape played at
/// different loudnesses (2× amplitude difference) should produce bass values
/// within 0.15 of each other after convergence. This is the basis of the
/// deviation primitive's mix-density stability — `f.bass` (and therefore the
/// per-band running average it feeds) is level-independent (D-026).
@Test func bassRel_isStableAcrossAmplitudeChanges() {
    // Run two separate pipelines: identical spectral shape, 2× amplitude difference.
    let pipelineA = MIRPipeline()
    let pipelineB = MIRPipeline()

    // Bass-heavy spectrum: high energy in low bins, low energy in high bins.
    let loMags = (0..<512).map { i -> Float in
        let fraction = Float(i) / 512.0
        return 0.3 * max(0, 1.0 - fraction * 4.0)  // ramps down from bin 0
    }
    // Same spectral shape, 2× louder.
    let hiMags = loMags.map { $0 * 2.0 }

    // Warm up both AGCs for 500 frames (~8s).
    var bassA: Float = 0, bassB: Float = 0
    for i in 0..<500 {
        let t = Float(i) / 60.0
        let dt: Float = 1.0 / 60.0
        let fvA = pipelineA.process(magnitudes: loMags, fps: 60, time: t, deltaTime: dt)
        let fvB = pipelineB.process(magnitudes: hiMags, fps: 60, time: t, deltaTime: dt)
        if i >= 400 {
            bassA += fvA.bass
            bassB += fvB.bass
        }
    }
    bassA /= 100.0
    bassB /= 100.0

    // After AGC convergence, same spectral shape at 2× amplitude should produce
    // nearly the same bass value (AGC compensates for level).
    #expect(abs(bassA - bassB) < 0.15,
            "AGC should normalise bass to similar values across 2× amplitude shift: bassA=\(bassA) bassB=\(bassB) diff=\(abs(bassA - bassB))")

    // A pivot applied to amplitude-stable bass values is itself amplitude-stable —
    // the property that makes the deviation primitive mix-density-robust.
    let relA = (bassA - 0.5) * 2.0
    let relB = (bassB - 0.5) * 2.0
    #expect(abs(relA - relB) < 0.30,
            "the deviation should be stable across a 2× amplitude shift: relA=\(relA) relB=\(relB) diff=\(abs(relA - relB))")
}

/// bassDev must be non-negative for any input — it is defined as max(0, bassRel).
@Test func bassDev_alwaysNonNegative() {
    let pipeline = MIRPipeline()

    // Use varied magnitudes to exercise different energy levels.
    var anyViolation = false
    for i in 0..<200 {
        let amplitude = Float(i % 20) * 0.05  // cycles 0.0 → 0.95 repeatedly
        let mags = [Float](repeating: amplitude, count: 512)
        let fv = pipeline.process(magnitudes: mags, fps: 60, time: Float(i) / 60.0, deltaTime: 1.0 / 60.0)
        if fv.bassDev < 0 { anyViolation = true; break }
        if fv.midDev  < 0 { anyViolation = true; break }
        if fv.trebDev < 0 { anyViolation = true; break }
    }

    #expect(!anyViolation,
            "bassDev, midDev, trebDev must always be ≥ 0 (defined as max(0, xRel))")
}

/// The end-to-end derivation contract that survives the D-146 pivot change:
/// `*Dev == max(0, *Rel)` for every processed frame through the real pipeline.
@Test func featureVector_devEqualsMaxZeroRel() {
    let pipeline = MIRPipeline()
    let mags = (0..<512).map { i -> Float in 0.3 * max(0, 1.0 - Float(i) / 512.0 * 4.0) }
    for i in 0..<60 {
        let fv = pipeline.process(magnitudes: mags, fps: 60, time: Float(i) / 60.0, deltaTime: 1.0 / 60.0)
        #expect(fv.bassDev == max(0, fv.bassRel), "Frame \(i): bassDev must equal max(0, bassRel)")
        #expect(fv.midDev  == max(0, fv.midRel),  "Frame \(i): midDev must equal max(0, midRel)")
        #expect(fv.trebDev == max(0, fv.trebRel), "Frame \(i): trebDev must equal max(0, trebRel)")
    }
}

// MARK: - BandDeviationTracker (D-146 / BUG-027)

/// Build a BandEnergies input with the attenuated bands mirroring the instant bands (sufficient
/// for these unit tests, which exercise the instant-band deviation contract).
private func bands(_ b: Float, _ m: Float, _ t: Float) -> BandDeviationTracker.BandEnergies {
    BandDeviationTracker.BandEnergies(bass: b, mid: m, treble: t, bassAtt: b, midAtt: m, trebleAtt: t)
}

/// The D-146 derivation contract: each band's `*Rel` equals `(value - that band's running
/// average) * 2`, and `*Dev` equals `max(0, *Rel)`. This replaces the retired fixed-0.5
/// formula pin (`bassRel == (bass - 0.5) * 2`).
@Test func bandDeviation_pivotsOnPerBandEMA() {
    var tracker = BandDeviationTracker()
    let frames: [(Float, Float, Float)] = [(0.3, 0.1, 0.02), (0.5, 0.05, 0.01), (0.2, 0.2, 0.03)]
    for (b, m, t) in frames {
        let out = tracker.derive(bands(b, m, t))
        let avg = tracker.runningAvg
        #expect(out.bassRel == (b - avg[0]) * 2.0, "bassRel must pivot on the bass running average")
        #expect(out.midRel  == (m - avg[1]) * 2.0, "midRel must pivot on the mid running average")
        #expect(out.trebRel == (t - avg[2]) * 2.0, "trebRel must pivot on the treble running average")
        #expect(out.bassDev == max(0, out.bassRel))
        #expect(out.midDev  == max(0, out.midRel))
        #expect(out.trebDev == max(0, out.trebRel))
    }
}

/// Seed-from-first-non-zero (SAR.1): the first post-reset frame's deviation is ~0, not 2× the
/// value — avoids the cold-start deviation inflation at every track change.
@Test func bandDeviation_firstFrameDeviationIsZero() {
    var tracker = BandDeviationTracker()
    let out = tracker.derive(bands(0.4, 0.3, 0.05))
    #expect(abs(out.bassRel) < 1e-5, "first-frame bassRel should seed to ~0, got \(out.bassRel)")
    #expect(abs(out.midRel)  < 1e-5, "first-frame midRel should seed to ~0, got \(out.midRel)")
    #expect(abs(out.trebRel) < 1e-5, "first-frame trebRel should seed to ~0, got \(out.trebRel)")
    #expect(out.bassDev == max(0, out.bassRel))
}

/// reset() clears the running averages (track change) so the next track's deviation is measured
/// against its own audio, re-seeding to ~0 on the first frame.
@Test func bandDeviation_resetClearsRunningAverage() {
    var tracker = BandDeviationTracker()
    _ = tracker.derive(bands(0.4, 0.3, 0.05))
    #expect(tracker.runningAvg.contains { $0 > 0 }, "running average should be seeded after a frame")
    tracker.reset()
    #expect(tracker.runningAvg.allSatisfy { $0 == 0 }, "reset must clear all running averages to sentinel 0")
    let out = tracker.derive(bands(0.6, 0.1, 0.02))
    #expect(abs(out.bassRel) < 1e-5, "first frame after reset should re-seed to ~0")
}

/// BUG-027 gate: on a recorded bass-dominant fixture the above-average bass primitive must fire on
/// >= 20% of frames (the fixed-0.5 pivot fired ~7% on this exact data). Fixture = 360 consecutive
/// AGC-normalised `bass` values from a Local-File Atlas (Battles) session, post-cold-start, deduped
/// to analysis cadence. See docs/diagnostics/AGC2_1_DEVIATION_CENTRING_2026-06-05.md.
@Test func bandDeviation_firesAboveOwnAverage_onRecordedBass() {
    let bass = BandDeviationFixtures.atlasBass
    #expect(bass.count == 360, "fixture must parse to 360 values, got \(bass.count)")

    // The retired fixed-0.5 pivot on this exact data (documents the BUG-027 starvation).
    let oldFires = bass.filter { ($0 - 0.5) * 2.0 > 1e-4 }.count
    let oldRate = Double(oldFires) / Double(bass.count)
    #expect(oldRate < 0.10, "fixed-0.5 pivot fires \(oldRate * 100)% — the BUG-027 starvation it replaces")

    // The D-146 per-band EMA pivot: fires when bass is above its own recent average.
    var tracker = BandDeviationTracker()
    var newFires = 0
    for b in bass {
        let out = tracker.derive(bands(b, 0, 0))
        if out.bassDev > 1e-4 { newFires += 1 }
    }
    let newRate = Double(newFires) / Double(bass.count)
    #expect(newRate >= 0.20,
            "per-band EMA pivot must fire >= 20% on recorded bass-dominant music (BUG-027 gate); got \(newRate * 100)%")
}

/// AGC2.4.1 — the band running average must RECOVER from a cold-start spike within the warmup
/// window, not stay poisoned for minutes. At session start the first audio after silence explodes
/// the AGC scale (the live M7 saw bass = 3.688 vs a normal ~0.25); seeding the slow-only EMA from
/// that spike left bassDev ~0% for ~3-4 minutes. Feeds a spike then steady dynamic bass and asserts
/// bassDev fires in the late window.
@Test func bandDeviation_recoversFromColdStartSpike() {
    var tracker = BandDeviationTracker()
    func bassVal(_ i: Int) -> Float {
        if i == 0 { return 3.7 }                                   // the seed spike (AGC cold-start)
        if i < 8 { return [1.4, 0.7, 1.1, 0.5, 0.9, 0.4, 0.6][i - 1] }   // spike tail
        return 0.25 + 0.12 * sin(Float(i) * 0.3)                    // steady dynamic bass ~0.13..0.37
    }
    var lateFires = 0, lateN = 0
    for i in 0..<400 {
        let out = tracker.derive(bands(bassVal(i), 0, 0))
        if i >= 250 { lateN += 1; if out.bassDev > 1e-4 { lateFires += 1 } }
    }
    let rate = Double(lateFires) / Double(lateN)
    #expect(rate > 0.20,
            "bassDev must recover after a cold-start spike (got \(rate * 100)% in the late window); the warmup must converge the EMA off the spike")
}

/// AGC2.4.1 / FA #66 — cold-start recovery through the LIVE MIRPipeline.process path (the path the
/// AGC2.3 unit tests + offline replay bypassed, which is why the cold-start hole shipped). A session
/// starts with silence, so the AGC seeds low and the first audio explodes the band scale; the band
/// average must recover so deviations fire within a few seconds, not stay suppressed for minutes.
@Test func bandDeviation_recoversFromColdStart_liveMIRPipeline() {
    let pipeline = MIRPipeline()
    func bassMags(_ amp: Float) -> [Float] { (0..<512).map { $0 < 6 ? amp : Float(0.0) } }
    var lateFires = 0, lateN = 0
    for i in 0..<600 {
        // 30 frames of true silence → the AGC seeds ~0; then a sudden dynamic bass onset explodes
        // the AGC scale (the real cold-start spike). The band average must recover by the late window.
        let amp: Float = i < 30 ? 0.0 : 0.22 + 0.14 * sin(Float(i) * 0.22)
        let fv = pipeline.process(magnitudes: bassMags(amp), fps: 60, time: Float(i) / 60.0, deltaTime: 1.0 / 60.0)
        if i >= 400 { lateN += 1; if fv.bassDev > 1e-4 { lateFires += 1 } }
    }
    let rate = Double(lateFires) / Double(lateN)
    #expect(rate > 0.15,
            "bassDev must recover after the live cold-start spike (got \(rate * 100)% in the late window) — AGC2.4.1")
}

// MARK: - StemFeatures Rel/Dev Invariants

/// Stem energyDev fields must always be non-negative — they are max(0, energyRel).
@Test func stemEnergyDev_alwaysNonNegative() {
    let analyzer = StemAnalyzer(sampleRate: 44100)

    // Generate four stem waveforms with varying amplitudes.
    func makeWaveform(amplitude: Float, count: Int = 1024) -> [Float] {
        (0..<count).map { i in amplitude * sin(Float(i) * 0.05) }
    }

    var anyViolation = false
    for i in 0..<150 {
        let amp = Float(i % 15) * 0.07   // cycles 0.0 → 0.98 repeatedly
        let stems = [
            makeWaveform(amplitude: amp * 1.0),
            makeWaveform(amplitude: amp * 0.8),
            makeWaveform(amplitude: amp * 1.2),
            makeWaveform(amplitude: amp * 0.6),
        ]
        let sf = analyzer.analyze(stemWaveforms: stems, fps: 60)
        if sf.vocalsEnergyDev < 0 { anyViolation = true; break }
        if sf.drumsEnergyDev  < 0 { anyViolation = true; break }
        if sf.bassEnergyDev   < 0 { anyViolation = true; break }
        if sf.otherEnergyDev  < 0 { anyViolation = true; break }
    }

    #expect(!anyViolation,
            "vocalsEnergyDev, drumsEnergyDev, bassEnergyDev, otherEnergyDev must always be ≥ 0")
}

// MARK: - Recorded fixture

/// Recorded bass-dominant fixture for the BUG-027 firing gate. 360 consecutive AGC-normalised
/// `bass` values, Local-File Atlas (Battles) session 2026-06-05T14-35-14Z, post-cold-start,
/// deduped to analysis cadence. Real data per Failed Approach #27 (no synthetic audio).
private enum BandDeviationFixtures {
    static let atlasBass: [Float] = raw.split(separator: ",").compactMap { Float($0) }

    private static let raw = "0.310,0.508,0.342,0.625,0.392,0.384,0.287,0.841,0.635,0.276,0.355,0.292,0.357,0.312,0.265,0.295,0.594,0.342,0.257,0.240,0.437,0.326,0.270,0.472,0.260,0.496,0.255,0.177,0.203,0.565,0.426,0.196,0.387,0.190,0.353,0.183,0.217,0.138,0.618,0.306,0.273,0.258,0.175,0.404,0.204,0.340,0.224,0.422,0.219,0.222,0.210,0.288,0.218,0.205,0.336,0.182,0.374,0.252,0.207,0.156,0.394,0.437,0.458,0.634,0.322,0.482,0.314,0.202,0.156,0.574,0.328,0.264,0.265,0.167,0.402,0.198,0.243,0.158,0.445,0.237,0.235,0.223,0.346,0.394,0.169,0.225,0.168,0.345,0.213,0.166,0.193,0.385,0.390,0.175,0.238,0.113,0.322,0.181,0.201,0.197,0.643,0.317,0.233,0.268,0.236,0.303,0.164,0.229,0.359,0.544,0.277,0.167,0.358,0.204,0.415,0.194,0.287,0.318,0.391,0.522,0.285,0.418,0.512,0.335,0.247,0.522,0.382,0.410,0.614,0.503,0.392,0.533,0.302,0.410,0.811,0.351,0.503,0.234,0.404,0.372,0.437,0.334,0.194,0.363,0.231,0.207,0.164,0.230,0.463,0.455,0.276,0.180,0.263,0.356,0.274,0.271,0.334,0.413,0.441,0.211,0.242,0.422,0.356,0.194,0.198,0.367,0.317,0.250,0.175,0.192,0.173,0.594,0.316,0.196,0.425,0.170,0.324,0.179,0.190,0.222,0.424,0.230,0.304,0.610,0.318,0.301,0.386,0.387,0.308,0.457,0.242,0.317,0.217,0.291,0.257,0.211,0.463,0.292,0.463,0.230,0.288,0.355,0.496,0.360,0.440,0.398,0.228,0.462,0.252,0.126,0.253,0.380,0.287,0.223,0.266,0.155,0.378,0.228,0.227,0.388,0.492,0.348,0.378,0.271,0.185,0.354,0.184,0.236,0.342,0.386,0.244,0.180,0.138,0.242,0.223,0.166,0.262,0.213,0.225,0.169,0.145,0.227,0.554,0.283,0.219,0.339,0.275,0.210,0.100,0.101,0.204,0.428,0.208,0.338,0.571,0.349,0.345,0.351,0.340,0.245,0.274,0.336,0.247,0.349,0.503,0.278,0.377,0.412,0.432,0.257,0.328,0.352,0.358,0.313,0.355,0.350,0.388,0.401,0.551,0.210,0.144,0.158,0.310,0.198,0.217,0.257,0.138,0.255,0.205,0.234,0.258,0.371,0.205,0.290,0.304,0.167,0.304,0.157,0.259,0.337,0.202,0.281,0.236,0.423,0.227,0.185,0.157,0.213,0.230,0.199,0.121,0.203,0.502,0.253,0.244,0.360,0.244,0.217,0.268,0.133,0.223,0.327,0.266,0.240,0.364,0.189,0.298,0.241,0.199,0.308,0.435,0.218,0.181,0.320,0.238,0.264,0.221,0.259,0.192,0.346,0.191,0.185,0.286,0.239,0.324,0.371,0.343,0.290,0.421,0.182,0.195,0.228,0.229,0.191,0.220,0.330,0.182,0.279,0.131,0.148"
}
