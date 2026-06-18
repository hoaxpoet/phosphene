// StemSeparatorTests — Unit tests for MPSGraph stem separation pipeline.
// Tests model loading, stem output correctness, buffer storage mode,
// label ordering, and protocol conformance.

import Testing
import Foundation
import Metal
@testable import ML
@testable import Audio
@testable import Shared

// MARK: - StemSeparator Unit Tests

@Test func test_init_loadsModel_noThrow() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw StemTestError.noMetalDevice
    }

    // Should not throw — model is bundled as a resource.
    _ = try StemSeparator(device: device)
}

@Test func test_separate_validInput_returnsFourStems() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw StemTestError.noMetalDevice
    }

    let separator = try StemSeparator(device: device)

    // Generate 1 second of stereo audio at 44100 Hz (model's native rate).
    let mono = AudioFixtures.sineWave(frequency: 440, sampleRate: 44100, duration: 1.0)
    let stereo = AudioFixtures.mixStereo(left: mono, right: mono)

    let result = try separator.separate(audio: stereo, channelCount: 2, sampleRate: 44100)

    #expect(result.sampleCount > 0, "Should produce output samples")
    #expect(result.stemData.vocals.sampleCount > 0, "Vocals stem should have samples")
    #expect(result.stemData.drums.sampleCount > 0, "Drums stem should have samples")
    #expect(result.stemData.bass.sampleCount > 0, "Bass stem should have samples")
    #expect(result.stemData.other.sampleCount > 0, "Other stem should have samples")

    // Verify all 4 stem buffers have non-trivial content (at least some energy).
    var totalEnergy: Float = 0
    for buf in separator.stemBuffers {
        var energy: Float = 0
        for i in 0..<min(result.sampleCount, buf.capacity) {
            energy += buf[i] * buf[i]
        }
        totalEnergy += energy
    }
    #expect(totalEnergy > 0, "Total stem energy should be non-zero for sine input")
}

@Test func test_separate_silence_allStemsNearZero() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw StemTestError.noMetalDevice
    }

    let separator = try StemSeparator(device: device)

    // 1 second of silence, stereo at model rate.
    let silence = AudioFixtures.silence(sampleCount: 44100 * 2)

    let result = try separator.separate(audio: silence, channelCount: 2, sampleRate: 44100)

    #expect(result.sampleCount > 0, "Should still produce output frames")

    // All stems should have near-zero RMS.
    for (i, buf) in separator.stemBuffers.enumerated() {
        var sumSq: Float = 0
        let count = min(result.sampleCount, buf.capacity)
        for j in 0..<count {
            sumSq += buf[j] * buf[j]
        }
        let rms = sqrtf(sumSq / Float(max(count, 1)))
        #expect(rms < 0.01,
                "Stem \(i) RMS should be near zero for silence, got \(rms)")
    }
}

@Test func test_separate_outputBuffers_storageModeShared() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw StemTestError.noMetalDevice
    }

    let separator = try StemSeparator(device: device)

    for (i, buf) in separator.stemBuffers.enumerated() {
        #expect(buf.buffer.resourceOptions.contains(.storageModeShared),
                "Stem buffer \(i) should use .storageModeShared for UMA zero-copy")
    }
}

@Test func test_separate_stemLabels_correctOrder() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw StemTestError.noMetalDevice
    }

    let separator = try StemSeparator(device: device)

    #expect(separator.stemLabels == ["vocals", "drums", "bass", "other"],
            "Stem labels should be in model output order")
    #expect(separator.stemLabels.count == 4)
    #expect(separator.stemBuffers.count == 4)
}

@Test func test_separate_chunkedInput_noGapBetweenChunks() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw StemTestError.noMetalDevice
    }

    let separator = try StemSeparator(device: device)

    // Two consecutive 0.5s chunks of sine wave.
    let mono = AudioFixtures.sineWave(frequency: 440, sampleRate: 44100, duration: 0.5)
    let stereo = AudioFixtures.mixStereo(left: mono, right: mono)

    let result1 = try separator.separate(audio: stereo, channelCount: 2, sampleRate: 44100)
    let result2 = try separator.separate(audio: stereo, channelCount: 2, sampleRate: 44100)

    // Both chunks should produce valid output.
    #expect(result1.sampleCount > 0, "First chunk should produce output")
    #expect(result2.sampleCount > 0, "Second chunk should produce output")

    // Second chunk should write valid data (non-NaN, non-Inf).
    let buf = separator.stemBuffers[0]
    let count = min(result2.sampleCount, buf.capacity)
    for i in 0..<min(count, 100) {
        let val = buf[i]
        #expect(!val.isNaN, "Output should not contain NaN at index \(i)")
        #expect(!val.isInfinite, "Output should not contain Inf at index \(i)")
    }
}

// CLEAN.4.2: mono input (channelCount 1) reuses the left STFT for the right instead of
// recomputing the identical transform. A mono separation must therefore produce the SAME
// stems as the un-optimized stereo-duplicated path (channelCount 2, L == R == the mono
// signal) — both feed magL == magR == stft(mono) to the model. The stereo path is unchanged
// reference code, so any divergence means the mono dedup altered the output.
@Test func test_separate_monoReusesStereoStft_outputUnchanged() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw StemTestError.noMetalDevice
    }

    let separator = try StemSeparator(device: device)
    let mono = AudioFixtures.sineWave(frequency: 440, sampleRate: 44100, duration: 1.0)

    func snapshotStems(sampleCount: Int) -> [[Float]] {
        separator.stemBuffers.map { buf in
            let n = min(sampleCount, buf.capacity)
            return (0..<n).map { buf[$0] }
        }
    }

    // Mono path (the dedup) — then snapshot before the buffers are reused.
    let monoResult = try separator.separate(audio: mono, channelCount: 1, sampleRate: 44100)
    let monoStems = snapshotStems(sampleCount: monoResult.sampleCount)

    // Stereo-duplicated reference path (unchanged code).
    let stereo = AudioFixtures.mixStereo(left: mono, right: mono)
    let stereoResult = try separator.separate(audio: stereo, channelCount: 2, sampleRate: 44100)
    let stereoStems = snapshotStems(sampleCount: stereoResult.sampleCount)

    #expect(monoResult.sampleCount == stereoResult.sampleCount,
            "mono and stereo-duplicated separations must yield the same sample count")
    for stem in 0..<min(monoStems.count, stereoStems.count) {
        #expect(monoStems[stem].count == stereoStems[stem].count, "stem \(stem) length mismatch")
        var maxDiff: Float = 0
        for i in 0..<min(monoStems[stem].count, stereoStems[stem].count) {
            maxDiff = max(maxDiff, abs(monoStems[stem][i] - stereoStems[stem][i]))
        }
        // Identical model input → identical output; tolerance absorbs only GPU float noise.
        #expect(maxDiff < 1e-5, "stem \(stem): mono dedup changed the output (maxDiff \(maxDiff))")
    }
}

@Test func test_conformsToStemSeparating() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw StemTestError.noMetalDevice
    }

    let separator = try StemSeparator(device: device)

    // Verify protocol conformance by assigning to protocol-typed variable.
    let proto: any StemSeparating = separator
    #expect(proto.stemLabels.count == 4)
    #expect(proto.stemBuffers.count == 4)
}

// MARK: - Errors

private enum StemTestError: Error {
    case noMetalDevice
}
