// FFTProcessor — vDSP-based real-time FFT analysis.
// Performs 1024-point FFT on audio samples, producing 512 magnitude bins.
// Results are written into a UMABuffer<Float> for direct GPU consumption
// as a frequency spectrum texture.
//
// Uses Accelerate.framework for SIMD-optimized FFT on Apple Silicon.
// All allocations happen at init time — per-frame processing is zero-alloc.

import Foundation
import Metal
import Accelerate
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.audio", category: "FFTProcessor")

// MARK: - FFTProcessor

/// Real-time FFT analysis using vDSP.
///
/// Produces 512 magnitude bins from 1024-point FFT of audio input.
/// Output is written to a UMA buffer for direct GPU binding.
///
/// Usage:
/// ```swift
/// let fft = try FFTProcessor(device: device)
/// let result = fft.process(samples: audioBuffer.latestSamples(count: 1024))
/// encoder.setBuffer(fft.magnitudeBuffer, offset: 0, index: 1)
/// ```
public final class FFTProcessor: FFTProcessing, @unchecked Sendable {

    // MARK: - Configuration

    /// FFT size (must be power of 2).
    public static let fftSize = 1024

    /// Number of output magnitude bins (fftSize / 2).
    public static let binCount = fftSize / 2

    /// Log2 of FFT size, required by vDSP.
    private static let log2n = vDSP_Length(log2(Double(fftSize)))

    // MARK: - vDSP Resources

    /// The vDSP FFT setup (allocated once, reused every frame).
    private let fftSetup: FFTSetup

    /// Hann window applied before FFT to reduce spectral leakage.
    private var window: [Float]

    /// Split complex buffers for vDSP FFT input/output.
    private var realPart: [Float]
    private var imagPart: [Float]

    /// Windowed time-domain samples (pre-FFT).
    private var windowedSamples: [Float]

    // MARK: - Output Buffers

    /// UMA buffer holding 512 magnitude bins for GPU binding.
    public let magnitudeBuffer: UMABuffer<Float>

    /// Most recent FFT result metadata.
    public private(set) var latestResult = FFTResult()

    /// Reused magnitude scratch (BUG-036). Written only inside `runFFTCore`,
    /// whose sole caller is the real-time audio thread, then copied into the
    /// GPU `magnitudeBuffer` under `lock`. Pre-allocating it keeps the per-frame
    /// path allocation-free (the `// per-frame processing is zero-alloc` header).
    private var magnitudesScratch: [Float]

    /// Lock for thread safety.
    private let lock = NSLock()

    // MARK: - Init

