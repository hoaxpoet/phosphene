// DancePhase — a render-rate phase, locked to an analysis-rate one (FTR.28).
//
// WHY THIS EXISTS, and it is the third time this project has learned the same lesson.
//
// Matt asked for the tree to dance: *"bounces, sways, grows, and recedes with the music in a
// coordinated dance… the broomsticks in Fantasia's The Sorcerer's Apprentice."* A dance is driven
// by a PHASE, not by an amplitude — which is the premise change nine tuning increments never made.
// But `FeatureVector.beatPhase01` is an ANALYSIS-rate signal, and measured on Matt's own capture
// `2026-08-17T20-01-01Z` it updates **14.6 times a second in steps of 0.109 of a beat** — about
// nine discrete jumps per beat, each held for ~4 render frames at 59 Hz. Driving geometry from it
// directly produces a staircase, and the rendered pose's dominant period came back **0.133 s** —
// the update cadence, not the music.
//
// A staircase is exactly what Matt has already rejected twice, in those words: *"dancing the
// robot"* (FTR.13, an ease sized in samples that ran on 2.1 of them) and *"herky-jerky… looks
// defective"* (FTR.24, an accent added downstream of the only render-rate smoothing). The
// instrument caught it a third time before he saw it.
//
// So the dance runs on its own clock: advance locally every RENDER frame at the measured tempo,
// and correct gently toward the analysis phase whenever a fresh one arrives. The correction is
// proportional and wrap-aware, so tracking never reintroduces a step — the same shape as a
// phase-locked loop, and the same reasoning as FTR.14's render-rate glide.

import Foundation
import Shared

// MARK: - DancePhase

/// A 0…1 phase advanced at render rate and phase-locked to an analysis-rate measurement.
public struct DancePhase {

    /// Correction gain per render frame. 0.08 gives a lock time constant of ~0.2 s at 60 fps:
    /// fast enough to follow a tempo change or a grid re-anchor within a beat, slow enough that
    /// a single 0.109 phase step arrives as a ramp rather than a jump. Raising this toward 1.0
    /// reintroduces the staircase this type exists to remove.
    static let lockGain: Float = 0.08

    /// Cycles per beat. 1 for the beat phase; 1/4 for a bar in 4/4 — the caller supplies the
    /// period directly, so nothing here assumes a meter.
    private var phase: Float = 0
    private var seeded = false
    /// The last tempo this clock was given, kept so the dance can carry on through a gap in the
    /// grid's confidence. See `advance` for why that matters more than it sounds.
    private var lastPeriod: Float = 0
    private var secondsSinceMeasurement: Float = 0
    /// ★★★ THE CLOCK ESTIMATES ITS OWN RATE from the phase it is handed, and does NOT depend on
    /// `BeatHold`'s tempo. That dependency is what made the first version fail on real music:
    /// the hold vouches for a tempo on only **13 % of frames** (47/360 on Matt's capture
    /// `2026-08-17T20-01-01Z`), because its trust gate wants eight beat intervals whose spread is
    /// ≤ 20 % of the mean and a 14.6 Hz phase keeps knocking it out of that window. With the
    /// dance gated on that, the lean's correlation with the bar was **+0.293 against a decoy of
    /// +0.285** — no lock at all.
    ///
    /// A phase's own rate of change is all a clock needs, and it needs no confidence gate: the
    /// measured phase advances 1.0 per cycle by definition, so `dφ/dt` IS the frequency. Per
    /// sample it is noisy (the phase arrives in 0.109 steps), so it is smoothed over ~1 s, which
    /// is a fraction of a beat's worth of error and converges within two beats.
    private var lastMeasured: Float?
    private var rateHz: Float = 0
    /// Advance and elapsed time, each smoothed with the SAME time constant, so the rate is their
    /// ratio. See `updateRate` for why a per-frame dφ/dt cannot work here.
    private var advanceEMA: Float = 0
    private var elapsedEMA: Float = 0

    /// How long the dance keeps going on its own after the grid stops vouching for a tempo.
    /// 2.5 s is about a bar at 94 BPM: long enough to ride out the trust flicker measured below,
    /// short enough that a genuinely stopped or changed track does not keep dancing to the old
    /// tempo.
    static let coastSeconds: Float = 2.5

    public init() {}

