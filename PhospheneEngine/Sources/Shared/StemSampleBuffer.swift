// StemSampleBuffer — Interleaved stereo PCM ring buffer for stem separation input.
// CPU-only storage (no Metal dependency). Accumulates audio samples from the render
// callback; the background stem pipeline snapshots the latest N seconds for separation.

import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene", category: "shared")

// MARK: - Protocol

/// Abstracts a ring buffer that accumulates interleaved stereo PCM samples
/// for downstream stem separation. Protocol exists for test doubles.
public protocol StemSampleBuffering: AnyObject, Sendable {
    /// Append interleaved stereo samples to the ring buffer. Thread-safe.
    func write(samples: UnsafePointer<Float>, count: Int)

    /// Copy the latest `seconds` worth of interleaved stereo samples.
    /// Returns an empty array if insufficient data has been written.
    func snapshotLatest(seconds: Double) -> [Float]

    /// Clear all stored samples (e.g., on track change). Thread-safe.
    func reset()
}

// MARK: - StemSampleBuffer

/// Thread-safe interleaved stereo PCM ring buffer.
///
/// Default capacity is 15 seconds at 44.1 kHz stereo (~1.32 M floats ≈ 5 MB).
/// When full, new samples overwrite the oldest. Storage is a plain `[Float]`
/// (CPU-only — no Metal dependency since stem separation reads on CPU before
/// sending to CoreML on ANE).
public final class StemSampleBuffer: StemSampleBuffering, @unchecked Sendable {

    // MARK: - Properties

    private let sampleRate: Double
    private let channelCount: Int = 2  // Always stereo
    private let capacity: Int
    private var storage: [Float]
    private var writeHead: Int = 0
    private var totalWritten: Int = 0
    private let lock = NSLock()

    // MARK: - Init

    /// Create a stem sample buffer.
    ///
    /// - Parameters:
    ///   - sampleRate: Expected sample rate (default 44100 Hz for stem separator).
    ///   - maxSeconds: Maximum audio duration to buffer (default 15 s).
    public init(sampleRate: Double = 44100, maxSeconds: Double = 15) {
        self.sampleRate = sampleRate
        self.capacity = Int(sampleRate * Double(channelCount) * maxSeconds)
        self.storage = [Float](repeating: 0, count: self.capacity)
    }

    // MARK: - StemSampleBuffering

    public func write(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        lock.lock()
        defer { lock.unlock() }

        if count >= capacity {
            // More samples than buffer capacity — keep only the tail.
            let offset = count - capacity
            storage.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.update(from: samples.advanced(by: offset), count: capacity)
            }
            writeHead = 0
            totalWritten += count
        } else if writeHead + count <= capacity {
            // Fits without wrapping.
            storage.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.advanced(by: writeHead).update(from: samples, count: count)
            }
            writeHead += count
            if writeHead == capacity { writeHead = 0 }
            totalWritten += count
        } else {
            // Wraps around the end.
            let firstChunk = capacity - writeHead
            let secondChunk = count - firstChunk
            storage.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.advanced(by: writeHead).update(from: samples, count: firstChunk)
                buf.baseAddress!.update(from: samples.advanced(by: firstChunk), count: secondChunk)
            }
            writeHead = secondChunk
            totalWritten += count
        }
    }

    public func snapshotLatest(seconds: Double) -> [Float] {
        let requestedSamples = Int(sampleRate * Double(channelCount) * seconds)
        lock.lock()
        let available = min(totalWritten, capacity)
        let count = min(requestedSamples, available)
        guard count > 0 else {
            lock.unlock()
            return []
        }

        var result = [Float](repeating: 0, count: count)
        // The latest `count` samples end at writeHead.
        let start = (writeHead - count + capacity) % capacity
        if start + count <= capacity {
            result.withUnsafeMutableBufferPointer { buf in
                storage.withUnsafeBufferPointer { src in
                    buf.baseAddress!.update(from: src.baseAddress!.advanced(by: start), count: count)
                }
            }
        } else {
            let firstChunk = capacity - start
            let secondChunk = count - firstChunk
            result.withUnsafeMutableBufferPointer { buf in
                storage.withUnsafeBufferPointer { src in
                    buf.baseAddress!.update(
                        from: src.baseAddress!.advanced(by: start), count: firstChunk)
                    buf.baseAddress!.advanced(by: firstChunk).update(
                        from: src.baseAddress!, count: secondChunk)
                }
            }
        }
        lock.unlock()
        return result
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        writeHead = 0
        totalWritten = 0
        // Zero the storage to avoid stale data bleeding through.
        storage.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress!.initialize(repeating: 0, count: capacity)
        }
        logger.info("StemSampleBuffer reset")
    }
}
