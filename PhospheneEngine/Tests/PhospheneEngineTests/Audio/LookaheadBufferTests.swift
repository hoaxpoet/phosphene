// LookaheadBufferTests — Unit tests for the analysis lookahead ring buffer.
// Verifies dual-head semantics, delay accuracy, overflow, reset, and thread safety.

import Testing
import Foundation
@testable import Audio
@testable import Shared

// MARK: - Helpers

/// Create an AnalyzedFrame with a given timestamp.
private func makeFrame(at timestamp: Double) -> AnalyzedFrame {
    AnalyzedFrame(
        timestamp: timestamp,
        audioFrame: AudioFrame(timestamp: timestamp),
        featureVector: FeatureVector(bass: Float(timestamp))
    )
}

// MARK: - Enqueue / Count

@Test func test_enqueue_incrementsCount() {
    let buffer = LookaheadBuffer(capacity: 64, delay: 0)

    #expect(buffer.frameCount == 0)

    buffer.enqueue(makeFrame(at: 0.0))
    #expect(buffer.frameCount == 1)

    buffer.enqueue(makeFrame(at: 0.016))
    #expect(buffer.frameCount == 2)

    for i in 2..<50 {
        buffer.enqueue(makeFrame(at: Double(i) * 0.016))
    }
    #expect(buffer.frameCount == 50)
}

// MARK: - Analysis Head

@Test func test_dequeueAnalysisHead_returnsLatestFrame() {
    let buffer = LookaheadBuffer(capacity: 64, delay: 2.5)

    buffer.enqueue(makeFrame(at: 1.0))
    buffer.enqueue(makeFrame(at: 2.0))
    buffer.enqueue(makeFrame(at: 3.0))

    let latest = buffer.dequeueAnalysisHead()
    #expect(latest != nil)
    #expect(latest?.timestamp == 3.0)
}

// MARK: - Render Head

@Test func test_dequeueRenderHead_returnsDelayedFrame() {
    let buffer = LookaheadBuffer(capacity: 512, delay: 1.0)

    // Enqueue 120 frames at 60fps (2 seconds of data).
    for i in 0..<120 {
        buffer.enqueue(makeFrame(at: Double(i) / 60.0))
    }

    let renderFrame = buffer.dequeueRenderHead()
    #expect(renderFrame != nil)

    // Latest timestamp is ~1.983s (frame 119).
    // Target = latest - 1.0 ≈ 0.983s → closest frame at ~0.983s (frame 59).
    let latestTimestamp = 119.0 / 60.0
    let expectedTarget = latestTimestamp - 1.0
    let delta = abs((renderFrame?.timestamp ?? 0) - expectedTarget)
    #expect(delta < 0.02, "Render head should be within 20ms of target, got delta \(delta)s")
}

// MARK: - 2500ms Delay

@Test func test_delay_2500ms_renderHeadLagsAnalysisHead() {
    let buffer = LookaheadBuffer(capacity: 512, delay: 2.5)

    // Enqueue 300 frames at 60fps (5 seconds of data).
    for i in 0..<300 {
        buffer.enqueue(makeFrame(at: Double(i) / 60.0))
    }

    let analysisFrame = buffer.dequeueAnalysisHead()
    let renderFrame = buffer.dequeueRenderHead()

    #expect(analysisFrame != nil)
    #expect(renderFrame != nil)

    let lag = (analysisFrame?.timestamp ?? 0) - (renderFrame?.timestamp ?? 0)
    // Lag should be approximately 2.5s, within ±50ms.
    #expect(abs(lag - 2.5) < 0.05,
            "Render head should lag analysis head by 2500ms ±50ms, got \(lag * 1000)ms")
}

// MARK: - Zero Delay

@Test func test_delay_0ms_bothHeadsReturnSameFrame() {
    let buffer = LookaheadBuffer(capacity: 64, delay: 0)

    for i in 0..<30 {
        buffer.enqueue(makeFrame(at: Double(i) / 60.0))
    }

    let analysisFrame = buffer.dequeueAnalysisHead()
    let renderFrame = buffer.dequeueRenderHead()

    #expect(analysisFrame != nil)
    #expect(renderFrame != nil)
    #expect(analysisFrame?.timestamp == renderFrame?.timestamp,
            "With zero delay, both heads should return the same frame")
}

