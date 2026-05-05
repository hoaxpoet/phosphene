// SpectralHistoryBufferTests — Unit tests for SpectralHistoryBuffer ring buffer logic.

import Testing
import Metal
@testable import Shared

// MARK: - Helpers

private func makeDevice() throws -> MTLDevice {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw SpectralHistoryTestError.noDevice
    }
    return device
}

private enum SpectralHistoryTestError: Error {
    case noDevice
}

private func readFloat(_ buf: MTLBuffer, at index: Int) -> Float {
    buf.contents().assumingMemoryBound(to: Float.self)[index]
}

// MARK: - Tests

@Test func test_init_bufferIsZeroed() throws {
    let device = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)
    let ptr = history.gpuBuffer.contents().assumingMemoryBound(to: Float.self)
    for i in 0..<SpectralHistoryBuffer.totalFloats {
        #expect(ptr[i] == 0.0, "byte \(i) should be 0 after init")
    }
}

@Test func test_init_writeHeadAndSamplesValidAreZero() throws {
    let device = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)
    #expect(readFloat(history.gpuBuffer, at: SpectralHistoryBuffer.offsetWriteHead) == 0.0)
    #expect(readFloat(history.gpuBuffer, at: SpectralHistoryBuffer.offsetSamplesValid) == 0.0)
}

@Test func test_singleAppend_slot0ContainsExpectedValues() throws {
    let device   = try makeDevice()
    let history  = SpectralHistoryBuffer(device: device)

    var fv    = FeatureVector.zero
    fv.valence     = 0.75
    fv.arousal     = -0.5
    fv.beatPhase01 = 0.42
    fv.bassDev     = 0.31

    var stems = StemFeatures.zero
    fv.barPhase01 = 0.25

    history.append(features: fv, stems: stems)

    let ptr = history.gpuBuffer.contents().assumingMemoryBound(to: Float.self)

    #expect(ptr[SpectralHistoryBuffer.offsetValence   + 0] == 0.75)
    #expect(ptr[SpectralHistoryBuffer.offsetArousal   + 0] == -0.5)
    #expect(ptr[SpectralHistoryBuffer.offsetBeatPhase + 0] == 0.42)
    #expect(ptr[SpectralHistoryBuffer.offsetBassDev   + 0] == 0.31)
    #expect(abs(ptr[SpectralHistoryBuffer.offsetBarPhase + 0] - 0.25) < 0.001)

    #expect(readFloat(history.gpuBuffer, at: SpectralHistoryBuffer.offsetWriteHead)     == 1.0)
    #expect(readFloat(history.gpuBuffer, at: SpectralHistoryBuffer.offsetSamplesValid)  == 1.0)
}

@Test func test_480Appends_writeHeadWrapsToZero_samplesValidCapsAt480() throws {
    let device  = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)

    var fv    = FeatureVector.zero
    var stems = StemFeatures.zero

    for i in 0..<480 {
        fv.bassDev = Float(i) / 479.0
        history.append(features: fv, stems: stems)
    }

    #expect(readFloat(history.gpuBuffer, at: SpectralHistoryBuffer.offsetWriteHead)    == 0.0)
    #expect(readFloat(history.gpuBuffer, at: SpectralHistoryBuffer.offsetSamplesValid) == 480.0)

    // Last written value was at slot 479.
    let ptr   = history.gpuBuffer.contents().assumingMemoryBound(to: Float.self)
    let last  = ptr[SpectralHistoryBuffer.offsetBassDev + 479]
    #expect(abs(last - 1.0) < 0.001)
}

@Test func test_481Appends_oldestSlotOverwritten() throws {
    let device  = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)

    var fv    = FeatureVector.zero
    var stems = StemFeatures.zero

    for _ in 0..<480 {
        fv.bassDev = 0.1
        history.append(features: fv, stems: stems)
    }
    // 481st append — overwrites slot 0.
    fv.bassDev = 0.999
    history.append(features: fv, stems: stems)

    #expect(readFloat(history.gpuBuffer, at: SpectralHistoryBuffer.offsetWriteHead)    == 1.0)
    #expect(readFloat(history.gpuBuffer, at: SpectralHistoryBuffer.offsetSamplesValid) == 480.0)

    let ptr = history.gpuBuffer.contents().assumingMemoryBound(to: Float.self)
    #expect(abs(ptr[SpectralHistoryBuffer.offsetBassDev + 0] - 0.999) < 0.001)
}

@Test func test_barPhase_multipleValues() throws {
    let device  = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)
    var fv      = FeatureVector.zero
    var stems   = StemFeatures.zero
    let ptr     = history.gpuBuffer.contents().assumingMemoryBound(to: Float.self)

    fv.barPhase01 = 0.0
    history.append(features: fv, stems: stems)
    #expect(abs(ptr[SpectralHistoryBuffer.offsetBarPhase + 0]) < 0.001)

    fv.barPhase01 = 1.0
    history.append(features: fv, stems: stems)
    #expect(abs(ptr[SpectralHistoryBuffer.offsetBarPhase + 1] - 1.0) < 0.001)

    fv.barPhase01 = 0.5
    history.append(features: fv, stems: stems)
    #expect(abs(ptr[SpectralHistoryBuffer.offsetBarPhase + 2] - 0.5) < 0.001)
}

@Test func test_barPhase_zeroWhenNoGrid() throws {
    let device  = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)
    var fv      = FeatureVector.zero
    // barPhase01 defaults to 0 in FeatureVector.zero
    history.append(features: fv, stems: StemFeatures.zero)

    let stored = readFloat(history.gpuBuffer, at: SpectralHistoryBuffer.offsetBarPhase)
    #expect(stored == 0.0, "barPhase01 should be 0 when no BeatGrid is installed")
}

@Test func test_reset_zerosBufferAndIndices() throws {
    let device  = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)
    var fv      = FeatureVector.zero
    var stems   = StemFeatures.zero
    fv.valence  = 0.9
    history.append(features: fv, stems: stems)

    history.reset()

    let ptr = history.gpuBuffer.contents().assumingMemoryBound(to: Float.self)
    let beatTimesStart = SpectralHistoryBuffer.offsetBeatTimes
    let beatTimesEnd   = beatTimesStart + SpectralHistoryBuffer.beatTimesCount
    for i in 0..<SpectralHistoryBuffer.totalFloats {
        if i >= beatTimesStart && i < beatTimesEnd {
            // Beat-time slots are reset to Float.infinity (sentinel = no tick).
            #expect(ptr[i].isInfinite, "slot \(i) should be ∞ after reset")
        } else {
            #expect(ptr[i] == 0.0, "slot \(i) should be 0 after reset")
        }
    }
    // After reset + single append, writeHead should be 1, samplesValid 1.
    fv.valence = 0.5
    history.append(features: fv, stems: stems)
    #expect(readFloat(history.gpuBuffer, at: SpectralHistoryBuffer.offsetWriteHead)    == 1.0)
    #expect(readFloat(history.gpuBuffer, at: SpectralHistoryBuffer.offsetSamplesValid) == 1.0)
}

@Test func test_bassDevPassthrough_noRescaling() throws {
    let device  = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)
    var fv      = FeatureVector.zero
    fv.bassDev  = 0.42
    var stems   = StemFeatures.zero

    history.append(features: fv, stems: stems)

    let stored = readFloat(history.gpuBuffer, at: SpectralHistoryBuffer.offsetBassDev)
    #expect(abs(stored - 0.42) < 1e-6, "bassDev 0.42 should be stored verbatim, got \(stored)")
}
