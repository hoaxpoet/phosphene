// FFTProcessorTests — Unit tests for FFT analysis pipeline.
// Split from AudioTests.swift for better organization.

import Testing
import Metal
@testable import Audio
@testable import Shared

// MARK: - FFTProcessor Tests

@Test func fftProcessorOutputBinCount() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw FFTProcessorTestError.noMetalDevice
    }

    let fft = try FFTProcessor(device: device)
    #expect(FFTProcessor.fftSize == 1024)
    #expect(FFTProcessor.binCount == 512)
    #expect(fft.magnitudeBuffer.capacity == 512)
}

@Test func fftProcessorSilenceProducesZeroMagnitudes() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw FFTProcessorTestError.noMetalDevice
    }

    let fft = try FFTProcessor(device: device)
    let silence = [Float](repeating: 0, count: 1024)

    let result = fft.process(samples: silence, sampleRate: 48000)

    #expect(result.dominantMagnitude == 0)
    #expect(result.binCount == 512)
    #expect(result.binResolution == 48000.0 / 1024.0)
}

@Test func fftProcessorDetectsDominantFrequency() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw FFTProcessorTestError.noMetalDevice
    }

    let fft = try FFTProcessor(device: device)
    let sampleRate: Float = 48000
    let frequency: Float = 440 // A4

    // Generate a pure sine wave at 440 Hz.
    var samples = [Float](repeating: 0, count: 1024)
    for i in 0..<1024 {
        samples[i] = sinf(2.0 * .pi * frequency * Float(i) / sampleRate)
    }

    let result = fft.process(samples: samples, sampleRate: sampleRate)

    // Dominant frequency should be close to 440 Hz.
    // Bin resolution is ~46.9 Hz, so we allow ±1 bin tolerance.
    let tolerance = result.binResolution * 1.5
    #expect(abs(result.dominantFrequency - frequency) < tolerance,
            "Expected ~440Hz, got \(result.dominantFrequency)Hz")
    #expect(result.dominantMagnitude > 0.1,
            "Expected non-trivial magnitude, got \(result.dominantMagnitude)")
}

@Test func fftProcessorStereoMixdown() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw FFTProcessorTestError.noMetalDevice
    }

    let fft = try FFTProcessor(device: device)
    let sampleRate: Float = 48000
    let frequency: Float = 1000

    // Generate interleaved stereo: same sine on both channels.
    var interleaved = [Float](repeating: 0, count: 2048)
    for i in 0..<1024 {
        let sample = sinf(2.0 * .pi * frequency * Float(i) / sampleRate)
        interleaved[i * 2] = sample      // L
        interleaved[i * 2 + 1] = sample  // R
    }

    let result = fft.processStereo(interleavedSamples: interleaved, sampleRate: sampleRate)

    let tolerance = result.binResolution * 1.5
    #expect(abs(result.dominantFrequency - frequency) < tolerance,
            "Expected ~1000Hz, got \(result.dominantFrequency)Hz")
}

@Test func fftProcessorHandlesShortInput() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw FFTProcessorTestError.noMetalDevice
    }

    let fft = try FFTProcessor(device: device)

    // Only 256 samples — should zero-pad to 1024 without crashing.
    let shortInput = [Float](repeating: 0.5, count: 256)
    let result = fft.process(samples: shortInput, sampleRate: 48000)

    #expect(result.binCount == 512)
    // Should still produce some output (DC component from the constant signal).
}

@Test func fftProcessorMagnitudeBufferGPUReadable() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw FFTProcessorTestError.noMetalDevice
    }

    let fft = try FFTProcessor(device: device)
    let sampleRate: Float = 48000

    // Process a sine wave.
    var samples = [Float](repeating: 0, count: 1024)
    for i in 0..<1024 {
        samples[i] = sinf(2.0 * .pi * 440.0 * Float(i) / sampleRate)
    }
    fft.process(samples: samples, sampleRate: sampleRate)

    // Read magnitudes directly from the UMA buffer (same path GPU would use).
    let magnitudes = fft.magnitudeBuffer
    var hasNonZero = false
    for i in 0..<FFTProcessor.binCount {
        if magnitudes[i] > 0.01 {
            hasNonZero = true
            break
        }
    }
    #expect(hasNonZero, "FFT magnitude buffer should have non-zero values after processing a sine wave")
}

// MARK: - Helpers

enum FFTProcessorTestError: Error {
    case noMetalDevice
}
