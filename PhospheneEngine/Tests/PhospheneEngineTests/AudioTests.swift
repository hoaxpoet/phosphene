// AudioTests — Unit tests for AudioBuffer and FFTProcessor.
// These test the offline/computational components. ScreenCaptureKit tests
// require a running system and user permission, so they're tested manually
// via the debug harness in the app.

import Testing
import Metal
@testable import Audio
@testable import Shared

// MARK: - AudioBuffer Tests

@Test func audioBufferWriteAndReadBack() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioTestError.noMetalDevice
    }

    let buffer = try AudioBuffer(device: device, capacity: 16)

    let samples: [Float] = [0.1, -0.2, 0.3, -0.4, 0.5, -0.6, 0.7, -0.8]
    let written = buffer.write(samples: samples)

    #expect(written == 8)
    #expect(buffer.sampleCount == 8)
    #expect(buffer.totalWritten == 8)
}

@Test func audioBufferRMSComputation() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioTestError.noMetalDevice
    }

    let buffer = try AudioBuffer(device: device, capacity: 16)

    // Write silence — RMS should be 0.
    buffer.write(samples: [0, 0, 0, 0])
    #expect(buffer.currentRMS == 0)

    // Write a known signal — all 0.5.
    buffer.write(samples: [0.5, 0.5, 0.5, 0.5])
    #expect(buffer.currentRMS == 0.5)
}

@Test func audioBufferLatestSamplesExtraction() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioTestError.noMetalDevice
    }

    let buffer = try AudioBuffer(device: device, capacity: 8)

    buffer.write(samples: [1, 2, 3, 4, 5, 6, 7, 8])

    // Extract last 4 samples.
    let latest = buffer.latestSamples(count: 4)
    #expect(latest.count == 4)
    #expect(latest == [5, 6, 7, 8])
}

@Test func audioBufferRingOverwrite() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioTestError.noMetalDevice
    }

    // Capacity 4 — writes beyond this overwrite oldest.
    let buffer = try AudioBuffer(device: device, capacity: 4)

    buffer.write(samples: [1, 2, 3, 4])
    buffer.write(samples: [5, 6])

    // Ring should now contain [5, 6, 3, 4] with head at 2,
    // but logical oldest→newest is [3, 4, 5, 6].
    let latest = buffer.latestSamples(count: 4)
    #expect(latest == [3, 4, 5, 6])
}

@Test func audioBufferReset() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioTestError.noMetalDevice
    }

    let buffer = try AudioBuffer(device: device, capacity: 16)
    buffer.write(samples: [1, 2, 3])
    buffer.reset()

    #expect(buffer.sampleCount == 0)
    #expect(buffer.totalWritten == 0)
    #expect(buffer.currentRMS == 0)
}

@Test func audioBufferMetalBufferBinding() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioTestError.noMetalDevice
    }

    let buffer = try AudioBuffer(device: device, capacity: 8)
    buffer.write(samples: [0.1, 0.2, 0.3, 0.4])

    // The metal buffer should be non-nil and have the right length.
    let mtlBuffer = buffer.metalBuffer
    #expect(mtlBuffer.length == 8 * MemoryLayout<Float>.stride)
}

// MARK: - FFTProcessor Tests

@Test func fftProcessorOutputBinCount() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioTestError.noMetalDevice
    }

    let fft = try FFTProcessor(device: device)
    #expect(FFTProcessor.fftSize == 1024)
    #expect(FFTProcessor.binCount == 512)
    #expect(fft.magnitudeBuffer.capacity == 512)
}

@Test func fftProcessorSilenceProducesZeroMagnitudes() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioTestError.noMetalDevice
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
        throw AudioTestError.noMetalDevice
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
        throw AudioTestError.noMetalDevice
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
        throw AudioTestError.noMetalDevice
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
        throw AudioTestError.noMetalDevice
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

enum AudioTestError: Error {
    case noMetalDevice
}
