// FrameTimingReporter — Per-frame timing accumulator for soak testing (Increment 7.1).
//
// Maintains two views of frame timing:
//   • Cumulative histogram: all frames since init, for percentile queries across a full run.
//   • Rolling 1000-frame window: recent timing, for "is it janky right now" snapshots.
//
// The cumulative histogram uses 100 fixed-width buckets of 0.5 ms each (0–50 ms).
// Anything ≥ 49.5 ms goes into the last bucket. This linear layout is sufficient for
// soak percentile reporting; an HDR histogram would be overkill.
//
// Thread-safety: NSLock guards all mutable state. `record()` is called from the
// @MainActor completed-handler hop (D-060(c)), but the class is `@unchecked Sendable`
// to allow injection from any context.

import Foundation
import QuartzCore

// MARK: - FrameTimingReporter

/// Accumulates per-frame timing data and provides percentile/max snapshots.
///
/// Wire into `RenderPipeline.onFrameTimingObserved` to collect timings:
/// ```swift
/// renderPipeline.onFrameTimingObserved = { [reporter] cpu, gpu in
///     reporter.record(cpuFrameMs: cpu, gpuFrameMs: gpu)
/// }
/// ```
public final class FrameTimingReporter: @unchecked Sendable {

    // MARK: - Snapshot

    /// A point-in-time view of accumulated frame timing data.
    public struct Snapshot: Sendable {
        public let timestamp: TimeInterval
        public let totalFramesObserved: UInt64
        public let cumulativeP50Ms: Float
        public let cumulativeP95Ms: Float
        public let cumulativeP99Ms: Float
        public let cumulativeMaxMs: Float
        /// Frames where `effectiveMs > droppedFrameThresholdMs` (default 32 ms = 1 missed vsync at 60 Hz).
        public let cumulativeDroppedFrames: UInt64
        /// P50 of the last 1000 frames.
        public let recentP50Ms: Float
        /// P95 of the last 1000 frames.
        public let recentP95Ms: Float
        public let recentMaxMs: Float
        /// Dropped frames in the last 1000-frame window.
        public let recentDroppedFrames: UInt32

        public init(timestamp: TimeInterval,
                    totalFramesObserved: UInt64,
                    cumulativeP50Ms: Float,
                    cumulativeP95Ms: Float,
                    cumulativeP99Ms: Float,
                    cumulativeMaxMs: Float,
                    cumulativeDroppedFrames: UInt64,
                    recentP50Ms: Float,
                    recentP95Ms: Float,
                    recentMaxMs: Float,
                    recentDroppedFrames: UInt32) {
            self.timestamp = timestamp
            self.totalFramesObserved = totalFramesObserved
            self.cumulativeP50Ms = cumulativeP50Ms
            self.cumulativeP95Ms = cumulativeP95Ms
            self.cumulativeP99Ms = cumulativeP99Ms
            self.cumulativeMaxMs = cumulativeMaxMs
            self.cumulativeDroppedFrames = cumulativeDroppedFrames
            self.recentP50Ms = recentP50Ms
            self.recentP95Ms = recentP95Ms
            self.recentMaxMs = recentMaxMs
            self.recentDroppedFrames = recentDroppedFrames
        }
    }

    // MARK: - Configuration

    private static let bucketCount = 100
    private static let bucketWidthMs: Float = 0.5
    private static let rollingCapacity = 1000

    // MARK: - Cumulative State

    private var histogram = [UInt64](repeating: 0, count: bucketCount)
    private var cumulativeMax: Float = 0
    private var cumulativeTotal: UInt64 = 0
    private var cumulativeDropped: UInt64 = 0

    // MARK: - Rolling Window State

    private var rollingBuffer = [Float](repeating: 0, count: rollingCapacity)
    private var rollingHead = 0
    private var rollingCount = 0
    private var rollingDropped: UInt32 = 0

    // MARK: - Config

    private let droppedThreshold: Float
    private let lock = NSLock()

    // MARK: - Init

    public init(droppedFrameThresholdMs: Float = 32.0) {
        self.droppedThreshold = droppedFrameThresholdMs
    }

    // MARK: - Record

