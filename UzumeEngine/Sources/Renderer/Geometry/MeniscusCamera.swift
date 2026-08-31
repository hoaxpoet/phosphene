// MeniscusCamera — the source's camera, ported as behaviour (MEN.2b).
//
// Split out of `MeniscusSurface` because it IS the source's own subsystem, and because
// the oracle showed it carrying more of the preset's character than the water does: in
// four seconds the plate rotates through most of a turn on three axes while the distance
// oscillation sweeps it from a small floating rhombus to frame-filling and back
// (`MENISCUS_PLAN.md` §9, correction 3). MEN.2a's bounded single-axis wobble was an
// invention standing in for this.
//
// PORTED AS BEHAVIOUR, NOT TRANSCRIBED (D-116 bullet 1). Nothing here is copied from the
// source; the mechanisms below are written from the decoded description.
//
// THE ONE DELIBERATE DEVIATION is the beat source, and it is mandatory compliance rather
// than a claimed divergence (`MENISCUS_PLAN.md` §5). The source tests `bass+mid+treb`
// against a slow running average — an absolute ratio on AGC-normalised energy, which is
// exactly FA #31 / D-026. Phosphene drives the same behaviour from deviation primitives.

import Foundation
import Shared

// MARK: - MeniscusCamera

/// Three Euler angles integrating from velocities re-randomised on the BAR LINE, plus an
/// arousal-driven dolly (§5's routing table). Deterministic: a track renders the same twice.
struct MeniscusCamera {

    /// The three Euler angles the projection consumes.
    private(set) var angles = SIMD3<Float>(0.35, 0.62, 0)
    /// Smoothed volume — drives the global brightness gate and the re-aim snappiness.
    private(set) var volumeEnvelope: Float = 0

    private var angularVelocity = SIMD3<Float>(0.10, 0.14, 0.05)
    private var smoothedVelocity = SIMD3<Float>(0.10, 0.14, 0.05)
    /// Mood arousal, smoothed onto §5's ~20–40 s timescale.
    private var arousalEnvelope: Float = 0
    /// Previous bar phase, for downbeat detection.
    private var previousBarPhase: Float = 0
    private var sinceDownbeat: Float = 99
    private var beatEnvelope: Float = 0
    private var previousBeatEnvelope: Float = 0
    private var refractory: Float = 0
    /// Counts RE-AIM EVENTS, not beats — the three axis cadences (%4, %4, %6) are
    /// meant to index successive re-aims, so mixing beat and downbeat increments
    /// would desynchronise them from the events they gate.
    private var reaimIndex = 0
    private var rng: UInt64 = 0x9E37_79B9_7F4A_7C15

    /// The hue arc the oracle actually traverses — measured 176° teal → 305° magenta,
    /// in turns. An unconstrained map walks into yellows and greens the source never
    /// shows; the first port did exactly that and rendered olive.
    private static let hueTealTurns: Float = 176.0 / 360.0
    private static let hueMagentaTurns: Float = 305.0 / 360.0

    // MARK: - Per frame

