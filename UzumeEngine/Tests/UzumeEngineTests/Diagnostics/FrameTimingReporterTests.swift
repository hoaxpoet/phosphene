// FrameTimingReporterTests — Unit tests for FrameTimingReporter (always-run, Increment 7.1).
//
// Verifies the rolling window, cumulative histogram, percentile computation,
// dropped-frame counting, and reset behaviour.

import Testing
import Foundation
@testable import Diagnostics

@Suite("FrameTimingReporter")
struct FrameTimingReporterTests {

    // MARK: - Empty State

    @Test("Empty reporter produces zero snapshot")
    func emptyReporter() {
        let reporter = FrameTimingReporter()
        let snap = reporter.snapshot()
        #expect(snap.totalFramesObserved == 0)
        #expect(snap.cumulativeP50Ms == 0)
        #expect(snap.cumulativeP95Ms == 0)
        #expect(snap.cumulativeP99Ms == 0)
        #expect(snap.cumulativeMaxMs == 0)
        #expect(snap.cumulativeDroppedFrames == 0)
        #expect(snap.recentP50Ms == 0)
        #expect(snap.recentP95Ms == 0)
        #expect(snap.recentMaxMs == 0)
        #expect(snap.recentDroppedFrames == 0)
    }

    // MARK: - Uniform 16 ms Frames

    @Test("100 frames at 16 ms: P50 ≈ 16 ms, no drops")
    func uniformSixteenMs() {
        let reporter = FrameTimingReporter()
        for _ in 0..<100 {
            reporter.record(cpuFrameMs: 16.0, gpuFrameMs: nil)
        }
        let snap = reporter.snapshot()
        #expect(snap.totalFramesObserved == 100)
        #expect(snap.cumulativeDroppedFrames == 0, "No frame should exceed 32 ms threshold")
        // P50 should land in the 16 ms bucket (±bucketWidth 0.5 ms).
        #expect(snap.cumulativeP50Ms >= 15.5 && snap.cumulativeP50Ms <= 16.5,
                "P50 should be ≈ 16 ms, got \(snap.cumulativeP50Ms)")
        #expect(snap.cumulativeMaxMs >= 15.5 && snap.cumulativeMaxMs <= 16.5,
                "Max should be ≈ 16 ms, got \(snap.cumulativeMaxMs)")
    }

    // MARK: - Dropped Frame Counting

    @Test("Every 10th frame at 40 ms produces 10 dropped frames")
    func droppedFrameCounting() {
        let reporter = FrameTimingReporter()
        for i in 0..<100 {
            let ms: Float = (i % 10 == 9) ? 40.0 : 16.0
            reporter.record(cpuFrameMs: ms, gpuFrameMs: nil)
        }
        let snap = reporter.snapshot()
        #expect(snap.cumulativeDroppedFrames == 10,
                "Expected 10 dropped frames (every 10th frame at 40 ms > 32 ms threshold)")
        #expect(snap.cumulativeP95Ms >= 32.0,
                "P95 should reflect the spike frames, got \(snap.cumulativeP95Ms)")
    }

    // MARK: - GPU vs CPU Max

    @Test("gpuFrameMs > cpuFrameMs → reporter uses GPU value")
    func gpuDominates() {
        let reporter = FrameTimingReporter()
        reporter.record(cpuFrameMs: 10.0, gpuFrameMs: 40.0)
        let snap = reporter.snapshot()
        #expect(snap.cumulativeMaxMs >= 39.5,
                "When gpuFrameMs > cpuFrameMs, the GPU value should be used (got \(snap.cumulativeMaxMs))")
        #expect(snap.cumulativeDroppedFrames == 1,
                "40 ms GPU frame should count as dropped (> 32 ms threshold)")
    }

    // MARK: - Rolling Window

    @Test("Rolling window reflects only the last 1000 frames")
    func rollingWindowBoundary() {
        let reporter = FrameTimingReporter()
        // First 501 frames at 16 ms.
        for _ in 0..<501 {
            reporter.record(cpuFrameMs: 16.0, gpuFrameMs: nil)
        }
        // Next 1000 frames at 8 ms.
        for _ in 0..<1000 {
            reporter.record(cpuFrameMs: 8.0, gpuFrameMs: nil)
        }
        let snap = reporter.snapshot()
        // The recent window (last 1000) should be all 8 ms — the 16 ms frames were evicted.
        #expect(snap.recentP50Ms <= 9.0,
                "Recent P50 should reflect the last 1000 frames (8 ms), got \(snap.recentP50Ms)")
        // Cumulative still includes the earlier 16 ms frames.
        #expect(snap.totalFramesObserved == 1501)
    }

    // MARK: - Reset

    @Test("reset() clears all accumulated data")
    func resetClearsData() {
        let reporter = FrameTimingReporter()
        for _ in 0..<50 {
            reporter.record(cpuFrameMs: 20.0, gpuFrameMs: nil)
        }
        reporter.reset()
        let snap = reporter.snapshot()
        #expect(snap.totalFramesObserved == 0)
        #expect(snap.cumulativeMaxMs == 0)
        #expect(snap.recentDroppedFrames == 0)
    }

    // MARK: - Percentile Accuracy

    @Test("Percentile returns 0 when no frames observed")
    func emptyPercentile() {
        let reporter = FrameTimingReporter()
        let snap = reporter.snapshot()
        #expect(snap.cumulativeP99Ms == 0)
        #expect(snap.recentP95Ms == 0)
    }

    @Test("Cumulative P99 reflects 1% worst-case frames")
    func cumulativeP99() {
        let reporter = FrameTimingReporter()
        // 99 frames at 16 ms + 1 frame at 48 ms (1% spike).
        for _ in 0..<99 {
            reporter.record(cpuFrameMs: 16.0, gpuFrameMs: nil)
        }
        reporter.record(cpuFrameMs: 48.0, gpuFrameMs: nil)
        let snap = reporter.snapshot()
        // P99 should land in the 48 ms bucket (last bucket).
        #expect(snap.cumulativeP99Ms >= 46.0,
                "P99 should reflect the spike at 48 ms, got \(snap.cumulativeP99Ms)")
        #expect(snap.cumulativeP50Ms <= 17.0,
                "P50 should still be ≈ 16 ms, got \(snap.cumulativeP50Ms)")
    }
}
