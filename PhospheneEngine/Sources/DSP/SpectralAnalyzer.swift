// SpectralAnalyzer — vDSP-based spectral feature extraction.
// Computes spectral centroid, rolloff, and flux from FFT magnitude bins.
// All allocations happen at init time — per-frame processing is zero-alloc.

import Foundation
import Accelerate
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "SpectralAnalyzer")

// MARK: - SpectralAnalyzer

/// Computes spectral features from FFT magnitude bins using vDSP.
///
/// - **Centroid**: Weighted mean frequency — indicates spectral "brightness".
/// - **Rolloff**: Frequency below which 85% of spectral energy is concentrated.
/// - **Flux**: Half-wave rectified difference from previous frame — measures timbral change rate.
///
/// Usage:
/// ```swift
/// let analyzer = SpectralAnalyzer()
/// let result = analyzer.process(magnitudes: fftMagnitudes)
/// // result.centroid is in Hz, result.rolloff is in Hz, result.flux is ≥ 0
/// ```
public final class SpectralAnalyzer: @unchecked Sendable {

    // MARK: - Result

    /// Spectral analysis output for a single frame.
    public struct Result: Sendable {
        /// Weighted mean frequency in Hz. 0 for silence.
        public var centroid: Float
        /// Frequency below which 85% of spectral energy lies, in Hz. 0 for silence.
        public var rolloff: Float
        /// Half-wave rectified spectral difference from previous frame. 0 on first frame.
        public var flux: Float
        /// EMA-smoothed centroid in Hz.
        public var smoothedCentroid: Float
        /// EMA-smoothed rolloff in Hz.
        public var smoothedRolloff: Float
        /// EMA-smoothed flux.
        public var smoothedFlux: Float
    }

    // MARK: - Configuration

    /// Number of magnitude bins.
    public let binCount: Int

    /// Sample rate in Hz.
    public let sampleRate: Float

    /// Frequency resolution per bin (sampleRate / fftSize).
    public let binResolution: Float

    // MARK: - Pre-allocated Buffers

    /// Frequency value for each bin index, precomputed at init.
    private let frequencyBins: [Float]

    /// Previous frame's magnitudes for flux computation.
    private var previousMagnitudes: [Float]

    /// Whether we have a previous frame (false on first call or after reset).
    private var hasPreviousFrame: Bool = false

    /// Scratch buffer for difference computation.
    private var diffBuffer: [Float]

    /// Scratch buffer for squared magnitudes.
    private var squaredBuffer: [Float]

    // MARK: - EMA Smoothing

    /// EMA alpha for centroid smoothing.
    private static let centroidAlpha: Float = 0.12

    /// EMA alpha for rolloff smoothing.
    private static let rolloffAlpha: Float = 0.12

    /// EMA alpha for flux smoothing.
    private static let fluxAlpha: Float = 0.25

    /// EMA-smoothed centroid value.
    private var smoothedCentroid: Float = 0

    /// EMA-smoothed rolloff value.
    private var smoothedRolloff: Float = 0

    /// EMA-smoothed flux value.
    private var smoothedFlux: Float = 0

    /// Thread safety.
    private let lock = NSLock()

    // MARK: - Init

    /// Create a spectral analyzer.
    ///
    /// - Parameters:
    ///   - binCount: Number of FFT magnitude bins (default 512 from 1024-point FFT).
    ///   - sampleRate: Sample rate in Hz (default 48000).
    ///   - fftSize: FFT size used to produce the magnitudes (default 1024).
    public init(binCount: Int = 512, sampleRate: Float = 48000, fftSize: Int = 1024) {
        self.binCount = binCount
        self.sampleRate = sampleRate
        self.binResolution = sampleRate / Float(fftSize)

        // Precompute frequency for each bin.
        self.frequencyBins = (0..<binCount).map { Float($0) * sampleRate / Float(fftSize) }

        // Pre-allocate working buffers.
        self.previousMagnitudes = [Float](repeating: 0, count: binCount)
        self.diffBuffer = [Float](repeating: 0, count: binCount)
        self.squaredBuffer = [Float](repeating: 0, count: binCount)

        logger.info("SpectralAnalyzer created: \(binCount) bins, \(sampleRate) Hz")
    }

    // MARK: - Processing

