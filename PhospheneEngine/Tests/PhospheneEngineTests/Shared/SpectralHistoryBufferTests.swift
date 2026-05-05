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
    let beatTimesStart    = SpectralHistoryBuffer.offsetBeatTimes
    let beatTimesEnd      = beatTimesStart + SpectralHistoryBuffer.beatTimesCount
    let downbeatTimesStart = SpectralHistoryBuffer.offsetDownbeatTimes
    let downbeatTimesEnd   = downbeatTimesStart + SpectralHistoryBuffer.downbeatTimesCount
    for i in 0..<SpectralHistoryBuffer.totalFloats {
        let isInfinitySlot = (i >= beatTimesStart && i < beatTimesEnd)
                          || (i >= downbeatTimesStart && i < downbeatTimesEnd)
        if isInfinitySlot {
            // Beat-time and downbeat-time slots are reset to Float.infinity (no-tick sentinel).
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

// MARK: - sessionMode tests (DSP.3.1)

@Test func test_updateBeatGridData_sessionMode_writtenToSlot2420() throws {
    let device = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)

    history.updateBeatGridData(relativeBeatTimes: [], bpm: 120.0, lockState: 2, sessionMode: 3)

    let stored = readFloat(history.gpuBuffer, at: SpectralHistoryBuffer.offsetSessionMode)
    #expect(stored == 3.0, "sessionMode 3 should be stored at offsetSessionMode, got \(stored)")
}

@Test func test_readSessionMode_returnsWrittenValue() throws {
    let device = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)

    for mode in 0...3 {
        history.updateBeatGridData(relativeBeatTimes: [], bpm: 120.0, lockState: 0, sessionMode: mode)
        let read = history.readSessionMode()
        #expect(read == mode, "readSessionMode should return \(mode), got \(read)")
    }
}

@Test func test_sessionMode_zeroAfterReset() throws {
    let device = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)

    history.updateBeatGridData(relativeBeatTimes: [], bpm: 120.0, lockState: 2, sessionMode: 3)
    history.reset()

    let read = history.readSessionMode()
    #expect(read == 0, "sessionMode should be 0 after reset(), got \(read)")
}

@Test func test_sessionMode_clampedTo0_3() throws {
    let device = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)

    history.updateBeatGridData(relativeBeatTimes: [], bpm: 0.0, lockState: 0, sessionMode: 99)
    let stored = readFloat(history.gpuBuffer, at: SpectralHistoryBuffer.offsetSessionMode)
    #expect(stored == 3.0, "sessionMode should be clamped to 3, got \(stored)")
}

// MARK: - DSP.3.3: downbeats + drift slots

@Test func test_downbeatSlots_infinityAfterReset() throws {
    let device = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)
    history.updateBeatGridData(
        relativeBeatTimes: [], relativeDownbeatTimes: [0.5, 1.0, 2.0],
        bpm: 120, lockState: 1, sessionMode: 2, driftMs: 15.0
    )
    history.reset()
    let ptr = history.gpuBuffer.contents().assumingMemoryBound(to: Float.self)
    for i in 0..<SpectralHistoryBuffer.downbeatTimesCount {
        let slot = SpectralHistoryBuffer.offsetDownbeatTimes + i
        #expect(ptr[slot].isInfinite, "downbeat slot \(i) should be ∞ after reset")
    }
}

@Test func test_driftMs_storedAndReadBack() throws {
    let device = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)
    history.updateBeatGridData(relativeBeatTimes: [], bpm: 120, lockState: 2,
                               sessionMode: 3, driftMs: 23.5)
    let read = history.readDriftMs()
    #expect(abs(read - 23.5) < 0.01, "drift should round-trip; got \(read)")
}

@Test func test_driftMs_zeroAfterReset() throws {
    let device = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)
    history.updateBeatGridData(relativeBeatTimes: [], bpm: 120, lockState: 2,
                               sessionMode: 3, driftMs: 50.0)
    history.reset()
    let read = history.readDriftMs()
    #expect(read == 0.0, "driftMs should be 0 after reset; got \(read)")
}

@Test func test_downbeatTimes_roundTrip() throws {
    let device = try makeDevice()
    let history = SpectralHistoryBuffer(device: device)
    let downbeats: [Float] = [-0.5, 0.0, 1.5, 3.0]
    history.updateBeatGridData(
        relativeBeatTimes: [], relativeDownbeatTimes: downbeats,
        bpm: 120, lockState: 2, sessionMode: 3, driftMs: 0
    )
    let ptr = history.gpuBuffer.contents().assumingMemoryBound(to: Float.self)
    for (i, expected) in downbeats.enumerated() {
        let slot = SpectralHistoryBuffer.offsetDownbeatTimes + i
        #expect(abs(ptr[slot] - expected) < 0.001, "downbeat[\(i)] mismatch: \(ptr[slot]) vs \(expected)")
    }
    // Unused slots should be infinity.
    for i in downbeats.count..<SpectralHistoryBuffer.downbeatTimesCount {
        let slot = SpectralHistoryBuffer.offsetDownbeatTimes + i
        #expect(ptr[slot].isInfinite, "unused downbeat slot \(i) should be ∞")
    }
}
