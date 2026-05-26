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
//   1. Detect rising edge on sub_bass raw onset boolean (BeatDetector.Result.onsets[0]).
//      Grouped `beatBass` pulse (sub_bass OR low_bass) is NOT used for period
//      estimation: on tracks like Love Rehab the low_bass synthesiser fires at
//      ~417 ms (just over the 400 ms per-band cooldown) while the kick lives at
//      480 ms (125 BPM).  sub_bass alone sees only the kick.  D-075 principle.
//   2. stableBPM (BeatDetector trimmed-mean IOI, also sub_bass-only) is blended
//      per-frame to keep the period anchored on tracks where sub_bass onsets are
//      sparse or delayed.
//   3. On sub_bass onset: if a valid inter-beat interval (0.3s–1.5s) was measured,
//      update the IIR period: period = 0.3 × period + 0.7 × interval.
//      Floor of 0.3s (200 BPM max) prevents note articulations from polluting.
//   4. Each frame: phase = (now − lastBeatTime) / estimatedPeriod, clamped 0–1.
//   5. If no beat for > 3 × estimatedPeriod: phase resets to 0 (tempo lost).
//   6. Bootstrap: `bootstrapBPM` seeds the period estimate so that once the
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
///
/// > Deprecated for tracks with cached `BeatGrid` analysis (DSP.2 S7, 2026-05-04).
/// > Tracks where `MIRPipeline.setBeatGrid(_:)` has been called with a non-empty
/// > grid drive `FeatureVector.beatPhase01` / `beatsUntilNext` from
/// > `LiveBeatDriftTracker` instead. This class remains the load-bearing
/// > fallback for **reactive mode** — ad-hoc playback, preview-unavailable
/// > tracks, or any path where Beat This! offline analysis did not run. New
/// > shader code should not assume this is the active source of phase.
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
    ///   - subBassOnset: Raw sub_bass onset flag from `BeatDetector.Result.onsets[0]`.
    ///     Fires at most once per 400 ms cooldown.  Used for rising-edge phase anchor
    ///     and IOI period measurement (D-075: sub_bass only, never fused with low_bass).
    ///   - beatMid: Mid beat pulse (unused for estimation, retained for API compat).
    ///   - beatComposite: Composite beat pulse (unused for estimation, retained).
    ///   - stableBPM: Trimmed-mean BPM from `BeatDetector.stableBPM` (0 = unavailable).
    ///     Blended per-frame to keep the period anchored while live IOIs are sparse.
    ///   - time: Current time in seconds (same domain across all calls — e.g.
    ///     MIRPipeline's `elapsedSeconds`).
    ///   - deltaTime: Seconds since the last call.
    /// - Returns: Beat phase prediction for this frame.
    public func update(
        subBassOnset: Bool, beatMid: Float, beatComposite: Float,
        stableBPM: Float = 0,
        time: Float, deltaTime: Float
    ) -> Result {
        lock.lock()
        defer { lock.unlock() }

        // Accumulate elapsed time from deltaTime so timing is correct regardless
        // of what the caller passes for `time` (MIRPipeline passes 0 currently).
        elapsedTime += Double(max(deltaTime, 0.001))
        let now = elapsedTime

        // Anchor period toward BeatDetector's trimmed-mean BPM (sub_bass-only
        // IOI, D-075) when available.  ~5-second time constant at 60 fps so the
        // IIR can still respond to genuine tempo changes.
        if stableBPM > 0 {
            let targetPeriod = Double(60.0 / stableBPM)
            estimatedPeriod = 0.997 * estimatedPeriod + 0.003 * targetPeriod
            hasPeriod = true
        }

        if subBassOnset {
            if lastBeatTime >= 0 {
                let interval = now - lastBeatTime
                // Valid BPM range: 40–200 BPM → period 0.3s–1.5s.
                // Floor 0.3s (200 BPM) prevents bass-guitar articulations from
                // being mistaken for beats (they land at ~0.2–0.25s on Money).
                if interval >= 0.3 && interval <= 1.5 {
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
        // Re-seed from bootstrap BPM if available.
        if let bpm = _bootstrapBPM, bpm > 0 {
            estimatedPeriod = Double(60.0 / bpm)
            hasPeriod = true
        }
        logger.info("BeatPredictor reset")
    }
}
