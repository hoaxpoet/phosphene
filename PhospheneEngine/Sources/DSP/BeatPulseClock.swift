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
// SLOW PULSE (Matt's direction 2026-06-10, D-154): the pulse period is FOUR
// beats, not one. The Stage-1 live verdict (session 2026-06-10T03-02-32Z)
// showed a per-beat punch from an arbitrary phase reads as a robotic
// metronome ignoring the music — on a streaming playlist, tracks 2+ switch
// mid-audio so the first-note anchor lands on a musically meaningless
// instant. At 4-beat rate (~2 s at 120 BPM) the same phase error reads as a
// gentle oceanic heave at a musical rate rather than a wrong beat claim, and
// sub-1 % tempo error takes 4× longer to smear the phase. A fixed 4 beats is
// used (not the grid's detected meter — meter detection is itself unreliable
// and the pulse does not claim downbeat alignment).
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
        /// Count of completed pulse cycles since the anchor (D-157): seeds the
        /// per-beat spatial punch mask so a different region of the spike
        /// field punches each beat. Monotonic within a track; resets per track.
        public var beatIndex: Float

        public static let zero = Output(phase01: 0, amp01: 0, beatIndex: 0)
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

    /// Pulse period in beats (D-154 slow pulse — see header). One heave per
    /// four beats: phase errors read as swell character, not a wrong beat.
    public static let pulseBeats: Double = 4.0

    // MARK: Handoff to the live beat (FBS.S3 / D-156)

    /// Seconds after the anchor before the pulse may hand off to the live
    /// drift tracker's per-beat phase. Matches the stem/tracker convergence
    /// window (the tracker's correction wanders over the opening — Stage 0).
    static let handoffAfterS: Double = 10.0

    /// Envelope threshold below which a swap is seam-safe. The handoff fires
    /// when BOTH the outgoing and incoming phases have envelope < this — the
    /// visible seam step is bounded by it. NOT a phase-window coincidence:
    /// the bridge and the live phase derive from the same tempo, so their
    /// relative offset is FROZEN — a narrow rest-window coincidence either
    /// fires every cycle or NEVER (Money, session 2026-06-10T17-21-49Z:
    /// zero eligible frames in 63 s — the handoff structurally could not
    /// fire). The bridge's low-envelope span (env < 0.15 ≈ 28 % of its 4-beat
    /// cycle ≈ 1.1 live cycles of time) sweeps MORE than one full live cycle,
    /// so a joint-low frame exists in every bridge cycle, guaranteed.
    static let handoffEnvelopeFloor: Float = 0.15

    /// The punch envelope, CPU-side authority — MUST mirror `fo_spike_strength`
    /// in `FerrofluidOcean.metal` (rise to `attackEnd`, decay to 0.85, rest).
    /// Used by the handoff's seam-safety condition.
    static let attackEnd: Float = 0.20
    static func envelope(_ phase01: Float) -> Float {
        let ph = min(max(phase01, 0), 1)
        let attack = min(max(ph / attackEnd, 0), 1)
        let decay = 1 - min(max((ph - attackEnd) / (0.85 - attackEnd), 0), 1)
        return attack * decay
    }

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

    /// FBS.S3 / D-156 — true once the pulse has handed off to the live
    /// drift-tracker phase (per-beat, "energetic" steady state). Cleared per
    /// track by `resetAnchor()` so every track re-opens on the slow bridge.
    public private(set) var handedOff = false

    /// D-157 — completed-cycle counter for the spatial punch mask. Bridge:
    /// derived from the metronome. Post-handoff: incremented on live-phase
    /// wraps (continuity across the handoff is irrelevant — the mask only
    /// needs to CHANGE each beat). Reset per track.
    private var liveBeatCount: Float = 0
    private var lastLivePhase: Float?

    // MARK: - Init

    public init() {}

    // MARK: - Configuration

    /// Install the pulse tempo from the cached `BeatGrid`'s BPM. Pass nil (or
    /// a non-positive BPM) to silence the pulse (reactive mode / no grid).
    /// The sole tempo authority — called from `MIRPipeline.setBeatGrid`.
    public func setTempo(bpm: Double?) {
        if let bpm, bpm > 0 {
            periodS = (60.0 / bpm) * Self.pulseBeats   // slow pulse (D-154)
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
        handedOff = false
        liveBeatCount = 0
        lastLivePhase = nil
    }

    /// First note = first sustained audible run; the anchor backdates to the
    /// run's first frame (no confirmation latency).
    private func acquireAnchorIfNeeded(audible: Bool, time: Double) {
        guard anchorTime == nil else { return }
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

    // MARK: - Per-frame update

    /// Advance the clock one analysis frame.
    ///
    /// - Parameters:
    ///   - energySum: AGC-normalised `bass + mid + treble` for this frame.
    ///   - time: the pipeline clock (`MIRPipeline.elapsedSeconds`, Double —
    ///     resets to 0 on track change, same clock the anchor lives in).
    ///   - deltaTime: seconds since the previous analysis frame.
    public func update(energySum: Float, time: Double, deltaTime: Float) -> Output {
        update(energySum: energySum, time: time, deltaTime: deltaTime, liveBeatPhase01: nil)
    }

    /// Advance the clock one analysis frame, with the live drift tracker's
    /// per-beat phase available for the FBS.S3 handoff (D-156).
    ///
    /// - Parameter liveBeatPhase01: `FeatureVector.beatPhase01` from
    ///   `LiveBeatDriftTracker` when a grid is installed; nil in reactive
    ///   mode (no handoff — the bridge keeps running).
    public func update(
        energySum: Float,
        time: Double,
        deltaTime: Float,
        liveBeatPhase01: Float?
    ) -> Output {
        let audible = energySum > Self.audibleEnergyFloor
        acquireAnchorIfNeeded(audible: audible, time: time)

        // --- Amplitude gate (music present?) ---
        if audible {
            silentRunS = 0
        } else {
            silentRunS += max(0, deltaTime)
        }
        let ampTarget: Float = (anchorTime != nil && silentRunS < Self.silenceFadeAfterS) ? 1 : 0
        let alpha = min(1, max(0, deltaTime) / Self.ampRampS)
        amp += alpha * (ampTarget - amp)

        // --- Phase ---
        guard let anchor = anchorTime, let period = periodS, time >= anchor else {
            return Output(phase01: 0, amp01: 0, beatIndex: 0)
        }
        let beats = (time - anchor) / period
        let bridgePhase = Float(beats - beats.rounded(.down))
        // D-157 — live-wrap counter (used post-handoff; cheap to track always).
        if let live = liveBeatPhase01 {
            if let last = lastLivePhase, live < last - 0.3 { liveBeatCount += 1 }
            lastLivePhase = live
        }

        // FBS.S3 / D-156 — handoff to the live beat. After the convergence
        // window, swap the phase source from the slow bridge metronome to the
        // drift tracker's per-beat phase — but ONLY at a frame where BOTH
        // phases sit in the envelope's rest window, so the punch envelope is
        // zero on each side of the swap and the seam is invisible by
        // construction. Once handed off, the pulse follows the live beat for
        // the rest of the track (its small continuous corrections read as
        // timing breath at punch rate, not stutter; gross corrections happen
        // in the opening, which the bridge covers).
        if !handedOff,
           let live = liveBeatPhase01,
           time - anchor >= Self.handoffAfterS,
           Self.envelope(bridgePhase) < Self.handoffEnvelopeFloor,
           Self.envelope(live) < Self.handoffEnvelopeFloor {
            handedOff = true
        }
        if handedOff {
            // Live phase gone (grid cleared mid-track) → fall back to the
            // bridge metronome rather than going dark.
            if let live = liveBeatPhase01 {
                return Output(phase01: live, amp01: amp, beatIndex: liveBeatCount)
            }
        }
        return Output(
            phase01: bridgePhase,
            amp01: amp,
            beatIndex: Float(beats.rounded(.down)))
    }
}
