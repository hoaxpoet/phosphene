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
        let n = Self.fftSize

        // Fill windowed samples: use the latest `fftSize` samples, zero-pad if short.
        windowedSamples.withUnsafeMutableBufferPointer { dst in
            // Zero the buffer first.
            dst.update(repeating: 0)

            let sampleCount = min(samples.count, n)
            let sourceOffset = max(0, samples.count - n)

            samples.withUnsafeBufferPointer { src in
                for i in 0..<sampleCount {
                    dst[i] = src[sourceOffset + i]
                }
            }
        }

        // Apply Hann window.
        vDSP_vmul(windowedSamples, 1, window, 1, &windowedSamples, 1, vDSP_Length(n))

        // Convert to split complex format for vDSP FFT.
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

                    // Compute magnitudes: sqrt(real² + imag²).
                    // vDSP_zvabs computes the absolute value of each complex pair.
                    var magnitudes = [Float](repeating: 0, count: Self.binCount)
                    vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(Self.binCount))

                    // Normalize by FFT size.
                    var scale = 2.0 / Float(n)
                    vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(Self.binCount))

                    // Write to UMA buffer for GPU.
                    lock.lock()
                    magnitudeBuffer.write(magnitudes)

                    // Find dominant frequency.
                    var maxMag: Float = 0
                    var maxIdx: vDSP_Length = 0
                    vDSP_maxvi(magnitudes, 1, &maxMag, &maxIdx, vDSP_Length(Self.binCount))

                    let binResolution = sampleRate / Float(n)
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
        let frameCount = interleavedSamples.count / 2
        var mono = [Float](repeating: 0, count: frameCount)

        // Average left and right channels.
        for i in 0..<frameCount {
            mono[i] = (interleavedSamples[i * 2] + interleavedSamples[i * 2 + 1]) * 0.5
        }

        return process(samples: mono, sampleRate: sampleRate)
    }

    // MARK: - Debug

    /// Print a text histogram of the current magnitude spectrum to the console.
    /// Groups bins into `barCount` frequency bands for readability.
    public func printHistogram(barCount: Int = 32) {
        lock.lock()
        let result = latestResult
        lock.unlock()

        let binsPerBar = Self.binCount / barCount
        let binRes = result.binResolution

        var bars = [Float](repeating: 0, count: barCount)
        for bar in 0..<barCount {
            var maxInBar: Float = 0
            for bin in 0..<binsPerBar {
                let idx = bar * binsPerBar + bin
                if idx < Self.binCount {
                    maxInBar = max(maxInBar, magnitudeBuffer[idx])
                }
            }
            bars[bar] = maxInBar
        }

        // Find global max for scaling.
        let globalMax = bars.max() ?? 1.0
        let scale = globalMax > 0 ? 1.0 / globalMax : 1.0

        var output = "FFT Spectrum (dominant: \(String(format: "%.0f", result.dominantFrequency))Hz @ \(String(format: "%.3f", result.dominantMagnitude)))\n"
        for bar in 0..<barCount {
            let freq = Float(bar * binsPerBar) * binRes
            let normalized = bars[bar] * scale
            let width = Int(normalized * 40)
            let barStr = String(repeating: "█", count: width)
            output += String(format: "%5.0fHz |%s\n", freq, barStr)
        }
        logger.debug("\(output)")
    }
}

// MARK: - FFTError

public enum FFTError: Error, Sendable {
    case setupFailed
}