    /// Record one frame's timing. Uses `max(cpuFrameMs, gpuFrameMs)` — same contract as
    /// `FrameBudgetManager.observe(_:)`.
    public func record(cpuFrameMs: Float, gpuFrameMs: Float?) {
        let effective = max(cpuFrameMs, gpuFrameMs ?? 0)
        lock.withLock {
            // --- Cumulative histogram ---
            let bucket = min(Int(effective / Self.bucketWidthMs), Self.bucketCount - 1)
            histogram[bucket] += 1
            cumulativeTotal += 1
            if effective > cumulativeMax { cumulativeMax = effective }
            if effective > droppedThreshold { cumulativeDropped += 1 }

            // --- Rolling window ---
            // When the buffer is full, the slot at rollingHead holds the oldest value.
            if rollingCount >= Self.rollingCapacity {
                let evicted = rollingBuffer[rollingHead]
                if evicted > droppedThreshold && rollingDropped > 0 {
                    rollingDropped -= 1
                }
            }
            rollingBuffer[rollingHead] = effective
            if effective > droppedThreshold { rollingDropped += 1 }
            rollingHead = (rollingHead + 1) % Self.rollingCapacity
            if rollingCount < Self.rollingCapacity { rollingCount += 1 }
        }
    }

    // MARK: - Snapshot

    /// Build a snapshot of current state.
    public func snapshot(now: TimeInterval = CACurrentMediaTime()) -> Snapshot {
        lock.withLock {
            Snapshot(
                timestamp: now,
                totalFramesObserved: cumulativeTotal,
                cumulativeP50Ms: cumulativePercentile(0.50),
                cumulativeP95Ms: cumulativePercentile(0.95),
                cumulativeP99Ms: cumulativePercentile(0.99),
                cumulativeMaxMs: cumulativeMax,
                cumulativeDroppedFrames: cumulativeDropped,
                recentP50Ms: recentPercentile(0.50),
                recentP95Ms: recentPercentile(0.95),
                recentMaxMs: recentMax(),
                recentDroppedFrames: rollingDropped
            )
        }
    }

    // MARK: - Reset

    /// Reset all accumulated data.
    public func reset() {
        lock.withLock {
            histogram = [UInt64](repeating: 0, count: Self.bucketCount)
            cumulativeMax = 0
            cumulativeTotal = 0
            cumulativeDropped = 0
            rollingBuffer = [Float](repeating: 0, count: Self.rollingCapacity)
            rollingHead = 0
            rollingCount = 0
            rollingDropped = 0
        }
    }

    // MARK: - Private Helpers (call while holding lock)

    private func cumulativePercentile(_ fraction: Float) -> Float {
        guard cumulativeTotal > 0 else { return 0 }
        // Find first bucket where strictly more than fraction*total samples are covered.
        // Using `>` (not `>=`) ensures that when exactly fraction*total samples land in
        // one bucket, we continue to the next — so P99 with 1 spike in 100 frames
        // returns the spike's bucket, not the 99-frame bucket.
        let threshold = UInt64(Double(cumulativeTotal) * Double(fraction))
        var running: UInt64 = 0
        for (index, count) in histogram.enumerated() {
            running += count
            if running > threshold {
                return Float(index) * Self.bucketWidthMs + Self.bucketWidthMs / 2
            }
        }
        return cumulativeMax
    }

    private func recentPercentile(_ fraction: Float) -> Float {
        guard rollingCount > 0 else { return 0 }
        var values: [Float]
        if rollingCount < Self.rollingCapacity {
            values = Array(rollingBuffer.prefix(rollingCount))
        } else {
            // Unwrap ring buffer: tail portion first (oldest), then head portion (newest).
            values = Array(rollingBuffer[rollingHead...]) + Array(rollingBuffer[..<rollingHead])
        }
        values.sort()
        let idx = min(Int(Float(values.count - 1) * fraction), values.count - 1)
        return values[idx]
    }

    private func recentMax() -> Float {
        guard rollingCount > 0 else { return 0 }
        if rollingCount < Self.rollingCapacity {
            return rollingBuffer.prefix(rollingCount).max() ?? 0
        }
        return rollingBuffer.max() ?? 0
    }
}
