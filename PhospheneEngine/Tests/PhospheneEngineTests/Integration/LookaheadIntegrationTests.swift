// LookaheadIntegrationTests — Integration test for analysis-to-render delay accuracy.
// Validates that the LookaheadBuffer delivers correct delay under simulated
// real-time conditions (100 frames at 60fps).

import Testing
import Foundation
@testable import Audio
@testable import Shared

@Test func test_analysisToRenderDelay_measuredAccurately() {
    let configuredDelay: Double = 2.5  // seconds
    let buffer = LookaheadBuffer(capacity: 512, delay: configuredDelay)
    let fps: Double = 60.0
    let frameCount = 300  // 5 seconds at 60fps — enough to fill the delay window

    // Simulate pushing frames at 60fps with monotonic timestamps.
    for i in 0..<frameCount {
        let timestamp = Double(i) / fps
        let frame = AnalyzedFrame(
            timestamp: timestamp,
            audioFrame: AudioFrame(timestamp: timestamp, sampleRate: 48000,
                                   sampleCount: 1024, channelCount: 2),
            fftResult: FFTResult(binCount: 512, binResolution: 46.875,
                                 dominantFrequency: 440.0 + Float(i),
                                 dominantMagnitude: 0.5),
            featureVector: FeatureVector(bass: Float(i) / Float(frameCount)),
            emotionalState: EmotionalState(valence: 0.1, arousal: 0.2)
        )
        buffer.enqueue(frame)
    }

    // Read both heads.
    guard let analysisFrame = buffer.dequeueAnalysisHead() else {
        Issue.record("Analysis head returned nil after enqueuing \(frameCount) frames")
        return
    }
    guard let renderFrame = buffer.dequeueRenderHead() else {
        Issue.record("Render head returned nil after enqueuing \(frameCount) frames")
        return
    }

    // Verify analysis head is the latest frame.
    let expectedLatestTimestamp = Double(frameCount - 1) / fps
    #expect(analysisFrame.timestamp == expectedLatestTimestamp,
            "Analysis head should be the latest frame")

    // Measure actual delay between heads.
    let actualDelay = analysisFrame.timestamp - renderFrame.timestamp
    let delayError = abs(actualDelay - configuredDelay)

    #expect(delayError < 0.1,
            """
            Delay error should be within ±100ms of configured \(configuredDelay)s delay.
            Analysis head: \(analysisFrame.timestamp)s
            Render head: \(renderFrame.timestamp)s
            Actual delay: \(actualDelay)s
            Error: \(delayError * 1000)ms
            """)

    // Verify the render frame's feature data is distinct from analysis head.
    #expect(renderFrame.fftResult.dominantFrequency != analysisFrame.fftResult.dominantFrequency,
            "Render and analysis frames should carry different data")
}
