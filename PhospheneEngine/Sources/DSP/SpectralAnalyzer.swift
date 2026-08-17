// SpectralAnalyzer — vDSP-based spectral feature extraction.
// Computes spectral centroid, rolloff, and flux from FFT magnitude bins.
// All allocations happen at init time — per-frame processing is zero-alloc.

import Foundation
import Accelerate
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "SpectralAnalyzer")

// MARK: - SpectralAnalyzer

/// Computes spectral features from FFT magnitude bins using vDSP.
///
/// - **Centroid**: Weighted mean frequency — indicates spectral "brightness".
/// - **Rolloff**: Frequency below which 85% of spectral energy is concentrated.
/// - **Flux**: Half-wave rectified difference from previous frame — measures timbral change rate.
public final class SpectralAnalyzer: @unchecked Sendable {

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

    // DYN.5 — the spectral-feature followers, in SECONDS; the last per-FRAME alphas in this
    // file. Each tau is what its old coefficient meant at the 43.07 Hz reference rate, so
    // nothing is retuned — only the rate dependence goes.
    static let centroidTau: Float = LoudnessProfile.tau(legacyAlpha: 0.12)   // ≈ 0.18 s
    static let rolloffTau: Float = LoudnessProfile.tau(legacyAlpha: 0.12)    // ≈ 0.18 s
    static let fluxTau: Float = LoudnessProfile.tau(legacyAlpha: 0.25)       // ≈ 0.08 s

    // DYN.1 density legs: a fast leg against a slow one, so the pair reads "this moment
    // against this track's normal". THE FAST LEG'S WIDTH IS THE WHOLE BALLGAME and was wrong
    // twice in opposite directions — the sweep is in `docs/ENGINE/DYN1_CALIBRATION.md` §1;
    // do not duplicate it here. The trunk reads the SECTION leg (DYN.2), never this one.
    //
    // DYN.4 — widths in SECONDS, converted per frame. See LoudnessProfile §Smoothing time
    // constants. Each tau is what its old coefficient meant at the reference rate.
    static let densityFastTau: Float = LoudnessProfile.tau(legacyAlpha: 0.117)     // ≈ 0.19 s
    static let densitySlowTau: Float = LoudnessProfile.tau(legacyAlpha: 0.0022)    // ≈ 10.5 s
    /// DYN.2b at the MEASURED 43 Hz analysis rate: τ20 s section leg over a τ45 s normal.
    /// The first cut used 0.0021 (τ10) against `densityAlpha` — but that "τ45" constant was
    /// sized under the old wrong ~10 Hz assumption and is really τ9.7 s, so the two legs
    /// landed 0.38 % apart, the ratio was a constant 1.00 and the trunk never moved.
    static let densitySectionTau: Float = LoudnessProfile.densitySectionTau         // ≈ 20 s
    /// FTR.9 — section-RATIO smoothing, after the rank. See `advanceLevelAndDensity`.
    static let sectionRatioTau: Float = 1.0
    static let densityNormalTau: Float = LoudnessProfile.tau(legacyAlpha: 0.00052) // ≈ 44.6 s

    /// FTR.9 — the section ratio after its own τ1 s smoothing; what consumers read. Seeded
    /// on the first analysis frame rather than ramping from zero. `internal` like the rest
    /// of the density state: the follower that owns it lives in `SpectralAnalyzer+Density`.
    var smoothedSectionRatio: Float = 0
    var sectionRatioSeeded = false

    /// EMA-smoothed centroid value.
    private var smoothedCentroid: Float = 0

    /// EMA-smoothed rolloff value.
    private var smoothedRolloff: Float = 0

    /// EMA-smoothed flux value.
    private var smoothedFlux: Float = 0

