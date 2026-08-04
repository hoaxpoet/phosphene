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
        /// DYN.1 — fraction of spectral energy above `densitySplitHz`, 0…1, EMA-smoothed
        /// to τ ≈ 6 s. Deliberately NOT the raw per-frame value, which turns 5.59 times a
        /// second and reads on screen as jitter.
        ///
        /// The ONE quantity in the pipeline that survives normalisation, because it is
        /// computed here from the raw magnitudes — before `MIRPipeline`'s total-energy
        /// AGC and before `BandDeviationTracker`'s per-band EMA. A scalar gain anywhere
        /// upstream scales every bin equally and cancels in the ratio.
        ///
        /// WHY THIS AND NOT A LEVEL. Measured on session `2026-08-04T14-58-10Z`
        /// (Cherub Rock): RMS is flat at −14 dBFS from 24 s to the end of the track —
        /// the master is limited, so there is no level change to detect. What moves when
        /// the distorted guitar enters is spectral density: this fraction runs 0.084–0.10
        /// through the verse and rises to 0.14–0.22 from ~75 s. Distortion adds harmonics,
        /// not amplitude, and that is what a listener hears as "it got louder".
        public var density: Float
        /// Slow EMA of `density` (τ ≈ 8 s). Lets a consumer read "denser than this
        /// track's normal" rather than an absolute, without rolling its own state.
        public var smoothedDensity: Float
        /// DYN.1b — SECTION SURGE, 0…1. Rises fast when the mix arrives, and HOLDS.
        ///
        /// The field for "the tree shoots up when the distorted guitar enters" — which
        /// Matt defines concretely as the trunk elongating and the next level of branches
        /// appearing. Both are STEPS that persist, and nothing else here can express one:
        /// every other field is instantaneous or averaged, so a preset can only scale it.
        /// An asymmetric follower turns an arrival into something a visual can sit on.
        ///
        /// Driven by pre-AGC LEVEL, not spectral shape. Measured on `2026-08-04T19-20-32Z`
        /// at the guitar entry, a level surge separates the pre-guitar passage from the
        /// arrival **20.4×** (0.048 → 0.981) while turning only 0.58 times a second. Shape
        /// cannot: the clean intro is BRIGHTER (HF 0.22) than the pre-guitar passage
        /// (HF 0.03), so it confuses a bright quiet intro with a loud arrival.
        ///
        /// The reasoning that earlier ruled level out was wrong in a specific way: the
        /// BODY of a limited master is flat, so level looked useless — but the intro→body
        /// transition is 26 dB. Limiting flattens the body, not the arrival.
        public var surge: Float
    }

    // MARK: - Configuration

    /// Number of magnitude bins.
    public let binCount: Int

    /// Sample rate in Hz. Mutable via `setSampleRate(_:)` so the live pipeline
    /// can adopt the actual tap rate once it is known (BUG-053).
    public private(set) var sampleRate: Float

    /// FFT size used to derive the bin→Hz mapping. Needed to recompute the
    /// frequency table on a `setSampleRate(_:)` reconfigure.
    private let fftSize: Int

    /// Frequency resolution per bin (sampleRate / fftSize).
    public private(set) var binResolution: Float

    /// Split point for `Result.density`. 1.5 kHz sits above the fundamental range of
    /// most rhythm-section content and below the harmonics distortion adds, which is
    /// what makes the fraction move when a guitar dirties up at constant level.
    static let densitySplitHz: Float = 1500

    // MARK: - Pre-allocated Buffers

    /// Frequency value for each bin index, recomputed on every rate change.
    private var frequencyBins: [Float]

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

    /// DYN.1 legs, at the ~10 Hz MIR rate: `density` at τ ≈ 0.8 s against
    /// `smoothedDensity` at τ ≈ 45 s, so the pair reads "this moment against this track's
    /// normal".
    ///
    /// THE FAST LEG'S WIDTH IS THE WHOLE BALLGAME, and it was wrong twice in opposite
    /// directions. Measured against a real capture (`2026-08-04T17-17-01Z`, distorted
    /// guitar entering at ~20 s, where an independent time-domain measure shows a 3.22×
    /// rise in high-frequency energy):
    ///
    ///     τ 6.0 s   1.15×   — swallows the event whole; the field looked broken
    ///     τ 1.5 s   2.22×
    ///     τ 0.8 s   2.98×   — 93 % of the reference, and the count turns only 0.41/s
    ///     τ 0.45 s  3.36×   — no better on response, and 50 % more restless
    ///
    /// τ 6 s was chosen when the TRUNK read this field and was bouncing. The trunk no
    /// longer reads it at all (FTR.3f confined density to the quantised branch count), so
    /// the smoothing that was protecting the trunk was only destroying the signal. Widen
    /// this only if something continuous starts reading density again — and the answer to
    /// that is to stop it reading density, not to re-smooth the field.
    ///
    /// The raw per-frame fraction turns 5.59 times a second, which is why SOME smoothing
    /// is still required; `density` is deliberately not instantaneous.
    private static let densityFastAlpha: Float = 0.117
    private static let densityAlpha: Float = 0.0022

    /// EMA-smoothed centroid value.
    private var smoothedCentroid: Float = 0

    /// EMA-smoothed rolloff value.
    private var smoothedRolloff: Float = 0

    /// EMA-smoothed flux value.
    private var smoothedFlux: Float = 0

    /// EMA-smoothed spectral density, both legs (DYN.1).
    private var fastDensity: Float = 0
    private var smoothedLevelDB: Float = -120
    private var surge: Float = 0
    private var smoothedDensity: Float = 0
    /// False until the first non-silent frame seeds both density legs.
    private var densitySeeded = false

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
        self.fftSize = fftSize
        self.binResolution = sampleRate / Float(fftSize)

        // Precompute frequency for each bin.
        self.frequencyBins = (0..<binCount).map { Float($0) * sampleRate / Float(fftSize) }

        // Pre-allocate working buffers.
        self.previousMagnitudes = [Float](repeating: 0, count: binCount)
        self.diffBuffer = [Float](repeating: 0, count: binCount)
        self.squaredBuffer = [Float](repeating: 0, count: binCount)

        logger.info("SpectralAnalyzer created: \(binCount) bins, \(sampleRate) Hz")
    }

    // MARK: - Reconfigure

    /// Adopt a new sample rate, recomputing the bin→Hz frequency table.
    ///
    /// BUG-053: the live pipeline constructs at a default rate before the tap
    /// installs; this lets it switch to the actual tap rate (and a device-swap
    /// rate change) without rebuilding. Running smoothing state is preserved.
    /// No-op when the rate is unchanged. Call on the same serial context as
    /// `process(...)` (the analysis queue) — the recompute runs under `lock`.
    public func setSampleRate(_ newSampleRate: Float) {
        guard newSampleRate > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard abs(newSampleRate - sampleRate) > 0.5 else { return }
        sampleRate = newSampleRate
        binResolution = newSampleRate / Float(fftSize)
        for i in 0..<binCount {
            frequencyBins[i] = Float(i) * binResolution
        }
        logger.info("SpectralAnalyzer reconfigured: \(newSampleRate) Hz")
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
            return Result(
                centroid: 0,
                rolloff: 0,
                flux: 0,
                smoothedCentroid: 0,
                smoothedRolloff: 0,
                smoothedFlux: 0,
                density: 0,
                smoothedDensity: 0,
                surge: 0
            )
        }

        let centroid = computeCentroid(magnitudes: magnitudes, count: count)
        let rolloff = computeRolloff(magnitudes: magnitudes, count: count)
        let flux = computeFlux(magnitudes: magnitudes, count: count)
        let rawDensity = computeDensity(magnitudes: magnitudes, count: count)

        // EMA smoothing.
        smoothedCentroid = Self.centroidAlpha * centroid + (1 - Self.centroidAlpha) * smoothedCentroid
        smoothedRolloff = Self.rolloffAlpha * rolloff + (1 - Self.rolloffAlpha) * smoothedRolloff
        smoothedFlux = Self.fluxAlpha * flux + (1 - Self.fluxAlpha) * smoothedFlux
        // SEED BOTH LEGS ON THE FIRST NON-SILENT FRAME. Without this the τ45 s baseline
        // climbs from 0 and never catches the fast leg inside a track: measured on Matt's
        // 2026-08-04T17-17-01Z capture the ratio sat at 2–6× and the resulting lift was
        // PINNED AT 1.00 from 20 s onward — a constant, incapable of the jump it exists to
        // produce ("there is no jump in growth when the distorted guitar kicks in").
        // Same fix BandDeviationTracker already applies to its per-band averages.
        if !densitySeeded && rawDensity > 0 {
            fastDensity = rawDensity
            smoothedDensity = rawDensity
            densitySeeded = true
        }
        // PRE-AGC LEVEL by Parseval: total spectral energy is proportional to signal
        // power, and these magnitudes are the raw FFT — upstream of every normaliser.
        var spectralEnergy: Float = 0
        for i in 0..<count { spectralEnergy += magnitudes[i] * magnitudes[i] }
        let levelDB = 10 * log10f(max(spectralEnergy, 1e-20))
        smoothedLevelDB = Self.levelAlpha * levelDB + (1 - Self.levelAlpha) * smoothedLevelDB
        let surgeTarget = Self.smoothstepf(Self.surgeLowDB, Self.surgeHighDB, smoothedLevelDB)
        // Asymmetric: arrive fast, leave slowly. A symmetric follower falls back between
        // phrases and reads as the pumping this field exists to avoid.
        let surgeAlpha = surgeTarget > surge ? Self.surgeAttack : Self.surgeRelease
        surge = surgeAlpha * surgeTarget + (1 - surgeAlpha) * surge

        fastDensity = Self.densityFastAlpha * rawDensity + (1 - Self.densityFastAlpha) * fastDensity
        smoothedDensity = Self.densityAlpha * rawDensity + (1 - Self.densityAlpha) * smoothedDensity

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
            smoothedFlux: smoothedFlux,
            density: fastDensity,
            smoothedDensity: smoothedDensity,
            surge: surge
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
        fastDensity = 0
        smoothedDensity = 0
        densitySeeded = false
        smoothedLevelDB = -120
        surge = 0
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
