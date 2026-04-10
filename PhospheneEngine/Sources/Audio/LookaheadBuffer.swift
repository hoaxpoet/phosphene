// LookaheadBuffer — Timestamped ring buffer with dual read heads.
// Enables anticipatory visual decisions by maintaining a configurable
// delay between analysis (latest frame) and rendering (delayed frame).
//
// The analysis head always returns the most recently enqueued frame.
// The render head returns the frame whose timestamp is closest to
// (latest timestamp - delay). With a 2.5s delay, the Orchestrator
// sees 2.5 seconds into the future relative to what's being rendered.
//
// Thread safety: all access is synchronized via NSLock. The buffer is
// written from the analysis pipeline and read from the render loop,
// which run on different threads.

import Foundation
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.audio", category: "LookaheadBuffer")

// MARK: - LookaheadBuffer

/// A timestamped ring buffer providing dual read heads for analysis lookahead.
///
/// Enqueue `AnalyzedFrame` values from the analysis pipeline. Read from
/// two heads:
/// - **Analysis head**: returns the latest frame (real-time).
/// - **Render head**: returns the frame delayed by `delay` seconds.
///
/// When `delay` is 0, both heads return the same frame.
public final class LookaheadBuffer: @unchecked Sendable {

    // MARK: - Configuration

    /// Default lookahead delay in seconds.
    public static let defaultDelay: Double = 2.5

    /// Maximum number of frames the buffer can hold.
    /// At 60fps with 2.5s delay, we need ~150 frames minimum.
    /// 512 gives comfortable headroom for variable frame rates.
    public static let defaultCapacity: Int = 512

    // MARK: - State

    private var storage: [AnalyzedFrame]
    private let capacity: Int
    private var head: Int = 0
    private var count: Int = 0
    private let lock = NSLock()

    /// Whether the buffer has any enqueued frames. Must be called with `lock` held.
    private var isEmptyUnlocked: Bool { count < 1 }

    /// Current lookahead delay in seconds.
    private var _delay: Double

    // MARK: - Init

    /// Create a lookahead buffer.
    ///
    /// - Parameters:
    ///   - capacity: Maximum number of frames to store. Defaults to 512.
    ///   - delay: Lookahead delay in seconds. Defaults to 2.5s.
    public init(capacity: Int = LookaheadBuffer.defaultCapacity,
                delay: Double = LookaheadBuffer.defaultDelay) {
        precondition(capacity > 0, "LookaheadBuffer capacity must be positive")
        precondition(delay >= 0, "LookaheadBuffer delay must be non-negative")
        self.capacity = capacity
        self._delay = delay
        self.storage = [AnalyzedFrame](repeating: .empty, count: capacity)
        logger.info("LookaheadBuffer created: capacity=\(capacity), delay=\(delay)s")
    }

    // MARK: - Public API

    /// The current lookahead delay in seconds.
    public var delay: Double {
        get { lock.withLock { _delay } }
        set {
            precondition(newValue >= 0, "Delay must be non-negative")
            lock.withLock { _delay = newValue }
            logger.info("Lookahead delay set to \(newValue)s")
        }
    }

    /// Number of frames currently in the buffer.
    public var frameCount: Int {
        lock.withLock { count }
    }

    /// Enqueue an analyzed frame.
    ///
    /// When the buffer is full, the oldest frame is overwritten.
    public func enqueue(_ frame: AnalyzedFrame) {
        lock.withLock {
            storage[head] = frame
            head = (head + 1) % capacity
            if count < capacity {
                count += 1
            }
        }
    }

    /// Read the analysis head — the most recently enqueued frame.
    ///
    /// Returns `nil` if the buffer is empty.
    public func dequeueAnalysisHead() -> AnalyzedFrame? {
        lock.withLock {
            guard !isEmptyUnlocked else { return nil }
            let latestIndex = (head - 1 + capacity) % capacity
            return storage[latestIndex]
        }
    }

    /// Read the render head — the frame delayed by `delay` seconds.
    ///
    /// Finds the frame whose timestamp is closest to
    /// `(latest timestamp - delay)`. Returns `nil` if the buffer is empty.
    ///
    /// When `delay` is 0, returns the same frame as `dequeueAnalysisHead()`.
    public func dequeueRenderHead() -> AnalyzedFrame? {
        lock.withLock {
            guard !isEmptyUnlocked else { return nil }

            let latestIndex = (head - 1 + capacity) % capacity
            let latestTimestamp = storage[latestIndex].timestamp
            let targetTimestamp = latestTimestamp - _delay

            // If delay is zero or we don't have enough history, return the
            // oldest available frame or the latest.
            if _delay == 0 {
                return storage[latestIndex]
            }

            // Search for the frame closest to targetTimestamp.
            // Frames are stored in chronological order in the ring.
            var bestIndex = tailIndex
            var bestDelta = Double.greatestFiniteMagnitude

            for i in 0..<count {
                let physicalIndex = (tailIndex + i) % capacity
                let delta = abs(storage[physicalIndex].timestamp - targetTimestamp)
                if delta < bestDelta {
                    bestDelta = delta
                    bestIndex = physicalIndex
                }
            }

            return storage[bestIndex]
        }
    }

    /// Reset the buffer, discarding all frames.
    public func reset() {
        lock.withLock {
            head = 0
            count = 0
        }
        logger.info("LookaheadBuffer reset")
    }

    // MARK: - Private

    /// Index of the oldest valid frame (requires lock held).
    private var tailIndex: Int {
        if count < capacity { return 0 }
        return head  // head points to the next write position = oldest when full
    }
}
