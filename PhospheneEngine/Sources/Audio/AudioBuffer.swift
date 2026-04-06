// AudioBuffer — Bridges audio input into UMA ring buffers for GPU consumption.
// Writes interleaved float32 PCM from Core Audio tap callbacks or raw sample
// arrays into a UMARingBuffer<Float>. Exposes the latest N samples as a
// Metal-bindable buffer for shader access.
//
// Threading: The write path is called from the real-time audio IO thread;
// the read path (buffer binding) is called from the render loop. The
// UMARingBuffer's underlying MTLBuffer is safe to bind to a render encoder
// while the CPU writes to a different region, because Metal command buffers
// execute after encoding is complete.

import Foundation
import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.audio", category: "AudioBuffer")

// MARK: - AudioBuffer

/// Writes PCM audio samples into a UMA ring buffer for GPU consumption.
///
/// The ring buffer holds a sliding window of recent audio samples. The GPU
/// reads the entire buffer each frame as waveform data. Older samples are
/// silently overwritten as new audio arrives.
public final class AudioBuffer: @unchecked Sendable {

    // MARK: - Configuration

    /// Number of PCM samples in the ring buffer (per channel).
    /// 1024 samples ≈ 21ms at 48kHz — one shader frame's worth of waveform.
    public static let defaultWaveformCapacity = 1024

    /// Total interleaved sample capacity (stereo = 2 × waveformCapacity).
    public static let defaultCapacity = defaultWaveformCapacity * 2

    // MARK: - Storage

    /// The UMA ring buffer holding interleaved float32 PCM samples.
    public let pcmRingBuffer: UMARingBuffer<Float>

    /// Running sample count for debug/monitoring.
    private var totalSamplesWritten: UInt64 = 0

    /// Lock for thread-safe write access.
    private let lock = NSLock()

    // MARK: - RMS Monitoring

    /// Most recent RMS level (linear, 0–1 range after typical normalization).
    /// Updated on each write for debug monitoring.
    public private(set) var currentRMS: Float = 0

    // MARK: - Init

    /// Create an AudioBuffer backed by a UMA ring buffer.
    ///
    /// - Parameters:
    ///   - device: Metal device for buffer allocation.
    ///   - capacity: Total interleaved sample capacity. Defaults to 2048 (1024 stereo frames).
    public init(device: MTLDevice, capacity: Int = AudioBuffer.defaultCapacity) throws {
        self.pcmRingBuffer = try UMARingBuffer<Float>(device: device, capacity: capacity)
        logger.info("AudioBuffer created: \(capacity) samples (\(capacity / 2) stereo frames)")
    }

    // MARK: - Writing from pointer (Core Audio tap callback path)

    /// Write interleaved float32 PCM from a raw pointer into the ring buffer.
    /// This is the primary write path, called from the real-time audio IO thread.
    /// Do not allocate memory in this method.
    ///
    /// - Parameters:
    ///   - pointer: Pointer to interleaved float32 samples.
    ///   - count: Number of float samples (not frames).
    /// - Returns: Number of samples written.
    @discardableResult
    public func write(from pointer: UnsafePointer<Float>, count: Int) -> Int {
        guard count > 0 else { return 0 }

        let samples = UnsafeBufferPointer(start: pointer, count: count)
        let rms = computeRMS(samples)

        lock.lock()
        pcmRingBuffer.write(contentsOf: samples)
        totalSamplesWritten += UInt64(count)
        currentRMS = rms
        lock.unlock()

        return count
    }

    // MARK: - Writing from raw Float array (file playback path)

    /// Write raw float32 samples into the ring buffer.
    ///
    /// - Parameter samples: Interleaved float32 PCM samples.
    /// - Returns: Number of samples written.
    @discardableResult
    public func write(samples: [Float]) -> Int {
        guard !samples.isEmpty else { return 0 }

        let rms = samples.withUnsafeBufferPointer { computeRMS($0) }

        lock.lock()
        pcmRingBuffer.write(contentsOf: samples)
        totalSamplesWritten += UInt64(samples.count)
        currentRMS = rms
        lock.unlock()

        return samples.count
    }

    // MARK: - GPU Binding

    /// The underlying MTLBuffer for binding to a Metal render/compute encoder.
    /// Contains the most recent `capacity` interleaved float32 samples.
    public var metalBuffer: MTLBuffer { pcmRingBuffer.buffer }

    /// Current write head position in the ring buffer.
    /// Shaders can use this to locate the newest sample.
    public var head: Int {
        lock.lock()
        defer { lock.unlock() }
        return pcmRingBuffer.head
    }

    /// Number of valid samples currently in the buffer.
    public var sampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pcmRingBuffer.count
    }

    /// Total samples written since creation (for debug/stats).
    public var totalWritten: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return totalSamplesWritten
    }

    // MARK: - Latest Samples Extraction (for FFT)

    /// Copy the most recent N interleaved samples from the ring buffer.
    /// Returns fewer samples if the buffer hasn't filled yet.
    ///
    /// - Parameter count: Number of samples to extract.
    /// - Returns: Array of the most recent samples, oldest first.
    public func latestSamples(count: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        let available = min(count, pcmRingBuffer.count)
        guard available > 0 else { return [] }

        var result = [Float]()
        result.reserveCapacity(available)

        let startLogical = pcmRingBuffer.count - available
        for i in 0..<available {
            result.append(pcmRingBuffer.read(at: startLogical + i))
        }

        return result
    }

    // MARK: - Debug

    /// Reset the buffer to empty state.
    public func reset() {
        lock.lock()
        pcmRingBuffer.reset()
        totalSamplesWritten = 0
        currentRMS = 0
        lock.unlock()
    }

    // MARK: - RMS Computation

    private func computeRMS(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sumOfSquares: Float = 0
        for sample in samples {
            sumOfSquares += sample * sample
        }
        return sqrtf(sumOfSquares / Float(samples.count))
    }
}
