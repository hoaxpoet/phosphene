// MelodicNoteGate — FTR.6: one tip per note of music.
//
// WHY THIS IS ENGINE-SIDE AND NOT A SHADER COEFFICIENT (measured, FTR.5-prep).
// Matt, after DYN.1c: *"The tips are too active. If possible, I would want only one tip
// per note of music."* Two numbers define the gap on his capture `2026-08-07T18-53-30Z`:
// the tips fire **7.62/s** with a mean jump of **4.6 branches**, against a measured guitar
// note rate of **3.29/s**. Sweeping the shader's quantisation coefficient fixes the second
// number (26 → 6 takes it from 4.54 to 1.00 branches per change) but not the first: the
// rate plateaus at ~6.5/s and then collapses to 0, because `beat_mid` itself turns 6.9
// times a second. A stateless shader cannot impose a minimum inter-event interval — it has
// no memory of when the last event was. The state belongs here.
//
// WHAT THIS IS. A level trigger on `beat_mid` with a refractory period of one eighth note,
// feeding a unit accumulator: each surviving event adds exactly ONE branch, and the count
// drains continuously back toward the rest tree. The eighth note is the shortest interval
// a note can plausibly occupy at the track's own tempo, so the ceiling scales with the
// music rather than being a constant in frames.
//
// THE COST OF "ONE TIP PER NOTE", measured and worth knowing before reading the report. A
// tip that appears must also disappear, and both are visible changes in the branch count.
// At any equilibrium the drain removes tips at exactly the rate the gate adds them, so the
// COUNT changes about twice per note event — ~5.8 transitions/s against 2.9 events/s. That
// is arithmetic, not a tuning miss: reaching 3 transitions/s would mean 1.5 events/s, i.e.
// half the notes. What this increment removes is the SIZE of each change (4.6 branches →
// 1). Decoupling the two would require tips to have identity — rotating WHICH branches are
// lit at a constant count — which the shader's count-threshold tiering cannot express.
//
// KNOWN LIMIT, STATED RATHER THAN IMPLIED. This fixes RATE and GRANULARITY. It does not fix
// instrument separation — Matt's *"heavily favors the drums vs. guitars"* survives it. The
// trigger stays mid-band, and mid band in a rock mix is snare AND guitar (they correlate
// **+0.973** on this material). Per-note guitar events were measured against three candidate
// detectors and none supports them: distortion adds harmonics rather than amplitude, so a
// note inside a sustained chord wall often has no detectable attack (see ENGINEERING_PLAN
// §MEL.1 — grid coherence 31 % for guitar against 41 % for the drums control). **Do not
// re-attempt per-note guitar events on distorted-guitar material without a changed premise.**

import Foundation

// MARK: - MelodicNoteGate

/// Converts the 6.9/s `beat_mid` pulse into a ~3/s note-event stream, and accumulates
/// those events into a branch count that moves one branch at a time.
///
/// Stateful by necessity: the refractory interval is the whole mechanism, and it cannot
/// exist without memory of the last event. Reset per track by `MIRPipeline.reset()`.
public struct MelodicNoteGate: Sendable {

    // MARK: Tuning

    /// Trigger level on `beat_mid`. Swept against both Siamese Dream sources
    /// (`MelodicNoteGateReportTests`), and the sweep is the reason this is not a round
    /// number. `beat_mid` is a pulse that clips at exactly 1.0, so every level in
    /// (0.75, 1.0] selects the same set of full-strength beats — 0.90 sits mid-plateau
    /// and is robust in both directions. Below the plateau the gate stops choosing:
    ///
    /// | level | events/s | duty | fired the instant the refractory expired |
    /// |---|---|---|---|
    /// | 0.25 | 4.19 | 0.61 | **90 %** |
    /// | 0.55 | 3.94 | 0.30 | 77 % |
    /// | 0.75 | 3.66 | 0.20 | 66 % |
    /// | **0.90** | **2.92** | **0.10** | **29 %** |
    ///
    /// At 0.25 the music is above the line 61 % of the time and 90 % of events fire on the
    /// first frame the clock allows — the refractory, not the music, is setting the rate,
    /// and the result is a metronome that ticks whether or not a note was played. At 0.90
    /// the music chooses 71 % of the moments and the rate lands on the measured guitar note
    /// rate of 3.29/s without being clamped to it.
    public static let triggerLevel: Float = 0.90

