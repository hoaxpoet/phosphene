// BeatPredictor — Predicts beat phase between detected onsets.
//
// Fed by BeatDetector output (beatBass, beatMid, beatComposite) plus the
// current frame timestamp.  Exposes beatPhase01 (0 at the last confirmed
// beat, linearly rising to 1 at the predicted next beat) and beatsUntilNext
// (fractional; 1.0 immediately after each beat).
//
// Why this matters (MV-3b, D-028): current presets can only react AFTER a
// beat lands.  With phase prediction a preset can begin its animation ramp
// slightly before the beat — the "anticipatory" motion that characterises
// live musicians and feel-good VJ performance.
//
// Algorithm:
//   1. Detect rising edge: beatValue = max(bass, mid, composite) > 0.5
//      and previous frame's value was ≤ 0.5.
//   2. On onset: if a valid inter-beat interval (0.2s–1.5s) was measured,
//      update the IIR period: period = 0.3 × period + 0.7 × interval.
//   3. Each frame: phase = (now − lastBeatTime) / estimatedPeriod, clamped 0–1.
//   4. If no beat for > 3 × estimatedPeriod: phase resets to 0 (tempo lost).
//   5. Bootstrap: `bootstrapBPM` seeds the period estimate so that once the
//      first live onset arrives the predictor can produce a valid phase
//      immediately (instead of needing two onsets to measure a period).
//      Phase remains 0 until the first onset lands.
//
// Thread safety: all mutable state is guarded by NSLock.
// Used from MIRPipeline.process() on the analysis queue.

import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "BeatPredictor")

// MARK: - BeatPredictor

/// Predicts beat phase and time-until-next-beat from BeatDetector onset pulses.
public final class BeatPredictor: @unchecked Sendable {

    // MARK: - Result

    /// Per-frame output placed into FeatureVector.
    public struct Result: Sendable {
        /// Phase in the current beat cycle. 0 at the last confirmed beat,
        /// linearly rises to 1 at the predicted next beat.
        /// Clamped to [0, 1]. Resets to 0 when tempo is lost.
        public var beatPhase01: Float
        /// Fractional beats until the next predicted beat (1 − beatPhase01).
        public var beatsUntilNext: Float
    }

    // MARK: - State

    private var elapsedTime: Double = 0            // accumulated from deltaTime
    private var lastBeatTime: Double = -1.0
    private var estimatedPeriod: Double = 0.5      // 120 BPM default
    private var hasPeriod: Bool = false
    private var prevBeatValue: Float = 0
    private var _bootstrapBPM: Float?
    private let lock = NSLock()

    // MARK: - Init

    public init() {}

    // MARK: - Bootstrap

    /// Seeds the period estimate from a known BPM.
    ///
    /// Call this when a TrackProfile BPM is available (e.g. from metadata
    /// pre-fetch).  Once the first live onset lands the predictor produces a
    /// valid phase immediately (no two-onset warm-up needed).  Phase remains 0
    /// until the first onset; `lastBeatTime` is not seeded here.
    /// Ignored once the IIR has been updated by a live beat.
    public func setBootstrapBPM(_ bpm: Float) {
        lock.lock()
        defer { lock.unlock() }
        _bootstrapBPM = bpm
        if !hasPeriod && bpm > 0 {
            estimatedPeriod = Double(60.0 / bpm)
            hasPeriod = true
            logger.debug("BeatPredictor bootstrapped at \(bpm, format: .fixed(precision: 1)) BPM")
        }
    }

    // MARK: - Update

    /// Advance the predictor by one frame and return the current phase.
    ///
    /// - Parameters:
    ///   - beatBass: Bass beat pulse from BeatDetector (0–1 decaying).
    ///   - beatMid: Mid beat pulse from BeatDetector (0–1 decaying).
    ///   - beatComposite: Composite beat pulse (0–1 decaying).
    ///   - time: Current time in seconds (same domain across all calls — e.g.
    ///     MIRPipeline's `elapsedSeconds`).
    ///   - deltaTime: Seconds since the last call (unused for phase, kept for
    ///     API consistency with other analyzers).
    /// - Returns: Beat phase prediction for this frame.
    public func update(
        beatBass: Float, beatMid: Float, beatComposite: Float,
        time: Float, deltaTime: Float
    ) -> Result {
        lock.lock()
        defer { lock.unlock() }

        // Accumulate elapsed time from deltaTime so timing is correct regardless
        // of what the caller passes for `time` (MIRPipeline passes 0 currently).
        elapsedTime += Double(max(deltaTime, 0.001))
        let now = elapsedTime

        // Detect rising edge on any of the three pulse signals.
        let beatValue = max(beatBass, max(beatMid, beatComposite))
        let onsetDetected = beatValue > 0.5 && prevBeatValue <= 0.5
        prevBeatValue = beatValue

        if onsetDetected {
            if lastBeatTime >= 0 {
                let interval = now - lastBeatTime
                // Valid BPM range: 40–300 BPM → period 0.2s–1.5s.
                if interval >= 0.2 && interval <= 1.5 {
                    // IIR period smoother: mostly measured, small prior contribution.
                    estimatedPeriod = 0.3 * estimatedPeriod + 0.7 * interval
                    hasPeriod = true
                    let iStr = String(format: "%.3f", interval)
                    let pStr = String(format: "%.3f", self.estimatedPeriod)
                    logger.debug("BeatPredictor onset: interval=\(iStr)s, period=\(pStr)s")
                }
            }
            lastBeatTime = now
        }

        // No period estimate yet — can't predict.
        guard hasPeriod && lastBeatTime >= 0 else {
            return Result(beatPhase01: 0, beatsUntilNext: 1)
        }

        let elapsed = now - lastBeatTime

        // Tempo lost: no beat for > 3× the estimated period.
        if elapsed > 3.0 * estimatedPeriod {
            return Result(beatPhase01: 0, beatsUntilNext: 1)
        }

        let rawPhase = Float(elapsed / estimatedPeriod)
        let phase = min(rawPhase, 1.0)

        return Result(beatPhase01: phase, beatsUntilNext: max(0, 1.0 - phase))
    }

    // MARK: - Reset

    /// Reset all learned period state.  Call on track change.
    /// Does NOT clear bootstrapBPM — the metadata-derived prior remains valid.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        elapsedTime = 0
        lastBeatTime = -1.0
        hasPeriod = false
        prevBeatValue = 0
        // Re-seed from bootstrap BPM if available.
        if let bpm = _bootstrapBPM, bpm > 0 {
            estimatedPeriod = Double(60.0 / bpm)
            hasPeriod = true
        }
        logger.info("BeatPredictor reset")
    }
}