    mutating func advance(features: FeatureVector, dt: Float, configuration: MeniscusConfiguration) {
        // Beat edge from deviation, with a refractory window (the source uses ~200 ms).
        let drive = max(features.bassDev, features.beatComposite)
        beatEnvelope += (drive > beatEnvelope ? dt / (0.010 + dt) : dt / (0.16 + dt))
            * (drive - beatEnvelope)
        refractory = max(0, refractory - dt)
        var beatFired = false
        if beatEnvelope > 0.55 && previousBeatEnvelope <= 0.55 && refractory <= 0 {
            beatFired = true
            refractory = 0.20
        }
        previousBeatEnvelope = beatEnvelope

        // RE-AIM ON THE BAR LINE, not the beat — §5's table, and FA #67 now REQUIRES it.
        // Once drops fire on per-stem onsets, a camera re-aiming on its own beat detector
        // puts two visual layers on one primitive at one timescale, which is the failure
        // the rule exists to catch (Ferrofluid rounds 56–65). Bar phase is a different
        // timescale AND comes from the cached grid, so it is also steadier than the live
        // detector it replaces. D-157: bounded angular step, luminance unaffected.
        let barPhase = features.barPhase01
        let downbeat = previousBarPhase > 0.75 && barPhase < 0.25
        previousBarPhase = barPhase
        sinceDownbeat = downbeat ? 0 : sinceDownbeat + dt
        // No grid ⇒ barPhase01 is pinned at 0 and never wraps; fall back to the live
        // detector rather than freezing the camera.
        let barsLive = sinceDownbeat < 8.0
        let reaim = barsLive ? downbeat : beatFired
        if reaim {
            reaimIndex &+= 1
            if reaimIndex % 4 == 0 { angularVelocity.x = nextVelocity(configuration.tumbleRate) }
            if reaimIndex % 4 == 2 { angularVelocity.y = nextVelocity(configuration.tumbleRate) }
            if reaimIndex % 6 == 2 { angularVelocity.z = nextVelocity(configuration.tumbleRate) }
        }

        // Loud music → less smoothing → snappier re-aim.
        let volume = min(max((features.bass + features.mid + features.treble) / 3, 0), 1.5)
        volumeEnvelope += (volume - volumeEnvelope) * (1 - exp(-dt / 0.35))
        let tau = max(configuration.cameraTau * (1.4 - 0.6 * volume), 0.02)
        smoothedVelocity += (angularVelocity - smoothedVelocity) * (1 - exp(-dt / tau))
        angles += smoothedVelocity * dt

        // DOLLY FROM MOOD AROUSAL — §5's table, replacing the source's free sine.
        //
        // The sine was ported faithfully at MEN.2b and Matt's live read was that the
        // in/out reads as unmotivated, which it is: nothing about it responded to audio.
        // §5 is explicit that this must NOT be a slower smoothing of loudness — that
        // would be two visual layers on one primitive (FA #67), and the surface amplitude
        // already carries loudness. Arousal is a genuinely independent wide-window signal,
        // and AV.7 / D-185 found mood envelopes are the right driver where deviation
        // primitives measure too spiky.
        // BUG-094: was `max(0, min(features.arousal, 1))`, which clamped a −1…+1 primitive
        // and pinned the dolly at the hero distance for every calm passage.
        arousalEnvelope += (features.arousal01 - arousalEnvelope)
            * (1 - exp(-dt / max(configuration.dollyTau, 0.1)))
    }

    mutating func reset() { self = MeniscusCamera() }

    // MARK: - Derived

    /// Camera distance this frame.
    /// Low arousal → close → the OPEN RASTER hero register; high arousal → back → the
    /// dense sheet excursion. The direction matters at cold start: §5 notes arousal is
    /// EMA-attenuated there, so starting from 0 puts the dolly at the hero distance and
    /// it moves outward, never the reverse.
    func distance(configuration: MeniscusConfiguration) -> Float {
        configuration.camDistCentre
            + configuration.camDistSwing * (2 * arousalEnvelope - 1)
    }

    /// Diagnostic: the smoothed arousal the dolly is riding.
    var dollyArousal: Float { arousalEnvelope }

    /// Sky/glare hue, in turns, derived from the camera attitude.
    ///
    /// This is the §9 correction 1: the source tints its wash from the Euler angles, and
    /// because the angles integrate continuously the tint NEVER SETTLES — measured off
    /// the oracle it sweeps ~40°/s. A still frame structurally cannot show this, which is
    /// why seven curated stills recorded a fixed "white-on-teal palette" that does not
    /// exist. There is no palette to choose at MEN.3; there is a rotation to reproduce.
    var hueTurns: Float {
        let sweep = 0.5 + 0.5 * sin(angles.x * 0.62 + angles.y * 0.41 + angles.z * 0.27)
        return Self.hueTealTurns + (Self.hueMagentaTurns - Self.hueTealTurns) * sweep
    }

    /// Global brightness gate driven by volume, as the source does — which is also why
    /// the oracle renders near-black at silence (anti-reference `06`). Floored, never
    /// zeroed: D-037 is the one place Meniscus must not follow the source, and §4 allows
    /// exactly the minimum that rule requires.
    var brightness: Float { max(0.16, min(1.0, 0.25 + 1.15 * volumeEnvelope)) }

    // MARK: - Helpers

    /// Deterministic LCG — never `Float.random`, which would make the harness unrepeatable.
    private mutating func nextVelocity(_ rate: Float) -> Float {
        rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let unit = Float((rng >> 33) & 0xFF_FFFF) / Float(0xFF_FFFF)
        return (unit * 2 - 1) * rate
    }
}
