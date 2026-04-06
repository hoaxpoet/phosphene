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
