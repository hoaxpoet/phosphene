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

@Test func fftProcessorStereoPointerMatchesArrayPath() throws {
    // BUG-036: the zero-alloc pointer path must be bit-for-bit equivalent to the
    // allocating array path (which now delegates to it). L≠R so the mixdown and
    // the partial-front zero-pad (short buffer) are both exercised.
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw FFTProcessorTestError.noMetalDevice
    }
    let sampleRate: Float = 48000

    func makeInterleaved(frames: Int) -> [Float] {
        var interleaved = [Float](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            interleaved[i * 2]     = sinf(2.0 * .pi * 440.0 * Float(i) / sampleRate)
            interleaved[i * 2 + 1] = 0.5 * sinf(2.0 * .pi * 880.0 * Float(i) / sampleRate)
        }
        return interleaved
    }

    for frames in [1024, 300] {  // full and short (partial zero-pad)
        let interleaved = makeInterleaved(frames: frames)

        let fftArray = try FFTProcessor(device: device)
        let arrayResult = fftArray.processStereo(interleavedSamples: interleaved, sampleRate: sampleRate)
        let arrayMags = (0..<FFTProcessor.binCount).map { fftArray.magnitudeBuffer[$0] }

        let fftPtr = try FFTProcessor(device: device)
        let ptrResult = interleaved.withUnsafeBufferPointer {
            fftPtr.processStereo(interleaved: $0, sampleRate: sampleRate)
        }
        let ptrMags = (0..<FFTProcessor.binCount).map { fftPtr.magnitudeBuffer[$0] }

        #expect(ptrResult.dominantFrequency == arrayResult.dominantFrequency)
        #expect(ptrResult.dominantMagnitude == arrayResult.dominantMagnitude)
        #expect(ptrMags == arrayMags)
    }
}

@Test func fftProcessorStereoPointerReuseIsStable() throws {
    // BUG-036: reusing windowedSamples / magnitudesScratch across calls must not
    // corrupt results — the same input yields identical output every call.
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw FFTProcessorTestError.noMetalDevice
    }
    let fft = try FFTProcessor(device: device)
    let sampleRate: Float = 48000

    var interleaved = [Float](repeating: 0, count: 2048)
    for i in 0..<1024 {
        let s = sinf(2.0 * .pi * 1000.0 * Float(i) / sampleRate)
        interleaved[i * 2] = s
        interleaved[i * 2 + 1] = s
    }

    let first = interleaved.withUnsafeBufferPointer {
        fft.processStereo(interleaved: $0, sampleRate: sampleRate)
    }
    let firstMags = (0..<FFTProcessor.binCount).map { fft.magnitudeBuffer[$0] }

    for _ in 0..<64 {
        let r = interleaved.withUnsafeBufferPointer {
            fft.processStereo(interleaved: $0, sampleRate: sampleRate)
        }
        let mags = (0..<FFTProcessor.binCount).map { fft.magnitudeBuffer[$0] }
        #expect(r.dominantFrequency == first.dominantFrequency)
        #expect(r.dominantMagnitude == first.dominantMagnitude)
        #expect(mags == firstMags)
    }

    let tolerance = first.binResolution * 1.5
    #expect(abs(first.dominantFrequency - 1000.0) < tolerance,
            "Expected ~1000Hz, got \(first.dominantFrequency)Hz")
}

// MARK: - Helpers

enum FFTProcessorTestError: Error {
    case noMetalDevice
}
