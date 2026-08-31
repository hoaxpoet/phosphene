// AnalyzedFrameTests — Unit tests for the AnalyzedFrame timestamped container.
// Verifies field access, timestamp ordering, and memory footprint.

import Testing
@testable import Shared

// MARK: - Field Access

@Test func test_analyzedFrame_init_allFieldsAccessible() {
    let audio = AudioFrame(timestamp: 1.0, sampleRate: 48000, sampleCount: 1024,
                           channelCount: 2, bufferOffset: 0)
    let fft = FFTResult(binCount: 512, binResolution: 46.875,
                        dominantFrequency: 440.0, dominantMagnitude: 0.8)
    let stems = StemData()
    let features = FeatureVector(bass: 0.5, mid: 0.3, treble: 0.2)
    let emotion = EmotionalState(valence: 0.7, arousal: 0.4)

    let frame = AnalyzedFrame(
        timestamp: 1.0,
        audioFrame: audio,
        fftResult: fft,
        stemData: stems,
        featureVector: features,
        emotionalState: emotion
    )

    #expect(frame.timestamp == 1.0)
    #expect(frame.audioFrame.sampleRate == 48000)
    #expect(frame.fftResult.dominantFrequency == 440.0)
    #expect(frame.stemData.vocals.channelCount == 2)
    #expect(frame.featureVector.bass == 0.5)
    #expect(frame.emotionalState.valence == 0.7)
    #expect(frame.emotionalState.quadrant == .happy)
}

// MARK: - Timestamp Ordering

@Test func test_analyzedFrame_timestamp_monotonicallyIncreasing() {
    let frames = (0..<100).map { i in
        AnalyzedFrame(timestamp: Double(i) / 60.0)
    }

    for i in 1..<frames.count {
        #expect(frames[i].timestamp > frames[i - 1].timestamp,
                "Frame \(i) timestamp should exceed frame \(i - 1)")
    }
}

// MARK: - Memory Layout

@Test func test_analyzedFrame_memoryLayout_isReasonableSize() {
    let size = MemoryLayout<AnalyzedFrame>.size
    // AnalyzedFrame should be well under 64KB per frame.
    // Expected: ~8 (timestamp) + 24 (AudioFrame) + 16 (FFTResult) + 96 (StemData)
    //           + 96 (FeatureVector) + 8 (EmotionalState) ≈ 248 bytes.
    #expect(size < 65536,
            "AnalyzedFrame should be under 64KB, got \(size) bytes")
    // Also verify it's reasonably compact (under 1KB).
    #expect(size < 1024,
            "AnalyzedFrame should be under 1KB for efficient buffering, got \(size) bytes")
}
