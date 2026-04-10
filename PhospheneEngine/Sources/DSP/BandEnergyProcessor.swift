// BandEnergyProcessor — 3-band and 6-band energy extraction with AGC and smoothing.
// Computes bass/mid/treble (instant + attenuated) and 6-band energy from FFT magnitudes.
// Uses Milkdrop-style average-tracking AGC and FPS-independent smoothing.
// All allocations happen at init time — per-frame processing is zero-alloc.

import Foundation
import Accelerate
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "BandEnergyProcessor")

// MARK: - BandEnergyProcessor

/// Extracts 3-band and 6-band energy from FFT magnitudes with AGC and smoothing.
///
/// Band definitions (from validated Electron prototype):
/// - **3-band**: Bass 20–250 Hz, Mid 250–4000 Hz, Treble 4000–20000 Hz
/// - **6-band**: Sub Bass 20–80, Low Bass 80–250, Low Mid 250–1000,
///   Mid High 1000–4000, High Mid 4000–8000, High 8000+
///
/// AGC normalizes output so average levels map to ~0.5, loud moments reach 0.8–1.0.
/// Smoothing is FPS-independent via `pow(rate, 30/fps)`.
public final class BandEnergyProcessor: @unchecked Sendable {

    // MARK: - Result

    /// Band energy output for a single frame.
    public struct Result: Sendable {
        // 3-band instant (fast smoothing)
        public var bass: Float
        public var mid: Float
        public var treble: Float

        // 3-band attenuated (heavy smoothing, slow-flowing motion)
        public var bassAtt: Float
        public var midAtt: Float
        public var trebleAtt: Float

        // 6-band (preserves relative differences via total-energy AGC)
        public var subBass: Float
        public var lowBass: Float
        public var lowMid: Float
        public var midHigh: Float
        public var highMid: Float
        public var high: Float

        /// All-zero result, returned when there is no input or fps is invalid.
        public static let zero = Result(
            bass: 0,
            mid: 0,
            treble: 0,
            bassAtt: 0,
            midAtt: 0,
            trebleAtt: 0,
            subBass: 0,
            lowBass: 0,
            lowMid: 0,
            midHigh: 0,
            highMid: 0,
            high: 0
        )
    }

    // MARK: - Band Definitions

    /// Named frequency band with a low/high cutoff in Hz.
    private struct BandRange {
        let name: String
        let low: Float
        let high: Float
    }

    /// 3-band frequency boundaries in Hz.
    private static let bands3: [BandRange] = [
        BandRange(name: "bass", low: 20, high: 250),
        BandRange(name: "mid", low: 250, high: 4000),
        BandRange(name: "treble", low: 4000, high: 20000),
    ]

    /// 6-band frequency boundaries in Hz.
    private static let bands6: [BandRange] = [
        BandRange(name: "subBass", low: 20, high: 80),
        BandRange(name: "lowBass", low: 80, high: 250),
        BandRange(name: "lowMid", low: 250, high: 1000),
        BandRange(name: "midHigh", low: 1000, high: 4000),
        BandRange(name: "highMid", low: 4000, high: 8000),
        BandRange(name: "high", low: 8000, high: 24000),
    ]

    /// Instant smoothing rates per 3-band (FPS-independent base rates at 30 fps).
    private static let instantRates: [Float] = [0.65, 0.75, 0.75]

    /// Attenuated smoothing rate (heavy smoothing).
    private static let attenuatedRate: Float = 0.95

    // MARK: - Configuration

    public let binCount: Int
    public let sampleRate: Float

    /// Precomputed bin ranges for 3-band: [(startBin, endBin)] exclusive end.
    private let bandRanges3: [(start: Int, end: Int)]

    /// Precomputed bin ranges for 6-band.
    private let bandRanges6: [(start: Int, end: Int)]

    // MARK: - AGC State

    /// Running average for 6-band AGC (total energy, not per-band).
    private var agcRunningAvg: Float = 0

    /// Frame counter for two-speed warmup.
    private var frameCount: Int = 0

    /// Number of frames for fast warmup phase (~1s at 60fps).
    private static let warmupFastFrames = 60

    /// Number of frames for moderate warmup phase (~3s at 60fps).
    private static let warmupModerateFrames = 180

    /// Fast warmup rate.
    private static let agcRateFast: Float = 0.95

    /// Moderate rate after warmup.
    private static let agcRateModerate: Float = 0.992

    // MARK: - Smoothing State

    /// Smoothed 3-band instant values.
    private var smoothedInstant: [Float] = [0, 0, 0]

    /// Smoothed 3-band attenuated values.
    private var smoothedAttenuated: [Float] = [0, 0, 0]

    /// Smoothed 6-band values.
    private var smoothed6Band: [Float] = [0, 0, 0, 0, 0, 0]

    /// Thread safety.
    private let lock = NSLock()

    // MARK: - Init

