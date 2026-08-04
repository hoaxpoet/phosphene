// SpectralAnalyzerTests — Unit tests for spectral centroid, rolloff, and flux.
// Uses synthetic magnitude arrays (no Metal/FFTProcessor dependency).

import Testing
import Foundation
@testable import DSP

// MARK: - Centroid Tests

@Test func centroid_silence_isZero() {
    let analyzer = SpectralAnalyzer()
    let magnitudes = [Float](repeating: 0, count: 512)
    let result = analyzer.process(magnitudes: magnitudes)
    #expect(result.centroid == 0, "Centroid of silence should be 0")
}

@Test func centroid_lowFreqSine_belowMidpoint() {
    let analyzer = SpectralAnalyzer()
    // Energy at bin 5 ≈ 234 Hz (well below Nyquist midpoint of 12000 Hz)
    let magnitudes = AudioFixtures.syntheticMagnitudes(peaks: [(bin: 5, magnitude: 1.0)])
    let result = analyzer.process(magnitudes: magnitudes)

    let nyquistMidpoint: Float = 48000.0 / 4.0  // 12000 Hz
    #expect(result.centroid < nyquistMidpoint,
            "Centroid of low-frequency signal (\(result.centroid) Hz) should be below \(nyquistMidpoint) Hz")
    #expect(result.centroid > 0, "Centroid should be positive for non-silent input")
}

@Test func centroid_highFreqSine_aboveMidpoint() {
    let analyzer = SpectralAnalyzer()
    // Energy at bin 300 ≈ 14062 Hz (above Nyquist midpoint of 12000 Hz)
    let magnitudes = AudioFixtures.syntheticMagnitudes(peaks: [(bin: 300, magnitude: 1.0)])
    let result = analyzer.process(magnitudes: magnitudes)

    let nyquistMidpoint: Float = 48000.0 / 4.0  // 12000 Hz
    #expect(result.centroid > nyquistMidpoint,
            "Centroid of high-frequency signal (\(result.centroid) Hz) should be above \(nyquistMidpoint) Hz")
}

// MARK: - Rolloff Tests

@Test func rolloff_silence_isZero() {
    let analyzer = SpectralAnalyzer()
    let magnitudes = [Float](repeating: 0, count: 512)
    let result = analyzer.process(magnitudes: magnitudes)
    #expect(result.rolloff == 0, "Rolloff of silence should be 0")
}

@Test func rolloff_fullBandNoise_near85Percent() {
    let analyzer = SpectralAnalyzer()
    // Uniform magnitudes across all bins — rolloff should be near 85% of bandwidth.
    let magnitudes = AudioFixtures.uniformMagnitudes()
    let result = analyzer.process(magnitudes: magnitudes)

    // Nyquist = 24000 Hz. 85% of that = 20400 Hz.
    // With uniform energy, rolloff should land near bin 435 (85% of 512) ≈ 20390 Hz.
    let nyquist: Float = 48000.0 / 2.0
    let expected85 = nyquist * 0.85
    let tolerance: Float = nyquist * 0.05  // 5% tolerance
    #expect(abs(result.rolloff - expected85) < tolerance,
            "Rolloff for uniform noise (\(result.rolloff) Hz) should be near \(expected85) Hz")
}

// MARK: - Flux Tests

@Test func flux_steadySignal_nearZero() {
    let analyzer = SpectralAnalyzer()
    let magnitudes = AudioFixtures.syntheticMagnitudes(peaks: [(bin: 50, magnitude: 0.8)])

    // First frame has no previous — flux is 0.
    _ = analyzer.process(magnitudes: magnitudes)
    // Second frame with identical input — flux should be 0.
    let result = analyzer.process(magnitudes: magnitudes)
    #expect(result.flux < 0.001, "Flux of steady signal should be near zero, got \(result.flux)")
}

@Test func flux_suddenOnset_highValue() {
    let analyzer = SpectralAnalyzer()

    // First frame: silence.
    let silence = [Float](repeating: 0, count: 512)
    _ = analyzer.process(magnitudes: silence)

    // Second frame: loud signal — flux should be high.
    let loud = AudioFixtures.uniformMagnitudes(magnitude: 1.0)
    let result = analyzer.process(magnitudes: loud)
    #expect(result.flux > 100, "Flux after sudden onset should be high, got \(result.flux)")
}

// MARK: - Determinism

@Test func allFeatures_deterministic_sameInput_sameOutput() {
    let magnitudes = AudioFixtures.syntheticMagnitudes(peaks: [
        (bin: 10, magnitude: 0.5),
        (bin: 100, magnitude: 0.8),
        (bin: 300, magnitude: 0.3),
    ])

    let analyzer1 = SpectralAnalyzer()
    _ = analyzer1.process(magnitudes: [Float](repeating: 0, count: 512))
    let result1 = analyzer1.process(magnitudes: magnitudes)

    let analyzer2 = SpectralAnalyzer()
    _ = analyzer2.process(magnitudes: [Float](repeating: 0, count: 512))
    let result2 = analyzer2.process(magnitudes: magnitudes)

    #expect(result1.centroid == result2.centroid, "Centroid should be deterministic")
    #expect(result1.rolloff == result2.rolloff, "Rolloff should be deterministic")
    #expect(result1.flux == result2.flux, "Flux should be deterministic")
}