// MARK: - Mid-Stream Delay Change

@Test func test_setDelay_midStream_adjustsSmoothly() {
    let buffer = LookaheadBuffer(capacity: 512, delay: 2.5)

    // Enqueue 300 frames (5s at 60fps).
    for i in 0..<300 {
        buffer.enqueue(makeFrame(at: Double(i) / 60.0))
    }

    // Verify initial 2.5s delay.
    let renderBefore = buffer.dequeueRenderHead()
    let analysisBefore = buffer.dequeueAnalysisHead()
    let lagBefore = (analysisBefore?.timestamp ?? 0) - (renderBefore?.timestamp ?? 0)
    #expect(abs(lagBefore - 2.5) < 0.05, "Initial delay should be ~2.5s")

    // Change delay to 1.0s mid-stream.
    buffer.delay = 1.0

    let renderAfter = buffer.dequeueRenderHead()
    let analysisAfter = buffer.dequeueAnalysisHead()
    let lagAfter = (analysisAfter?.timestamp ?? 0) - (renderAfter?.timestamp ?? 0)
    #expect(abs(lagAfter - 1.0) < 0.05,
            "After delay change, render head should lag by ~1.0s, got \(lagAfter)s")
}

// MARK: - Overflow

@Test func test_buffer_overflow_dropsOldestFrames() {
    let smallCapacity = 10
    let buffer = LookaheadBuffer(capacity: smallCapacity, delay: 0)

    // Enqueue 25 frames into a capacity-10 buffer.
    for i in 0..<25 {
        buffer.enqueue(makeFrame(at: Double(i)))
    }

    // Count should be capped at capacity.
    #expect(buffer.frameCount == smallCapacity)

    // Analysis head should be the most recent frame.
    let latest = buffer.dequeueAnalysisHead()
    #expect(latest?.timestamp == 24.0)

    // Render head (delay=0) should also return the latest.
    let render = buffer.dequeueRenderHead()
    #expect(render?.timestamp == 24.0)
}

// MARK: - Reset

@Test func test_reset_clearsAllFrames() {
    let buffer = LookaheadBuffer(capacity: 64, delay: 0)

    for i in 0..<20 {
        buffer.enqueue(makeFrame(at: Double(i)))
    }
    #expect(buffer.frameCount == 20)

    buffer.reset()

    #expect(buffer.frameCount == 0)
    #expect(buffer.dequeueAnalysisHead() == nil)
    #expect(buffer.dequeueRenderHead() == nil)
}

// MARK: - Empty Buffer

@Test func test_emptyBuffer_dequeue_returnsNil() {
    let buffer = LookaheadBuffer(capacity: 64, delay: 2.5)

    #expect(buffer.dequeueAnalysisHead() == nil)
    #expect(buffer.dequeueRenderHead() == nil)
}

// MARK: - Thread Safety

@Test func test_threadSafety_concurrentEnqueueDequeue_noCrash() async {
    let buffer = LookaheadBuffer(capacity: 256, delay: 1.0)

    // Concurrent writers and readers — no crash or data race.
    await withTaskGroup(of: Void.self) { group in
        // Writer: enqueue 500 frames.
        group.addTask {
            for i in 0..<500 {
                buffer.enqueue(makeFrame(at: Double(i) / 60.0))
                // Yield occasionally to let readers interleave.
                if i % 50 == 0 {
                    await Task.yield()
                }
            }
        }

        // Reader 1: analysis head.
        group.addTask {
            for _ in 0..<200 {
                _ = buffer.dequeueAnalysisHead()
                await Task.yield()
            }
        }

        // Reader 2: render head.
        group.addTask {
            for _ in 0..<200 {
                _ = buffer.dequeueRenderHead()
                await Task.yield()
            }
        }

        // Reader 3: frame count.
        group.addTask {
            for _ in 0..<200 {
                _ = buffer.frameCount
                await Task.yield()
            }
        }
    }

    // If we reach here without crashing, the test passes.
    #expect(buffer.frameCount > 0, "Buffer should have frames after concurrent operations")
}