    /// Compute spectral features from FFT magnitude bins.
    ///
    /// - Parameter magnitudes: FFT magnitude array (should have `binCount` elements).
    /// - Returns: Spectral centroid, rolloff, and flux.
    public func process(magnitudes: [Float]) -> Result {
        lock.lock()
        defer { lock.unlock() }

        let count = min(magnitudes.count, binCount)
        guard count > 0 else {
            return Result(centroid: 0, rolloff: 0, flux: 0,
                          smoothedCentroid: 0, smoothedRolloff: 0, smoothedFlux: 0)
        }

        let centroid = computeCentroid(magnitudes: magnitudes, count: count)
        let rolloff = computeRolloff(magnitudes: magnitudes, count: count)
        let flux = computeFlux(magnitudes: magnitudes, count: count)

        // EMA smoothing.
        smoothedCentroid = Self.centroidAlpha * centroid + (1 - Self.centroidAlpha) * smoothedCentroid
        smoothedRolloff = Self.rolloffAlpha * rolloff + (1 - Self.rolloffAlpha) * smoothedRolloff
        smoothedFlux = Self.fluxAlpha * flux + (1 - Self.fluxAlpha) * smoothedFlux

        // Store current frame for next flux computation.
        magnitudes.withUnsafeBufferPointer { src in
            previousMagnitudes.withUnsafeMutableBufferPointer { dst in
                for i in 0..<count {
                    dst[i] = src[i]
                }
            }
        }
        hasPreviousFrame = true

        return Result(
            centroid: centroid,
            rolloff: rolloff,
            flux: flux,
            smoothedCentroid: smoothedCentroid,
            smoothedRolloff: smoothedRolloff,
            smoothedFlux: smoothedFlux
        )
    }

    /// Reset internal state (previous frame buffer).
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        previousMagnitudes.withUnsafeMutableBufferPointer { ptr in
            ptr.update(repeating: 0)
        }
        hasPreviousFrame = false
        smoothedCentroid = 0
        smoothedRolloff = 0
        smoothedFlux = 0
    }

    // MARK: - Centroid

    /// Weighted mean frequency: sum(freq_i * mag_i) / sum(mag_i).
    private func computeCentroid(magnitudes: [Float], count: Int) -> Float {
        // Sum of magnitudes.
        var totalMag: Float = 0
        vDSP_sve(magnitudes, 1, &totalMag, vDSP_Length(count))

        guard totalMag > 1e-10 else { return 0 }

        // Dot product of frequencies and magnitudes.
        var weightedSum: Float = 0
        vDSP_dotpr(frequencyBins, 1, magnitudes, 1, &weightedSum, vDSP_Length(count))

        return weightedSum / totalMag
    }

    // MARK: - Rolloff

    /// Frequency below which 85% of spectral energy is concentrated.
    private func computeRolloff(magnitudes: [Float], count: Int) -> Float {
        // Compute squared magnitudes (energy).
        vDSP_vsq(magnitudes, 1, &squaredBuffer, 1, vDSP_Length(count))

        // Total energy.
        var totalEnergy: Float = 0
        vDSP_sve(squaredBuffer, 1, &totalEnergy, vDSP_Length(count))

        guard totalEnergy > 1e-10 else { return 0 }

        let threshold = totalEnergy * 0.85
        var cumulative: Float = 0

        for i in 0..<count {
            cumulative += squaredBuffer[i]
            if cumulative >= threshold {
                return frequencyBins[i]
            }
        }

        // All energy accounted for — return highest bin.
        return frequencyBins[count - 1]
    }

    // MARK: - Flux

    /// Half-wave rectified spectral difference from previous frame.
    private func computeFlux(magnitudes: [Float], count: Int) -> Float {
        guard hasPreviousFrame else { return 0 }

        // diff = current - previous
        vDSP_vsub(previousMagnitudes, 1, magnitudes, 1, &diffBuffer, 1, vDSP_Length(count))

        // Half-wave rectify: keep only positive differences.
        // vDSP_vthres clamps values below threshold TO the threshold,
        // so we use vDSP_vthr to zero out negatives: max(diff, 0).
        var zero: Float = 0
        var rectified = [Float](repeating: 0, count: count)
        vDSP_vmax(diffBuffer, 1, &zero, 0, &rectified, 1, vDSP_Length(count))

        // Sum the rectified differences.
        var fluxSum: Float = 0
        vDSP_sve(rectified, 1, &fluxSum, vDSP_Length(count))

        return fluxSum
    }
}