// MARK: - Spectral Density (DYN.1)

// The field exists because NOTHING else in the pipeline can express "the mix got
// bigger" on a limited master. Measured on session 2026-08-04T14-58-10Z (Cherub
// Rock): RMS is flat at −14 dBFS from 24 s to the end of the track, while the
// energy fraction above 1.5 kHz runs 0.084–0.10 through the verse and rises to
// 0.14–0.22 once the distorted guitar enters. Distortion adds harmonics, not
// amplitude. These tests pin the definition that makes that measurable.

@Test func density_silence_isZero() {
    let analyzer = SpectralAnalyzer()
    let result = analyzer.process(magnitudes: [Float](repeating: 0, count: 512))
    #expect(result.density == 0, "density of silence must be 0, not a divide artefact")
}

/// `density` is EMA-smoothed (τ≈6 s), so these settle it rather than reading one frame.
/// That smoothing is load-bearing: the raw per-frame fraction turns 5.59 times a second
/// and shipping it made the trunk visibly bounce.
private func settledDensity(_ magnitudes: [Float], frames: Int = 4000) -> Float {
    let analyzer = SpectralAnalyzer()
    var last: Float = 0
    for _ in 0..<frames { last = analyzer.process(magnitudes: magnitudes).density }
    return last
}

@Test func density_lowFrequencyOnly_isNearZero() {
    // Bin 5 ≈ 234 Hz — bass register, far below the 1.5 kHz split.
    let value = settledDensity(AudioFixtures.syntheticMagnitudes(peaks: [(bin: 5, magnitude: 1.0)]))
    #expect(value < 0.01, "a bass-only spectrum must read as low density (got \(value))")
}

@Test func density_highFrequencyOnly_isNearOne() {
    // Bin 200 ≈ 9.4 kHz — well above the split.
    let value = settledDensity(AudioFixtures.syntheticMagnitudes(peaks: [(bin: 200, magnitude: 1.0)]))
    #expect(value > 0.95, "a treble-only spectrum must read as high density (got \(value))")
}

/// THE ONE THAT MATTERS: density must be SCALE-INVARIANT.
///
/// This is the whole reason the field is computed in `SpectralAnalyzer` from raw
/// magnitudes rather than downstream. Every other band field is flattened by the
/// total-energy AGC and `BandDeviationTracker`'s per-band EMA — measured, the band
/// RATIOS are flattened too (`treble/(bass+mid+treble)` correlates −0.229 with real
/// HF content, moving OPPOSITE to it). A ratio taken before any of that cancels a
/// scalar gain exactly, which is what lets this survive.
@Test func density_isInvariantToOverallGain() {
    let shape: [(bin: Int, magnitude: Float)] = [(bin: 5, magnitude: 1.0), (bin: 200, magnitude: 0.5)]
    let quietValue = settledDensity(AudioFixtures.syntheticMagnitudes(peaks: shape))
    let loudValue = settledDensity(
        AudioFixtures.syntheticMagnitudes(peaks: shape.map { (bin: $0.bin, magnitude: $0.magnitude * 40) }))
    #expect(abs(quietValue - loudValue) < 1e-5, """
        density changed by \(abs(quietValue - loudValue)) under a pure \
        40× gain. It must not: a scalar gain has to cancel in the ratio, or the field is \
        just another level measure and cannot do the job it was added for.
        """)
}

/// Density must RISE when harmonics are added at constant low-end — the distorted
/// guitar case, stated as a test rather than as a hope.
@Test func density_risesWhenHarmonicsAreAdded() {
    let fundamental: [(bin: Int, magnitude: Float)] = [(bin: 8, magnitude: 1.0)]
    let cleanValue = settledDensity(AudioFixtures.syntheticMagnitudes(peaks: fundamental))
    // Same fundamental, plus a harmonic series above the split — distortion.
    let withHarmonics = fundamental + (4...12).map { (bin: $0 * 40, magnitude: Float(0.25)) }
    let dirtyValue = settledDensity(AudioFixtures.syntheticMagnitudes(peaks: withHarmonics))
    #expect(dirtyValue > cleanValue + 0.2, """
        adding a harmonic series above 1.5 kHz moved density only \
        \(dirtyValue - cleanValue). This is the exact signal the field \
        exists to carry (Matt: "when the distorted guitar enters the mix, the volume \
        increases, but the tree does not grow").
        """)
}
