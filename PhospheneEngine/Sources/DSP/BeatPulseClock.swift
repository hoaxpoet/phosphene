// BeatPulseClock — FBS Stage 1: the steady, first-note-anchored, tempo-locked
// beat pulse (D-153).
//
// Produces the `pulsePhase01` / `pulseAmp01` FeatureVector fields that drive
// Ferrofluid Ocean's per-beat spike punch. Design contract (FBS kickoff +
// Stage 0 findings, docs/diagnostics/FBS_STAGE0_FINDINGS_2026-06-09.md):
//
//  1. ANCHOR = the first NOTE (silence → sustained sound), not the first
//     strong hit. Music starts on the "one"; the silence→signal transition is
//     the cleanest event in the take to detect, and unlike a strength
//     threshold it is not fooled by a quiet/building intro (Matt's
//     correction, 2026-06-09, verified: a first-note-anchored pulse lands
//     within ~28 ms of the beat on the measured catalog, beating the cached
//     grid's cross-capture-unstable phase at +60…+240 ms).
//  2. TEMPO = the pre-analysed cached BeatGrid BPM (Stage 0: reliable to
//     ~1 % and reproducible across captures — the one trustworthy part of
//     the grid).
//  3. DEAD STEADY — phase is `frac((t − anchor) / period)` and is NEVER
//     corrected afterwards. Explicitly does NOT consume
//     `LiveBeatDriftTracker` (its correction wanders 50–90 ms over the
//     opening — Stage 0; chasing it reads as the visual "searching").
//     A steady pulse that is wrong-by-a-hair beats a wandering pulse that is
//     right-on-average. Stage 3 may add a bar-boundary handoff; Stage 1
//     must not.
//
// Amplitude (`amp01`) is a music-present gate only in Stage 1: 0 before the
// anchor, 1 while audio flows, fading to 0 across sustained silence (an
// inter-track gap or a stop — NOT a between-beat dip) so the pulse never
// punches into a silent room. Stage 2 will modulate it by live energy.
//
// Deterministic: outputs are a pure function of the input series. No locks —
// all access happens on MIRPipeline's processing path plus its existing
// app-layer call sites, mirroring `BandDeviationTracker` / `BeatPredictor`.

import Foundation

// MARK: - BeatPulseClock

/// Steady first-note-anchored beat pulse generator (FBS Stage 1, D-153).
public final class BeatPulseClock: @unchecked Sendable {

    // MARK: - Output

    /// Per-frame pulse state, written into `FeatureVector` floats 40–41.
    public struct Output: Sendable, Equatable {
        /// Beat-cycle phase: 0 at each pulse beat, rising linearly to 1 at the
        /// next. 0 before the anchor exists.
        public var phase01: Float
        /// Pulse gate: 0 before the first note / across sustained silence,
        /// 1 while music plays (smooth ~250 ms ramps between).
        public var amp01: Float

        public static let zero = Output(phase01: 0, amp01: 0)
    }

    // MARK: - Tuning constants

    /// AGC-normalised `bass + mid + treble` below this is silence. Matches the
    /// empirical floor used by the AGC3 / FBS session-measurement tools (true
    /// silence logs 0.000xx; the first audible frame jumps to ≥ 0.1).
    public static let audibleEnergyFloor: Float = 0.02

    /// Consecutive audible frames required before the anchor latches. Rejects
    /// a single spurious frame (pop, UI-sound bleed); the anchor backdates to
    /// the FIRST frame of the run, so confirmation adds no anchor latency.
    static let anchorConfirmFrames = 3

    /// Sustained near-silence (seconds) before `amp01` fades out. An
    /// inter-track gap / stop, not a between-beat dip — mirrors the D-148
    /// "sustained" gate rationale in `BandEnergyProcessor`.
    static let silenceFadeAfterS: Float = 0.5

    /// `amp01` ramp time constant (seconds), both directions.
    static let ampRampS: Float = 0.25

    // MARK: - State

    /// Beat period in seconds. nil = no usable tempo → pulse stays silent.
    private var periodS: Double?

    /// Anchor instant (in the caller's `time` clock). nil until the first
    /// note has been confirmed.
    private var anchorTime: Double?

    /// First frame time of the current candidate audible run (pre-anchor).
    private var pendingAnchorTime: Double?
    /// Length of the current candidate audible run (pre-anchor).
    private var audibleRunFrames = 0

    /// Seconds of continuous near-silence (post-anchor, drives the amp gate).
    private var silentRunS: Float = 0
    /// Smoothed amplitude gate.
    private var amp: Float = 0

    // MARK: - Init

    public init() {}

    // MARK: - Configuration

    /// Install the pulse tempo from the cached `BeatGrid`'s BPM. Pass nil (or
    /// a non-positive BPM) to silence the pulse (reactive mode / no grid).
    /// The sole tempo authority — called from `MIRPipeline.setBeatGrid`.
    public func setTempo(bpm: Double?) {
        if let bpm, bpm > 0 {
            periodS = 60.0 / bpm
        } else {
            periodS = nil
        }
    }

    /// Clear the anchor and amplitude state for a new track (called from
    /// `MIRPipeline.reset()`). Keeps the tempo — `setTempo` is the sole tempo
    /// authority, and track-change call order between `reset()` and the grid
    /// install differs across the LF / streaming paths.
    public func resetAnchor() {
        anchorTime = nil
        pendingAnchorTime = nil
        audibleRunFrames = 0
        silentRunS = 0
        amp = 0
    }

    // MARK: - Per-frame update

    /// Advance the clock one analysis frame.
    ///
    /// - Parameters:
    ///   - energySum: AGC-normalised `bass + mid + treble` for this frame.
    ///   - time: the pipeline clock (`MIRPipeline.elapsedSeconds`, Double —
    ///     resets to 0 on track change, same clock the anchor lives in).
    ///   - deltaTime: seconds since the previous analysis frame.
    public func update(energySum: Float, time: Double, deltaTime: Float) -> Output {
        let audible = energySum > Self.audibleEnergyFloor

        // --- Anchor acquisition (first note = first sustained audible run) ---
        if anchorTime == nil {
            if audible {
                if pendingAnchorTime == nil {
                    pendingAnchorTime = time
                    audibleRunFrames = 1
                } else {
                    audibleRunFrames += 1
                }
                if audibleRunFrames >= Self.anchorConfirmFrames {
                    anchorTime = pendingAnchorTime   // backdate to the run's first frame
                }
            } else {
                pendingAnchorTime = nil
                audibleRunFrames = 0
            }
        }

        // --- Amplitude gate (music present?) ---
        if audible {
            silentRunS = 0
        } else {
            silentRunS += max(0, deltaTime)
        }
        let ampTarget: Float = (anchorTime != nil && silentRunS < Self.silenceFadeAfterS) ? 1 : 0
        let alpha = min(1, max(0, deltaTime) / Self.ampRampS)
        amp += alpha * (ampTarget - amp)

        // --- Phase: pure metronome, never corrected ---
        guard let anchor = anchorTime, let period = periodS, time >= anchor else {
            return Output(phase01: 0, amp01: 0)
        }
        let beats = (time - anchor) / period
        let phase = Float(beats - beats.rounded(.down))
        return Output(phase01: phase, amp01: amp)
    }
}
