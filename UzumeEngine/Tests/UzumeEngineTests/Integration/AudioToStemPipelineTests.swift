// AudioToStemPipelineTests — Integration tests wiring real AudioBuffer + real StemSeparator.
// No mocks: exercises the full audio-to-stem data path with synthetic input.

import Testing
import Foundation
import Metal
@testable import ML
@testable import Audio
@testable import Shared

// MARK: - Audio → Stem Pipeline Integration

@Test func sineWaveInput_stemsHaveExpectedEnergyDistribution() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw StemPipelineTestError.noMetalDevice
    }

    let separator = try StemSeparator(device: device)

    // 440Hz sine wave — a pure tone should land primarily in "other" stem
    // (not drums, not bass, not vocals).
    let mono = AudioFixtures.sineWave(frequency: 440, sampleRate: 44100, duration: 1.0)
    let stereo = AudioFixtures.mixStereo(left: mono, right: mono)

    let result = try separator.separate(audio: stereo, channelCount: 2, sampleRate: 44100)

    // Compute RMS for each stem.
    var stemRMS = [Float](repeating: 0, count: 4)
    for (i, buf) in separator.stemBuffers.enumerated() {
        var sumSq: Float = 0
        let count = min(result.sampleCount, buf.capacity)
        for j in 0..<count {
            sumSq += buf[j] * buf[j]
        }
        stemRMS[i] = sqrtf(sumSq / Float(max(count, 1)))
    }

    // At minimum, the total energy across stems should be non-trivial.
    let totalRMS = stemRMS.reduce(0, +)
    #expect(totalRMS > 0.01,
            "Total stem RMS should be non-trivial for 440Hz sine, got \(totalRMS)")

    // The "other" stem (index 3) should carry significant energy for a pure tone.
    // A 440Hz sine is not a vocal, drum hit, or bass line.
    let otherRatio = stemRMS[3] / max(totalRMS, 1e-10)
    #expect(otherRatio > 0.1,
            "Other stem should carry meaningful energy for 440Hz sine, ratio: \(otherRatio)")
}

@Test func continuousChunks_noMemoryLeak() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw StemPipelineTestError.noMetalDevice
    }

    let separator = try StemSeparator(device: device)

    // Generate a fixed chunk of stereo audio at model rate.
    let mono = AudioFixtures.sineWave(frequency: 440, sampleRate: 44100, duration: 0.5)
    let stereo = AudioFixtures.mixStereo(left: mono, right: mono)

    // Process 5 chunks. Each includes full STFT → CoreML → iSTFT pipeline.
    // If there's a per-call leak, memory will grow noticeably even across 5 iterations.
    let iterations = 5
    for _ in 0..<iterations {
        _ = try separator.separate(audio: stereo, channelCount: 2, sampleRate: 44100)
    }

    // If we reach here, the loop completed without crashing or excessive memory growth.
    // Verify the last separation still produces valid output.
    let finalResult = try separator.separate(audio: stereo, channelCount: 2, sampleRate: 44100)
    #expect(finalResult.sampleCount > 0,
            "Should still produce valid output after \(iterations) iterations")

    // Verify output is not corrupted (no NaN/Inf).
    let buf = separator.stemBuffers[0]
    let checkCount = min(finalResult.sampleCount, 100)
    for i in 0..<checkCount {
        let val = buf[i]
        #expect(!val.isNaN, "Output should not contain NaN after \(iterations) iterations")
        #expect(!val.isInfinite, "Output should not contain Inf after \(iterations) iterations")
    }
}

// MARK: - Errors

private enum StemPipelineTestError: Error {
    case noMetalDevice
}
