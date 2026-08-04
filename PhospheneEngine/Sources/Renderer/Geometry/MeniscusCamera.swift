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

/// Three Euler angles integrating from re-randomised velocities, plus a free distance
/// oscillation. Deterministic: a given track renders identically twice.
struct MeniscusCamera {

    /// The three Euler angles the projection consumes.
    private(set) var angles = SIMD3<Float>(0.35, 0.62, 0)
    /// Smoothed volume — drives the global brightness gate and the re-aim snappiness.
    private(set) var volumeEnvelope: Float = 0

    private var angularVelocity = SIMD3<Float>(0.10, 0.14, 0.05)
    private var smoothedVelocity = SIMD3<Float>(0.10, 0.14, 0.05)
    private var dollyPhase: Float = 0
    private var beatEnvelope: Float = 0
    private var previousBeatEnvelope: Float = 0
    private var refractory: Float = 0
    private var beatIndex = 0
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
            beatIndex &+= 1
            refractory = 0.20
        }
        previousBeatEnvelope = beatEnvelope

        // Three axes, three cadences — the source re-randomises on beat indices
        // satisfying (i % 4 == 0), (i % 4 == 2) and (i % 6 == 2). Independent periods
        // mean the axes drift in and out of phase rather than locking into a spin.
        if beatFired {
            if beatIndex % 4 == 0 { angularVelocity.x = nextVelocity(configuration.tumbleRate) }
            if beatIndex % 4 == 2 { angularVelocity.y = nextVelocity(configuration.tumbleRate) }
            if beatIndex % 6 == 2 { angularVelocity.z = nextVelocity(configuration.tumbleRate) }
        }

        // Loud music → less smoothing → snappier re-aim.
        let volume = min(max((features.bass + features.mid + features.treble) / 3, 0), 1.5)
        volumeEnvelope += (volume - volumeEnvelope) * (1 - exp(-dt / 0.35))
        let tau = max(configuration.cameraTau * (1.4 - 0.6 * volume), 0.02)
        smoothedVelocity += (angularVelocity - smoothedVelocity) * (1 - exp(-dt / tau))
        angles += smoothedVelocity * dt

        // Distance oscillation — a free slow sine, independent of the tumble.
        dollyPhase += dt * (2 * .pi / max(configuration.dollyPeriod, 0.001))
    }

    mutating func reset() { self = MeniscusCamera() }

    // MARK: - Derived

    /// Camera distance this frame: the resting register swept by the slow sine.
    func distance(configuration: MeniscusConfiguration) -> Float {
        configuration.camDistCentre + configuration.camDistSwing * sin(dollyPhase)
    }

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
