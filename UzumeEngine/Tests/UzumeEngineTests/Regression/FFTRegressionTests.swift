// FFTRegressionTests — Golden-value regression tests for FFT processing.
// Compares current FFTProcessor output against saved fixture data to catch
// silent changes to FFT windowing, normalization, or bin layout.

import Testing
import Accelerate
import Foundation
import Metal
@testable import Audio
@testable import Shared

// MARK: - FFT Golden-Value Regression

@Test func fft440Hz_matchesGoldenOutput() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw FFTRegressionError.noMetalDevice
    }

    // Load golden fixtures.
    let sineSamples = try loadFixture("440hz_sine_4800")
    let expectedMagnitudes = try loadFixture("440hz_fft_expected")

    #expect(sineSamples.count == 4800, "Sine fixture should have 4800 samples")
    #expect(expectedMagnitudes.count == 512, "FFT fixture should have 512 bins")

    // Process the first 1024 samples through FFTProcessor (same as golden generation).
    let fftProcessor = try FFTProcessor(device: device)
    let inputSamples = Array(sineSamples.prefix(1024))
    fftProcessor.process(samples: inputSamples, sampleRate: 48000)

    // Compare each bin against the golden reference.
    var maxDiff: Float = 0
    var maxDiffBin = 0
    for i in 0..<512 {
        let actual = fftProcessor.magnitudeBuffer[i]
        let expected = expectedMagnitudes[i]
        let diff = abs(actual - expected)
        if diff > maxDiff {
            maxDiff = diff
            maxDiffBin = i
        }
    }

    #expect(maxDiff < 0.0001,
            "Max absolute difference should be < 0.0001, got \(maxDiff) at bin \(maxDiffBin)")
}

@Test func fft440Hz_peakBinIsStable() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw FFTRegressionError.noMetalDevice
    }

    // Load golden fixture to find expected peak bin.
    let expectedMagnitudes = try loadFixture("440hz_fft_expected")
    var expectedPeakBin = 0
    var expectedPeakMag: Float = 0
    for i in 0..<expectedMagnitudes.count {
        if expectedMagnitudes[i] > expectedPeakMag {
            expectedPeakMag = expectedMagnitudes[i]
            expectedPeakBin = i
        }
    }

    // Process the same sine wave through FFTProcessor.
    let sineSamples = try loadFixture("440hz_sine_4800")
    let fftProcessor = try FFTProcessor(device: device)
    fftProcessor.process(samples: Array(sineSamples.prefix(1024)), sampleRate: 48000)

    // Find actual peak bin.
    var actualPeakBin = 0
    var actualPeakMag: Float = 0
    for i in 0..<512 {
        let mag = fftProcessor.magnitudeBuffer[i]
        if mag > actualPeakMag {
            actualPeakMag = mag
            actualPeakBin = i
        }
    }

    #expect(actualPeakBin == expectedPeakBin,
            "Peak bin should be \(expectedPeakBin) (golden), got \(actualPeakBin) — FFT windowing or normalization may have changed")
    #expect(abs(actualPeakMag - expectedPeakMag) < 0.0001,
            "Peak magnitude should match golden reference within 0.0001")
}

// MARK: - Divergence Guard (BUG-066 / MOOD-FLUX.3)

/// The load-bearing mechanization guard: the live `FFTProcessor` and the shared
/// `FFTMagnitudeKernel` (which the offline `analyzeMIR` + census mirror call) MUST
/// produce bit-identical magnitudes for the same input. BUG-066 was a silent 16×
/// drift between two hand-copied magnitude formulas; this fails CI the moment a
/// second implementation reappears.
@Test func fftMagnitudeKernel_matchesLiveFFTProcessorBinForBin() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw FFTRegressionError.noMetalDevice
    }

    let sineSamples = try loadFixture("440hz_sine_4800")
    let input = Array(sineSamples.prefix(FFTProcessor.fftSize))

    // Live path.
    let fftProcessor = try FFTProcessor(device: device)
    fftProcessor.process(samples: input, sampleRate: 48000)
    let liveMags = (0..<FFTProcessor.binCount).map { fftProcessor.magnitudeBuffer[$0] }

    // Offline path: the exact scratch setup analyzeMIR / the census mirror use.
    let kernelMags = kernelMagnitudes(input)

    #expect(kernelMags == liveMags,
            "FFTMagnitudeKernel must be bit-identical to FFTProcessor — a divergence is BUG-066 reappearing")
}

/// Parity / no-behaviour-change: the shared kernel still matches the golden the
/// live pipeline produced (the MoodClassifier scaler is calibrated to this scale).
@Test func fftMagnitudeKernel_matchesGolden() throws {
    let sineSamples = try loadFixture("440hz_sine_4800")
    let expected = try loadFixture("440hz_fft_expected")
    let kernelMags = kernelMagnitudes(Array(sineSamples.prefix(1024)))

    var maxDiff: Float = 0
    for i in 0..<512 { maxDiff = max(maxDiff, abs(kernelMags[i] - expected[i])) }
    #expect(maxDiff < 0.0001, "Offline kernel drifted from golden — max diff \(maxDiff)")
}

/// Drive `FFTMagnitudeKernel` exactly as the offline paths do (raw 1024-sample
/// window in via the kernel's own scratch, magnitudes out).
private func kernelMagnitudes(_ input: [Float]) -> [Float] {
    guard let fft = try? FFTMagnitudeKernel(fftSize: 1024) else { return [] }
    fft.windowed.withUnsafeMutableBufferPointer { dst in
        dst.update(repeating: 0)
        for i in 0..<min(input.count, fft.fftSize) { dst[i] = input[i] }
    }
    fft.computeMagnitudes()
    return fft.magnitudes
}

// MARK: - Fixture Loading

private func loadFixture(_ name: String) throws -> [Float] {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw FFTRegressionError.fixtureNotFound(name)
    }
    let data = try Data(contentsOf: url)
    guard let doubles = try JSONSerialization.jsonObject(with: data) as? [Double] else {
        throw FFTRegressionError.fixtureParseError(name)
    }
    return doubles.map { Float($0) }
}

// MARK: - Errors

private enum FFTRegressionError: Error {
    case noMetalDevice
    case fixtureNotFound(String)
    case fixtureParseError(String)
}
