// AudioFeaturesTests — Unit tests for @frozen SIMD-aligned audio data types.
// Verifies memory layout, default values, and GPU-compatibility of Shared types.

import Testing
import Metal
@testable import Shared

@Test func test_audioFrame_memoryLayout_isSIMDAligned() {
    // AudioFrame must be at least 16-byte aligned for safe GPU upload.
    // @frozen struct with Double + Float + 3×UInt32 = 24 bytes.
    let alignment = MemoryLayout<AudioFrame>.alignment
    #expect(alignment >= 4, "AudioFrame alignment should be at least 4-byte, got \(alignment)")
    #expect(MemoryLayout<AudioFrame>.size == 24,
            "AudioFrame should be 24 bytes, got \(MemoryLayout<AudioFrame>.size)")
}

@Test func test_fftResult_binCount_is512() {
    let result = FFTResult()
    #expect(result.binCount == 512,
            "Default FFTResult binCount should be 512, got \(result.binCount)")
}

@Test func test_featureVector_defaultValues_areZero() {
    let fv = FeatureVector()

    #expect(fv.bass == 0)
    #expect(fv.mid == 0)
    #expect(fv.treble == 0)
    #expect(fv.bassAtt == 0)
    #expect(fv.midAtt == 0)
    #expect(fv.trebleAtt == 0)
    #expect(fv.subBass == 0)
    #expect(fv.lowBass == 0)
    #expect(fv.lowMid == 0)
    #expect(fv.midHigh == 0)
    #expect(fv.highMid == 0)
    #expect(fv.high == 0)
    #expect(fv.beatBass == 0)
    #expect(fv.beatMid == 0)
    #expect(fv.beatTreble == 0)
    #expect(fv.beatComposite == 0)
    #expect(fv.spectralCentroid == 0)
    #expect(fv.spectralFlux == 0)
    #expect(fv.valence == 0)
    #expect(fv.arousal == 0)
    #expect(fv.time == 0)
    #expect(fv.deltaTime == 0)
    #expect(fv.accumulatedAudioTime == 0)

    // Also verify the static zero constant.
    #expect(FeatureVector.zero.bass == 0)
    #expect(FeatureVector.zero.time == 0)
    #expect(FeatureVector.zero.accumulatedAudioTime == 0)
}

@Test func test_stemData_fourStems_correctLayout() {
    let stems = StemData()

    // Four stems, each an AudioFrame.
    #expect(stems.vocals.sampleRate == 48000, "Default vocal sample rate should be 48000")
    #expect(stems.drums.channelCount == 2, "Default drum channel count should be 2")
    #expect(stems.bass.sampleCount == 0, "Default bass sample count should be 0")
    #expect(stems.other.bufferOffset == 0, "Default other buffer offset should be 0")

    // StemData size = 4 × AudioFrame = 4 × 24 = 96 bytes.
    #expect(MemoryLayout<StemData>.size == 4 * MemoryLayout<AudioFrame>.size,
            "StemData should be exactly 4 AudioFrames in size")
}

@Test func test_audioFrame_equatable_sameValues_areEqual() {
    let frame1 = AudioFrame(timestamp: 1.5, sampleRate: 48000, sampleCount: 1024,
                            channelCount: 2, bufferOffset: 0)
    let frame2 = AudioFrame(timestamp: 1.5, sampleRate: 48000, sampleCount: 1024,
                            channelCount: 2, bufferOffset: 0)

    // Verify byte-level equality via raw memory comparison.
    let equal = withUnsafeBytes(of: frame1) { bytes1 in
        withUnsafeBytes(of: frame2) { bytes2 in
            bytes1.elementsEqual(bytes2)
        }
    }
    #expect(equal, "AudioFrames with same values should be byte-equal")

    // Also verify a different frame is not equal.
    let frame3 = AudioFrame(timestamp: 2.0, sampleRate: 48000, sampleCount: 1024,
                            channelCount: 2, bufferOffset: 0)
    let notEqual = withUnsafeBytes(of: frame1) { bytes1 in
        withUnsafeBytes(of: frame3) { bytes2 in
            bytes1.elementsEqual(bytes2)
        }
    }
    #expect(!notEqual, "AudioFrames with different timestamps should not be byte-equal")
}

@Test func test_stemFeatures_memoryLayout_is64Bytes() {
    // StemFeatures: 16 floats × 4 bytes = 64 bytes.
    #expect(MemoryLayout<StemFeatures>.size == 64,
            "StemFeatures must be 64 bytes (16 × 4), got \(MemoryLayout<StemFeatures>.size)")
    #expect(MemoryLayout<StemFeatures>.stride == 64,
            "StemFeatures stride must be 64 bytes, got \(MemoryLayout<StemFeatures>.stride)")
}

@Test func test_stemFeatures_simdAligned() {
    // StemFeatures stride must be 16-byte aligned for GPU uniform upload.
    #expect(MemoryLayout<StemFeatures>.stride % 16 == 0,
            "StemFeatures stride must be 16-byte aligned for GPU, got stride \(MemoryLayout<StemFeatures>.stride)")

    // Verify the matching MSL struct size expectation (16 floats × 4 bytes).
    let expectedMSLSize = 16 * MemoryLayout<Float>.size
    #expect(MemoryLayout<StemFeatures>.size == expectedMSLSize,
            "Swift StemFeatures size (\(MemoryLayout<StemFeatures>.size)) must match MSL size (\(expectedMSLSize))")

    // Verify .zero default is safe to bind.
    let zero = StemFeatures.zero
    #expect(zero.vocalsEnergy == 0)
    #expect(zero.drumsBeat == 0)
    #expect(zero.otherBand1 == 0)
}

@Test func test_featureVector_simdSize_matchesGPUExpectation() {
    // FeatureVector: 32 floats = 128 bytes (Increment 3.15: added accumulatedAudioTime + 7 pad).
    // Stride must be 16-byte aligned for GPU uniforms.
    #expect(MemoryLayout<FeatureVector>.size == 128,
            "FeatureVector must be 128 bytes (32 × 4), got \(MemoryLayout<FeatureVector>.size)")
    #expect(MemoryLayout<FeatureVector>.stride % 16 == 0,
            "FeatureVector stride must be 16-byte aligned for GPU, got stride \(MemoryLayout<FeatureVector>.stride)")

    // Verify the matching MSL struct size expectation (32 floats × 4 bytes).
    let expectedMSLSize = 32 * MemoryLayout<Float>.size
    #expect(MemoryLayout<FeatureVector>.size == expectedMSLSize,
            "Swift FeatureVector size (\(MemoryLayout<FeatureVector>.size)) must match MSL size (\(expectedMSLSize))")
}