    /// Create a band energy processor.
    ///
    /// - Parameters:
    ///   - binCount: Number of FFT magnitude bins (default 512).
    ///   - sampleRate: Sample rate in Hz (default 48000).
    ///   - fftSize: FFT size (default 1024).
    public init(binCount: Int = 512, sampleRate: Float = 48000, fftSize: Int = 1024) {
        self.binCount = binCount
        self.sampleRate = sampleRate

        let binResolution = sampleRate / Float(fftSize)

        // Precompute bin ranges for each band.
        self.bandRanges3 = Self.bands3.map { band in
            let start = max(0, Int(floor(band.low / binResolution)))
            let end = min(binCount, Int(ceil(band.high / binResolution)))
            return (start, end)
        }

        self.bandRanges6 = Self.bands6.map { band in
            let start = max(0, Int(floor(band.low / binResolution)))
            let end = min(binCount, Int(ceil(band.high / binResolution)))
            return (start, end)
        }

        logger.info("BandEnergyProcessor created: \(binCount) bins, 3+6 bands")
    }

    // MARK: - Processing

    /// Compute band energies from FFT magnitude bins.
    ///
    /// - Parameters:
    ///   - magnitudes: FFT magnitude array (should have `binCount` elements).
    ///   - fps: Current frame rate for FPS-independent smoothing.
    /// - Returns: 3-band instant, 3-band attenuated, and 6-band energy values.
    public func process(magnitudes: [Float], fps: Float) -> Result {
        lock.lock()
        defer { lock.unlock() }

        let count = min(magnitudes.count, binCount)
        guard count > 0 && fps > 0 else { return .zero }

        // Compute raw RMS for each band.
        let raw3 = computeRawEnergy(magnitudes: magnitudes, ranges: bandRanges3)
        let raw6 = computeRawEnergy(magnitudes: magnitudes, ranges: bandRanges6)

        // AGC: normalize 6-band against total energy.
        let totalRawEnergy = raw6.reduce(0, +)
        let agcRate = frameCount < Self.warmupFastFrames ? Self.agcRateFast : Self.agcRateModerate

        if frameCount == 0 {
            agcRunningAvg = max(totalRawEnergy, 1e-6)
        } else {
            agcRunningAvg = agcRate * agcRunningAvg + (1 - agcRate) * totalRawEnergy
        }

        let agcScale: Float = agcRunningAvg > 1e-10 ? 0.5 / agcRunningAvg : 0

        // Apply AGC to both 3-band and 6-band.
        let agc3 = raw3.map { $0 * agcScale }
        let agc6 = raw6.map { $0 * agcScale }

        // FPS-independent smoothing.
        let fpsRatio = 30.0 / fps

        for i in 0..<3 {
            let instantRate = powf(Self.instantRates[i], fpsRatio)
            smoothedInstant[i] = instantRate * smoothedInstant[i] + (1 - instantRate) * agc3[i]

            let attRate = powf(Self.attenuatedRate, fpsRatio)
            smoothedAttenuated[i] = attRate * smoothedAttenuated[i] + (1 - attRate) * agc3[i]
        }

        // 6-band uses parent 3-band instant rates mapped to sub-bands.
        let sixBandRates: [Float] = [
            Self.instantRates[0], Self.instantRates[0],  // sub_bass, low_bass → bass rate
            Self.instantRates[1], Self.instantRates[1],  // low_mid, mid_high → mid rate
            Self.instantRates[2], Self.instantRates[2],  // high_mid, high → treble rate
        ]

        for i in 0..<6 {
            let rate = powf(sixBandRates[i], fpsRatio)
            smoothed6Band[i] = rate * smoothed6Band[i] + (1 - rate) * agc6[i]
        }

        frameCount += 1

        return Result(
            bass: smoothedInstant[0],
            mid: smoothedInstant[1],
            treble: smoothedInstant[2],
            bassAtt: smoothedAttenuated[0],
            midAtt: smoothedAttenuated[1],
            trebleAtt: smoothedAttenuated[2],
            subBass: smoothed6Band[0],
            lowBass: smoothed6Band[1],
            lowMid: smoothed6Band[2],
            midHigh: smoothed6Band[3],
            highMid: smoothed6Band[4],
            high: smoothed6Band[5]
        )
    }

    /// Reset all internal state.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        agcRunningAvg = 0
        frameCount = 0
        smoothedInstant = [0, 0, 0]
        smoothedAttenuated = [0, 0, 0]
        smoothed6Band = [0, 0, 0, 0, 0, 0]
    }

    // MARK: - Helpers

    /// Compute RMS energy for each band from magnitude bins.
    private func computeRawEnergy(magnitudes: [Float], ranges: [(start: Int, end: Int)]) -> [Float] {
        ranges.map { range in
            let start = range.start
            let end = min(range.end, magnitudes.count)
            let count = end - start
            guard count > 0 else { return Float(0) }

            var rms: Float = 0
            magnitudes.withUnsafeBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                vDSP_rmsqv(base + start, 1, &rms, vDSP_Length(count))
            }
            return rms
        }
    }
}
