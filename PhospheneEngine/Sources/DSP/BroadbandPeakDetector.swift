// BroadbandPeakDetector — Broadband spectral-flux peak detection for BPM-anchored
// phase acquisition (BSAudit.3 / BUG-017).
//
// Consumes `SpectralAnalyzer.smoothedFlux` per frame and emits a boolean peak
// event when the smoothed flux exceeds an adaptive median by `thresholdMultiplier`,
// is on a rising edge, and the BPM-aware refractory window has expired.
//
// Why broadband, not sub-bass:
//   Per CLAUDE.md Failed Approach #68, the sub-bass onset detector fires on
//   sub-bass *events* (bass notes, 808s, synth bass) — not beats. Broadband
//   flux integrates kick + snare + claps + vocal accents + chord changes
//   across the spectrum, which correlates with perceived beats across
//   rhythmic styles (BSAudit.3 design §6.3).
//
// Why an adaptive median, not a fixed threshold:
//   Flux magnitude varies with mix density, AGC running-max state, and
//   per-track production style. An adaptive median over the last ~1 s of
//   frames absorbs those variations so the same threshold multiplier
//   (1.8×) works across the catalog.
//
// Refractory period:
//   `0.4 × (60 / cachedBPM)` seconds — short enough to admit hits on each
//   beat at typical tempos, long enough to suppress double-firing on the
//   same beat. Falls back to 200 ms when no BPM has been installed.

import Foundation
import os.log

private let logger = Logger(
    subsystem: "com.phosphene.dsp",
    category: "BroadbandPeakDetector"
)

// MARK: - BroadbandPeakDetector

/// Detects per-frame broadband-flux peaks for beat-phase anchoring.
///
/// Stateful, single-instance-per-track. Thread-safe via NSLock; designed to
/// be driven from the MIRPipeline per-frame path.
public final class BroadbandPeakDetector: @unchecked Sendable {

    // MARK: - Tunables (BSAudit.3 design §6.3)

    /// Threshold multiplier — peaks must exceed `adaptiveMedian × this`.
    /// Higher than BeatDetector's per-band 1.5 because broadband flux is
    /// noisier (integrates across the whole spectrum).
    public static let thresholdMultiplier: Float = 1.8

    /// Adaptive median window in frames. 60 ≈ 1 s at 60 fps.
    public static let medianWindowFrames: Int = 60

    /// Refractory fraction of one beat period — `period × this` is the
    /// minimum spacing between peaks. 0.4 admits one peak per beat at
    /// typical tempos and suppresses double-firing on the same beat.
    public static let refractoryFraction: Double = 0.4

    /// Fallback refractory period (seconds) when no BPM has been installed.
    /// Matches roughly the BeatDetector sub-bass band cooldown.
    public static let defaultRefractorySeconds: Double = 0.2

    /// Minimum frames in the median buffer before peaks fire. Below this,
    /// the adaptive median is unreliable so we wait. ~5 frames ≈ 83 ms at
    /// 60 fps.
    public static let medianWarmupFrames: Int = 5

    // MARK: - State (lock-guarded)

    private var fluxBuffer: [Float]
    private var fluxHead: Int = 0
    private var fluxCount: Int = 0
    private var previousFlux: Float = 0
    private var hasPreviousFrame: Bool = false
    private var refractoryRemaining: Double = 0
    private var refractorySeconds: Double = BroadbandPeakDetector.defaultRefractorySeconds
    private let lock = NSLock()

    // MARK: - Init

    public init() {
        self.fluxBuffer = [Float](
            repeating: 0,
            count: Self.medianWindowFrames
        )
    }

    // MARK: - BPM Configuration

    /// Configure the refractory period from the installed BPM. Pass 0 (or
    /// any non-positive value) to revert to `defaultRefractorySeconds`.
    /// Safe to call at any time; the next `process` call uses the new value.
    public func setBPM(_ bpm: Double) {
        lock.lock(); defer { lock.unlock() }
        if bpm > 0 {
            refractorySeconds = Self.refractoryFraction * (60.0 / bpm)
        } else {
            refractorySeconds = Self.defaultRefractorySeconds
        }
    }

    /// Current refractory period in seconds (for diagnostics / tests).
    public var currentRefractorySeconds: Double {
        lock.lock(); defer { lock.unlock() }
        return refractorySeconds
    }

    // MARK: - Processing

    /// Process one frame's smoothed flux. Returns true when a broadband peak
    /// was detected on this frame.
    ///
    /// - Parameters:
    ///   - smoothedFlux: `SpectralAnalyzer.Result.smoothedFlux` for the frame.
    ///   - deltaTime: Seconds since the last `process` call.
    /// - Returns: `true` when the current frame is a broadband peak.
    public func process(smoothedFlux: Float, deltaTime: Float) -> Bool {
        lock.lock(); defer { lock.unlock() }

        let dt = Double(max(deltaTime, 0))
        refractoryRemaining = max(0, refractoryRemaining - dt)

        // Push the current sample into the circular median buffer.
        fluxBuffer[fluxHead] = smoothedFlux
        fluxHead = (fluxHead + 1) % Self.medianWindowFrames
        fluxCount = min(fluxCount + 1, Self.medianWindowFrames)

        defer {
            previousFlux = smoothedFlux
            hasPreviousFrame = true
        }

        guard fluxCount >= Self.medianWarmupFrames else { return false }
        guard hasPreviousFrame else { return false }
        guard refractoryRemaining <= 0 else { return false }

        let median = medianLocked()
        let threshold = median * Self.thresholdMultiplier

        // Rising edge above adaptive threshold. The flux is already EMA-
        // smoothed upstream (SpectralAnalyzer.fluxAlpha = 0.25), so the
        // rising-edge gate cleanly identifies the first frame at which the
        // broadband event has reached its peak amplitude band.
        let isRising = smoothedFlux > previousFlux
        let aboveThreshold = smoothedFlux > threshold

        if isRising && aboveThreshold {
            refractoryRemaining = refractorySeconds
            return true
        }
        return false
    }

    /// Clear all internal state. Use on track change.
    public func reset() {
        lock.lock(); defer { lock.unlock() }
        for i in 0..<fluxBuffer.count { fluxBuffer[i] = 0 }
        fluxHead = 0
        fluxCount = 0
        previousFlux = 0
        hasPreviousFrame = false
        refractoryRemaining = 0
        // refractorySeconds intentionally NOT reset — it's a per-track
        // tunable installed via setBPM and should survive transient
        // pipeline restarts within the same track.
    }

    // MARK: - Helpers

    /// Compute the median of the populated portion of `fluxBuffer`.
    /// Caller must hold the lock. Allocates one scratch buffer; called
    /// once per frame so the per-frame cost is small.
    private func medianLocked() -> Float {
        let count = fluxCount
        guard count > 0 else { return 0 }
        var scratch = [Float](repeating: 0, count: count)
        // Copy in arrival order — order doesn't matter for median.
        for i in 0..<count { scratch[i] = fluxBuffer[i] }
        scratch.sort()
        if count.isMultiple(of: 2) {
            return (scratch[count / 2 - 1] + scratch[count / 2]) * 0.5
        }
        return scratch[count / 2]
    }
}