    /// Drain time constant, seconds — how long a tip lingers after the note that made it.
    ///
    /// Equilibrium count ≈ event rate × τ, so this sets the canopy's resting density and
    /// NOT its activity: the drain removes tips at whatever rate the gate adds them, so τ
    /// moves the level without moving the change rate. Two constraints pin it, and they
    /// pull opposite ways.
    ///
    /// UPWARD, from the preset. The tips only read as a layer once the count crosses the
    /// depth-5 threshold at 31 branches and keeps crossing back. Measured on the
    /// `route_coverage` fixture through the real render harness: τ 1.0 put depth-5 on
    /// **0 %** of frames (the tier never appeared at all — Matt's *"I never see beyond
    /// three levels"*), τ 2.0 on 6 % with 0.50 crossings/s, τ 2.5 on **39 % with 1.36
    /// crossings/s**.
    ///
    /// DOWNWARD, from saturation. A route pinned near its ceiling expresses nothing —
    /// the FTR.2 "pinned at 63 on 1.24 % of frames" defect in a smaller register. At τ 2.5
    /// the two Siamese Dream sources measure 7.3 and 7.1 of 12, i.e. **60 %**, with room
    /// above for a dense passage.
    public static let drainTau: Float = 2.5

    /// Ceiling on accumulated tips. Raised 8 → 12 with `drainTau`: at τ 2.5 the mean sits
    /// near 7, and a ceiling of 8 would have clipped every busy passage flat — the
    /// "canopy must not flat-top" anti-reference in the fractal_tree README. The full
    /// canopy budget is unaffected: FTR.2 measured a real-world maximum of 48 of the
    /// available 63 branches, so four more tips do not approach the clamp.
    public static let maxTips: Float = 12

    /// Refractory bounds, seconds. Clamps the derived eighth note to a musically sane
    /// window so a bad tempo estimate cannot open the gate to every frame (0.15 s ≈ 200 BPM
    /// eighths) or close it for most of a bar (0.50 s ≈ 60 BPM eighths).
    public static let refractoryBounds: ClosedRange<Float> = 0.15...0.50

    /// Refractory used when no tempo is available yet (cold start, low-confidence
    /// estimate): the eighth note at 120 BPM.
    public static let defaultRefractory: Float = 0.25

    // MARK: State

    private var secondsSinceEvent: Float = .greatestFiniteMagnitude
    private var tips: Float = 0

    public init() {}

    // MARK: Update

    /// Advance one analysis frame.
    ///
    /// - Parameters:
    ///   - beatMid: `BeatDetector.Result.beatMid`, the mid-register beat pulse.
    ///   - bpm: Stable BPM if one is established, else 0 → `defaultRefractory`.
    ///   - deltaTime: Seconds since the previous frame.
    /// - Returns: Accumulated tip count, 0…`maxTips`. Integer-truncated by the shader, so
    ///   it steps by one branch in both directions.
    public mutating func update(beatMid: Float, bpm: Float, deltaTime: Float) -> Float {
        let dt = max(deltaTime, 0)
        secondsSinceEvent = min(secondsSinceEvent + dt, .greatestFiniteMagnitude / 2)

        // Continuous drain. Runs before the trigger so a firing frame lands on a freshly
        // decayed count rather than compounding with its own event.
        if dt > 0 {
            tips *= exp(-dt / Self.drainTau)
        }

        let refractory = bpm > 0
            ? min(max(30 / bpm, Self.refractoryBounds.lowerBound), Self.refractoryBounds.upperBound)
            : Self.defaultRefractory

        if beatMid >= Self.triggerLevel && secondsSinceEvent >= refractory {
            tips = min(tips + 1, Self.maxTips)
            secondsSinceEvent = 0
        }

        return tips
    }

    /// Track change: no carried-over notes, no carried-over refractory.
    public mutating func reset() {
        secondsSinceEvent = .greatestFiniteMagnitude
        tips = 0
    }
}