    /// Advance one render frame and return the smooth phase.
    ///
    /// - Parameters:
    ///   - measured: the analysis-rate phase (0…1), or `nil` when no grid is trusted.
    ///   - periodSeconds: the cycle length. Non-positive disables advancement.
    ///   - deltaTime: the RENDER frame's delta, not the analysis frame's.
    /// - Returns: the locked phase, or 0 when there is nothing to lock to.
    public mutating func advance(measured: Float?, periodSeconds: Float, deltaTime: Float) -> Float {
        // ★★★ COAST THROUGH GAPS IN THE GRID'S CONFIDENCE. Measured on Matt's capture
        // `2026-08-17T20-01-01Z`, `BeatHold` vouches for a tempo on only **47 of 360 frames
        // (13 %)** — and when it does, the tempo is accurate to 1.5 % (0.647 s against the grid's
        // 0.638 s). The trust gate wants eight intervals whose spread is ≤ 20 % of the mean, and a
        // `beatPhase01` sampled at 14.6 Hz keeps knocking it out of that window.
        //
        // A dance that stops whenever confidence blinks is worse than no dance: the tree would
        // stand still for 87 % of frames and lurch on the rest, which is precisely the
        // start-and-stop quality Matt called robotic. So once a tempo has been established the
        // clock keeps turning on the last known one, and only gives up after `coastSeconds`.
        //
        // Before the FIRST tempo, though, it still returns 0 and the tree stands still — that is
        // the cold-start phase contract (an ungated accent fires at the wrong phase), and it is
        // what keeps this safe on D-154 beat-irregular material, where a tempo never arrives.
        updateRate(measured: measured, deltaTime: deltaTime)
        // Prefer the caller's period when it has one (BeatHold's estimate is the more stable
        // number when available), and fall back to the self-measured rate, which is always there.
        let selfPeriod = rateHz > 1e-4 ? 1 / rateHz : 0
        if periodSeconds > 0.05 { lastPeriod = periodSeconds } else if selfPeriod > 0.05 { lastPeriod = selfPeriod }
        let period = periodSeconds > 0.05 ? periodSeconds : lastPeriod
        if measured != nil { secondsSinceMeasurement = 0 } else { secondsSinceMeasurement += deltaTime }
        guard period > 0.05, secondsSinceMeasurement < Self.coastSeconds else {
            seeded = false
            phase = 0
            lastPeriod = 0
            return 0
        }
        guard let measured else {
            // Coasting: no fresh phase to lock to, so just keep turning.
            guard seeded else { return 0 }
            phase += deltaTime / period
            phase -= phase.rounded(.down)
            return phase
        }
        guard seeded else {
            phase = measured           // adopt exactly, no ramp from zero
            seeded = true
            return phase
        }
        phase += deltaTime / period
        // Circular error in −0.5…0.5, so a correction never takes the long way round the cycle.
        var error = measured - phase
        error -= (error / 1.0).rounded()
        phase += Self.lockGain * error
        phase -= phase.rounded(.down)   // wrap into 0…1
        return phase
    }

    /// Track the measured phase's own rate of change, wrap-aware and smoothed.
    ///
    /// ★★★ THE RATE IS A RATIO OF TWO SMOOTHED SUMS, NOT A PER-FRAME dφ/dt, and the difference is
    /// not cosmetic. The measured phase is a STAIRCASE: it changes only on an analysis update —
    /// ~15 times a second, in steps of ~0.109 of a cycle — and holds between them. A per-frame
    /// dφ/dt therefore reads either 0 (most frames, and skipping those biases the average) or
    /// 0.109 / 0.0167 s = **6.5 cycles per second on a 1.57 Hz beat**, four times too fast.
    ///
    /// The consequence was invisible in the dance and fatal downstream. The lock's correction
    /// still pulled the phase onto the beat, so the gait measured fine (in-step r +0.799) — but
    /// the phase free-ran four times too fast between corrections and got yanked back, so it
    /// crossed zero far more often than once per beat. Anything counting those wraps as beats saw
    /// intervals of ~0.15 s, below `BeatHold.periodRange`'s 0.25 s floor, and threw every one
    /// away: the hold reported a tempo on **0 of 3000 frames** on a real capture while engaging
    /// instantly on a synthetic clock. That was mis-filed as BUG-096 against the hold's tolerance.
    ///
    /// Smoothing the advance and the elapsed time with the same τ and dividing gives the honest
    /// average: a frame with no update contributes 0 to the numerator and its dt to the
    /// denominator, which is exactly what a staircase requires.
    private mutating func updateRate(measured: Float?, deltaTime: Float) {
        defer { if measured != nil { lastMeasured = measured } }
        guard deltaTime > 1e-5 else { return }
        var advance: Float = 0
        if let measured, let previous = lastMeasured {
            advance = measured - previous
            if advance < -0.5 { advance += 1 }    // wrapped forward past 1.0
            if advance > 0.5 { advance -= 1 }     // a correction stepped backwards
            if advance < 0 { advance = 0 }        // never let a correction read as negative tempo
        }
        let alpha = 1 - exp(-deltaTime / 1.5)     // τ 1.5 s — ≈ two beats at 94 BPM
        advanceEMA += (advance - advanceEMA) * alpha
        elapsedEMA += (deltaTime - elapsedEMA) * alpha
        guard elapsedEMA > 1e-6 else { return }
        rateHz = advanceEMA / elapsedEMA
    }

    /// Drop the lock — call at a track change so the next track's grid is adopted exactly
    /// instead of being chased from the previous track's position.
    public mutating func reset() {
        seeded = false
        phase = 0
        lastPeriod = 0
        secondsSinceMeasurement = 0
        lastMeasured = nil
        rateHz = 0
    }
}
