// StemSampleBuffer — Interleaved stereo PCM ring buffer for stem separation input.
// CPU-only storage (no Metal dependency). Accumulates audio samples from the render
// callback; the background stem pipeline snapshots the latest N seconds for separation.

import Accelerate
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

    /// Copy the latest `seconds` of interleaved stereo samples using `sampleRate`
    /// as the actual audio rate instead of the buffer's stored initialization rate.
    ///
    /// Use this when the Core Audio tap rate differs from the rate the buffer was
    /// initialized with (e.g. tap at 48000 Hz, buffer initialized at 44100 Hz).
    /// Passing the actual rate ensures the correct number of frames is retrieved.
    func snapshotLatest(seconds: Double, sampleRate: Double) -> [Float]

    /// Compute the RMS energy of the latest `seconds` of buffered audio.
    /// Returns 0 if no data is available. Thread-safe.
    func rms(seconds: Double) -> Float

    /// Compute the RMS energy of the latest `seconds` using `sampleRate` as the
    /// actual audio rate, mirroring the rate-aware `snapshotLatest` overload so
    /// callers running on a tap whose rate differs from the buffer init rate
    /// (e.g. tap at 48000 Hz, buffer initialized at 44100 Hz) measure energy
    /// over the correct number of frames.
    func rms(seconds: Double, sampleRate: Double) -> Float

    /// Clear all stored samples (e.g., on track change). Thread-safe.
    func reset()
}

// MARK: - StemSampleBuffer

/// Thread-safe interleaved stereo PCM ring buffer.
///
/// Default capacity is 15 seconds at 44.1 kHz stereo (~1.32 M floats ≈ 5 MB).
/// When full, new samples overwrite the oldest. Storage is a plain `[Float]`
/// (CPU-only — no Metal dependency since stem separation reads on CPU before
/// dispatching to MPSGraph on GPU).
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
                guard let base = buf.baseAddress else { return }
                base.update(from: samples.advanced(by: offset), count: capacity)
            }
            writeHead = 0
            totalWritten += count
        } else if writeHead + count <= capacity {
            // Fits without wrapping.
            storage.withUnsafeMutableBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                base.advanced(by: writeHead).update(from: samples, count: count)
            }
            writeHead += count
            if writeHead == capacity { writeHead = 0 }
            totalWritten += count
        } else {
            // Wraps around the end.
            let firstChunk = capacity - writeHead
            let secondChunk = count - firstChunk
            storage.withUnsafeMutableBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                base.advanced(by: writeHead).update(from: samples, count: firstChunk)
                base.update(from: samples.advanced(by: firstChunk), count: secondChunk)
            }
            writeHead = secondChunk
            totalWritten += count
        }
    }

    public func snapshotLatest(seconds: Double) -> [Float] {
        snapshotLatest(seconds: seconds, sampleRate: sampleRate)
    }

    public func snapshotLatest(seconds: Double, sampleRate actualRate: Double) -> [Float] {
        let requestedSamples = Int(actualRate * Double(channelCount) * seconds)
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
                    guard let dst = buf.baseAddress, let srcBase = src.baseAddress else { return }
                    dst.update(from: srcBase.advanced(by: start), count: count)
                }
            }
        } else {
            let firstChunk = capacity - start
            let secondChunk = count - firstChunk
            result.withUnsafeMutableBufferPointer { buf in
                storage.withUnsafeBufferPointer { src in
                    guard let dst = buf.baseAddress, let srcBase = src.baseAddress else { return }
                    dst.update(from: srcBase.advanced(by: start), count: firstChunk)
                    dst.advanced(by: firstChunk).update(from: srcBase, count: secondChunk)
                }
            }
        }
        lock.unlock()
        return result
    }

    /// Compute the RMS energy of the latest `seconds` of buffered audio.
    /// Returns 0 if no data is available. Thread-safe.
    public func rms(seconds: Double) -> Float {
        rms(seconds: seconds, sampleRate: sampleRate)
    }

    public func rms(seconds: Double, sampleRate actualRate: Double) -> Float {
        let requestedSamples = Int(actualRate * Double(channelCount) * seconds)
        lock.lock()
        let available = min(totalWritten, capacity)
        let count = min(requestedSamples, available)
        guard count > 0 else {
            lock.unlock()
            return 0
        }

        let start = (writeHead - count + capacity) % capacity
        var sumOfSquares: Float = 0

        storage.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            if start + count <= capacity {
                // Contiguous region.
                vDSP_svesq(srcBase.advanced(by: start), 1, &sumOfSquares, vDSP_Length(count))
            } else {
                // Wraps — two contiguous chunks.
                let firstChunk = capacity - start
                var sum1: Float = 0
                var sum2: Float = 0
                vDSP_svesq(srcBase.advanced(by: start), 1, &sum1, vDSP_Length(firstChunk))
                vDSP_svesq(srcBase, 1, &sum2, vDSP_Length(count - firstChunk))
                sumOfSquares = sum1 + sum2
            }
        }
        lock.unlock()

        return sqrtf(sumOfSquares / Float(count))
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        writeHead = 0
        totalWritten = 0
        // Zero the storage to avoid stale data bleeding through.
        storage.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            base.initialize(repeating: 0, count: capacity)
        }
        logger.info("StemSampleBuffer reset")
    }
}