    /// Create an FFT processor with GPU-shared output buffers.
    ///
    /// - Parameter device: Metal device for UMA buffer allocation.
    public init(device: MTLDevice) throws {
        guard let setup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2)) else {
            throw FFTError.setupFailed
        }
        self.fftSetup = setup

        // Pre-allocate all working buffers.
        self.window = [Float](repeating: 0, count: Self.fftSize)
        self.realPart = [Float](repeating: 0, count: Self.binCount)
        self.imagPart = [Float](repeating: 0, count: Self.binCount)
        self.windowedSamples = [Float](repeating: 0, count: Self.fftSize)
        self.magnitudesScratch = [Float](repeating: 0, count: Self.binCount)

        // Generate Hann window.
        vDSP_hann_window(&self.window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))

        // Allocate GPU-shared magnitude buffer.
        self.magnitudeBuffer = try UMABuffer<Float>(device: device, capacity: Self.binCount)

        logger.info("FFTProcessor created: \(Self.fftSize)-point FFT → \(Self.binCount) bins")
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - Processing

    /// Perform FFT on the given samples and write magnitudes to the UMA buffer.
    ///
    /// Input samples should be mono (or pre-mixed to mono). If fewer than
    /// `fftSize` samples are provided, the remainder is zero-padded.
    /// If more are provided, only the last `fftSize` samples are used.
    ///
    /// - Parameter samples: Mono float32 PCM samples.
    /// - Returns: FFT result metadata including dominant frequency.
    @discardableResult
    public func process(samples: [Float], sampleRate: Float = 48000) -> FFTResult {
        let fftLength = Self.fftSize

        // Fill windowed samples: use the latest `fftSize` samples, zero-pad if short.
        windowedSamples.withUnsafeMutableBufferPointer { dst in
            // Zero the buffer first.
            dst.update(repeating: 0)

            let sampleCount = min(samples.count, fftLength)
            let sourceOffset = max(0, samples.count - fftLength)

            samples.withUnsafeBufferPointer { src in
                for i in 0..<sampleCount {
                    dst[i] = src[sourceOffset + i]
                }
            }
        }

        return runFFTCore(sampleRate: sampleRate)
    }

    /// Shared FFT core. Assumes `windowedSamples` already holds the latest
    /// `fftSize` time-domain samples (zero-padded). Applies the Hann window,
    /// runs the forward FFT, writes magnitudes to the GPU buffer, and returns
    /// metadata. Allocation-free — reuses `magnitudesScratch` (BUG-036).
    private func runFFTCore(sampleRate: Float) -> FFTResult {
        let fftLength = Self.fftSize

        // Apply Hann window.
        vDSP_vmul(windowedSamples, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftLength))

        // Convert to split complex format for vDSP FFT.
        // swiftlint:disable force_unwrapping
        windowedSamples.withUnsafeBufferPointer { srcPtr in
            realPart.withUnsafeMutableBufferPointer { realPtr in
                imagPart.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(
                        realp: realPtr.baseAddress!,
                        imagp: imagPtr.baseAddress!
                    )
                    srcPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.binCount) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(Self.binCount))
                    }

                    // Perform forward FFT.
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, Self.log2n, FFTDirection(FFT_FORWARD))

                    // Compute magnitudes: sqrt(real² + imag²) into the reused
                    // scratch (BUG-036 — no per-frame [Float] allocation).
                    vDSP_zvabs(&splitComplex, 1, &magnitudesScratch, 1, vDSP_Length(Self.binCount))

                    // swiftlint:enable force_unwrapping

                    // Normalize by FFT size.
                    var scale = 2.0 / Float(fftLength)
                    vDSP_vsmul(magnitudesScratch, 1, &scale, &magnitudesScratch, 1, vDSP_Length(Self.binCount))

                    // Write to UMA buffer for GPU.
                    lock.lock()
                    magnitudeBuffer.write(magnitudesScratch)

                    // Find dominant frequency.
                    var maxMag: Float = 0
                    var maxIdx: vDSP_Length = 0
                    vDSP_maxvi(magnitudesScratch, 1, &maxMag, &maxIdx, vDSP_Length(Self.binCount))

                    let binResolution = sampleRate / Float(fftLength)
                    latestResult = FFTResult(
                        binCount: UInt32(Self.binCount),
                        binResolution: binResolution,
                        dominantFrequency: Float(maxIdx) * binResolution,
                        dominantMagnitude: maxMag
                    )
                    lock.unlock()
                }
            }
        }

        return latestResult
    }

    // MARK: - Convenience: Process Stereo to Mono

    /// Mix interleaved stereo samples down to mono, then run FFT.
    ///
    /// - Parameters:
    ///   - interleavedSamples: Interleaved stereo float32 PCM (L, R, L, R, ...).
    ///   - sampleRate: Sample rate in Hz.
    /// - Returns: FFT result metadata.
    @discardableResult
    public func processStereo(interleavedSamples: [Float], sampleRate: Float = 48000) -> FFTResult {
        interleavedSamples.withUnsafeBufferPointer {
            processStereo(interleaved: $0, sampleRate: sampleRate)
        }
    }

    /// Zero-allocation stereo path for the real-time audio thread (BUG-036).
    /// Averages interleaved L/R straight into the reused windowed-sample scratch
    /// — no intermediate `mono` array — then runs the shared FFT core. Pass the
    /// most recent `fftSize * 2` interleaved samples; a shorter buffer zero-pads.
    @discardableResult
    public func processStereo(interleaved samples: UnsafeBufferPointer<Float>, sampleRate: Float = 48000) -> FFTResult {
        let fftLength = Self.fftSize
        let frameCount = samples.count / 2

        windowedSamples.withUnsafeMutableBufferPointer { dst in
            dst.update(repeating: 0)

            // Use the latest `fftLength` frames; zero-pad (front) if short.
            let validFrames = min(frameCount, fftLength)
            let frameOffset = max(0, frameCount - fftLength)
            for i in 0..<validFrames {
                let left = samples[(frameOffset + i) * 2]
                let right = samples[(frameOffset + i) * 2 + 1]
                dst[i] = (left + right) * 0.5
            }
        }

        return runFFTCore(sampleRate: sampleRate)
    }
}

// MARK: - FFTError

public enum FFTError: Error, Sendable {
    case setupFailed
}
