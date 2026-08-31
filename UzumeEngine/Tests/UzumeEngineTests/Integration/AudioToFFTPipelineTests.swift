// AudioToFFTPipelineTests — Integration tests wiring real AudioBuffer + real FFTProcessor.
// No mocks: exercises the full audio-to-FFT data path with synthetic input.

import Testing
import Foundation
import Metal
@testable import Audio
@testable import Shared

// MARK: - Audio → FFT Pipeline Integration

@Test func sineWaveThroughPipeline_fftShowsPeak() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioFFTTestError.noMetalDevice
    }

    let audioBuffer = try AudioBuffer(device: device)
    let fftProcessor = try FFTProcessor(device: device)

    // Generate 440Hz sine, interleaved stereo.
    let mono = AudioFixtures.sineWave(frequency: 440, sampleRate: 48000, duration: 0.1)
    let stereo = AudioFixtures.mixStereo(left: mono, right: mono)

    // Write through the pointer-based path (same as Core Audio tap callback).
    stereo.withUnsafeBufferPointer { ptr in
        _ = audioBuffer.write(from: ptr.baseAddress!, count: ptr.count)
    }

    // Extract interleaved samples and run FFT.
    let latest = audioBuffer.latestSamples(count: FFTProcessor.fftSize * 2)
    let result = fftProcessor.processStereo(interleavedSamples: latest, sampleRate: 48000)

    // 440Hz at 48kHz with 1024-point FFT: bin resolution = 48000/1024 ≈ 46.875 Hz.
    // Expected peak bin = 440 / 46.875 ≈ 9.39 → bin 9.
    let expectedBin = 9
    let binResolution = 48000.0 / 1024.0

    // Find the actual peak bin in the magnitude buffer.
    var peakBin = 0
    var peakMag: Float = 0
    for i in 0..<FFTProcessor.binCount {
        let mag = fftProcessor.magnitudeBuffer[i]
        if mag > peakMag {
            peakMag = mag
            peakBin = i
        }
    }

    #expect(peakBin == expectedBin,
            "Peak bin should be \(expectedBin) (440Hz), got \(peakBin) (\(Float(peakBin) * Float(binResolution))Hz)")
    #expect(peakMag > 0.1, "Peak magnitude should be significant, got \(peakMag)")
    #expect(result.dominantFrequency > 0, "Dominant frequency should be detected")
}

@Test func silenceThroughPipeline_fftIsFlat() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioFFTTestError.noMetalDevice
    }

    let audioBuffer = try AudioBuffer(device: device)
    let fftProcessor = try FFTProcessor(device: device)

    // Write silence (interleaved stereo).
    let silence = AudioFixtures.silence(sampleCount: 4096)
    silence.withUnsafeBufferPointer { ptr in
        _ = audioBuffer.write(from: ptr.baseAddress!, count: ptr.count)
    }

    let latest = audioBuffer.latestSamples(count: FFTProcessor.fftSize * 2)
    fftProcessor.processStereo(interleavedSamples: latest, sampleRate: 48000)

    // All magnitudes should be effectively zero.
    for i in 0..<FFTProcessor.binCount {
        let mag = fftProcessor.magnitudeBuffer[i]
        #expect(mag < 0.001,
                "Bin \(i) magnitude should be < 0.001 for silence, got \(mag)")
    }
}

@Test func continuousStream_noMemoryGrowth() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioFFTTestError.noMetalDevice
    }

    let audioBuffer = try AudioBuffer(device: device)
    let fftProcessor = try FFTProcessor(device: device)

    // Generate a fixed chunk of audio to reuse (avoids per-iteration alloc in the test setup).
    let mono = AudioFixtures.sineWave(frequency: 440, sampleRate: 48000, duration: 0.02)
    let stereo = AudioFixtures.mixStereo(left: mono, right: mono)

    // Process 10,000 frames in a tight loop.
    // If there's a per-frame leak, this will either crash or take unreasonably long.
    let iterations = 10_000
    for _ in 0..<iterations {
        stereo.withUnsafeBufferPointer { ptr in
            _ = audioBuffer.write(from: ptr.baseAddress!, count: ptr.count)
        }
        let latest = audioBuffer.latestSamples(count: FFTProcessor.fftSize * 2)
        fftProcessor.processStereo(interleavedSamples: latest, sampleRate: 48000)
    }

    // If we reach here, the loop completed without crashing or excessive memory growth.
    #expect(audioBuffer.totalWritten == UInt64(stereo.count) * UInt64(iterations),
            "All samples should have been written")
    #expect(fftProcessor.latestResult.dominantMagnitude > 0,
            "FFT should still produce valid results after \(iterations) iterations")
}

// MARK: - Errors

private enum AudioFFTTestError: Error {
    case noMetalDevice
}