    /// EMA-smoothed spectral density, both legs (DYN.1).
    var fastDensity: Float = 0
    var sectionDensity: Float = 0
    var densityNormal: Float = 0
    var smoothedLevelDB: Float = -120
    var surge: Float = 0
    /// FTR.24a — the level-rise accent, its short pre-smoothing, and the ring the fixed-lag
    /// difference reads. `smoothedLevelDB` (τ 0.76 s) cannot see a transient at all; a trailing
    /// MINIMUM of the raw level, which this first used, is not rate-invariant (22× across the
    /// two real analysis rates — see `SpectralAnalyzer+Density`).
    var levelRise: Float = 0
    var preSmoothedLevelDB: Float = -120
    var recentLevelDB: [Float] = []
    var smoothedDensity: Float = 0
    /// False until the first non-silent frame seeds both density legs.
    private var densitySeeded = false

    /// DYN.1c — installed per track via `setLoudnessProfile(_:)`; `nil` ⇒ fixed band.
    /// Not `private`: the setter lives in `SpectralAnalyzer+Density.swift`.
    var loudnessProfile: LoudnessProfile?

    /// Thread safety. Not `private` — `SpectralAnalyzer+Density.swift` locks around the
    /// DYN.1c profile install.
    let lock = NSLock()

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
    public func process(magnitudes: [Float], deltaTime: Float) -> Result {
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
                sectionRatio: 1,
                surge: 0,
                levelRise: 0
            )
        }

        let centroid = computeCentroid(magnitudes: magnitudes, count: count)
        let rolloff = computeRolloff(magnitudes: magnitudes, count: count)
        let flux = computeFlux(magnitudes: magnitudes, count: count)
        let rawDensity = computeDensity(magnitudes: magnitudes, count: count)

        // EMA smoothing (DYN.5 — widths in seconds, alpha derived from this frame).
        func blend(_ current: Float, _ target: Float, tau: Float) -> Float {
            let alpha = LoudnessProfile.emaAlpha(deltaTime: deltaTime, tau: tau)
            return alpha * target + (1 - alpha) * current
        }
        smoothedCentroid = blend(smoothedCentroid, centroid, tau: Self.centroidTau)
        smoothedRolloff = blend(smoothedRolloff, rolloff, tau: Self.rolloffTau)
        smoothedFlux = blend(smoothedFlux, flux, tau: Self.fluxTau)
        // SEED BOTH LEGS ON THE FIRST NON-SILENT FRAME. Without this the τ45 s baseline
        // climbs from 0 and never catches the fast leg inside a track: measured on Matt's
        // 2026-08-04T17-17-01Z capture the ratio sat at 2–6× and the resulting lift was
        // PINNED AT 1.00 from 20 s onward — a constant, incapable of the jump it exists to
        // produce ("there is no jump in growth when the distorted guitar kicks in").
        // Same fix BandDeviationTracker already applies to its per-band averages.
        if !densitySeeded && rawDensity > 0 {
            fastDensity = rawDensity
            smoothedDensity = rawDensity
            sectionDensity = rawDensity   // DYN.2: seed with the others (same reason)
            densityNormal = rawDensity
            densitySeeded = true
        }
        advanceLevelAndDensity(deltaTime: deltaTime, rawDensity: rawDensity, magnitudes: magnitudes, count: count)

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
            // DYN.2c: the OFFLINE normal when a local-file profile is installed — it is
            // right from frame 1. The live τ45 s EMA remains the streaming fallback, where
            // no full decode exists; there it still needs ~90 s to mean anything.
            sectionRatio: smoothedSectionRatio,
            surge: surge,
            levelRise: levelRise
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
        smoothedSectionRatio = 0
        sectionRatioSeeded = false
        smoothedRolloff = 0
        smoothedFlux = 0
        fastDensity = 0
        sectionDensity = 0
        densityNormal = 0
        smoothedDensity = 0
        densitySeeded = false
        smoothedLevelDB = -120
        surge = 0
        levelRise = 0
        preSmoothedLevelDB = -120
        recentLevelDB.removeAll(keepingCapacity: true)
        // `loudnessProfile` intentionally NOT cleared — see `setLoudnessProfile(_:)`.
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
