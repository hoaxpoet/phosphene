// WitchlightBead / WitchlightTuning — Witchlight's data types and its numeric constants.
//
// Split out of `WitchlightPath.swift` so the model file stays inside the 400-line lint
// budget and so a tuning change is a diff nobody has to read the integrator to review.

import Foundation

// MARK: - WitchlightBead

/// One deposited point on the ribbon. Mirrors MSL `WLBead` field-for-field — scalar
/// floats only, so the 32-byte layout matches without alignment surprises.
@frozen
public struct WitchlightBead: Sendable, Equatable {
    public var posX: Float = 0
    public var posY: Float = 0
    public var posZ: Float = 0
    /// Seconds since emission. Drives brightness, radius and expiry.
    public var age: Float = 0
    public var colR: Float = 0
    public var colG: Float = 0
    public var colB: Float = 0
    /// 1 when this bead was laid down on a bar downbeat — permanently set, never decays back.
    public var promoted: Float = 0

    public init() {}
}

// MARK: - WitchlightTuning

/// The numeric constants of the motion model. Grouped so `WitchlightPathTests` can drive
/// degenerate variants (zero relaxation, zero steer) without touching production values.
public struct WitchlightTuning: Sendable {

    /// Visible age window. The 30 s contract: what hangs in the dark IS the last 30 s of
    /// harmonic motion (WITCHLIGHT_DESIGN §3.3).
    public var trailSeconds: Float = 30

    /// Beads per second, at a fixed TIME rate rather than a fixed arc length — so bead
    /// spacing encodes pen speed (`05`, `02`: density varies along the stroke).
    public var emissionHz: Float = 34

    /// Base pen speed in world units/second. World units: the frame is 2.0 tall.
    public var baseSpeed: Float = 0.10

    /// Minimum turning radius, world units. 0.16 = 8 % of frame height (§3.1(b)).
    public var minTurnRadius: Float = 0.16

    /// `k` in `θ̇ = clamp(k · φ̄̇, ±ω_max)`. Measured against the four §2 captures — see
    /// the clamp-fraction instrumentation below, which WL.2's closeout reports.
    public var steerGain: Float = 1.10

    /// Circular-EMA time constant on the harmonic phase, seconds (CR.1.2 settled on 1.5 s).
    public var phaseTau: Float = 1.5

    /// Laplacian smoothing strength, per SECOND (not per frame).
    ///
    /// Per-frame was both frame-rate-dependent and far too strong: λ = 0.30 applied every
    /// frame across the ~2.5 s mutable window is ~100 smoothing passes, and plain λ-only
    /// Laplacian smoothing SHRINKS — measured, it flattened a 2-circle heading sweep into a
    /// visually straight stroke. (That is the shrinkage Taubin's λ|μ scheme exists to fix;
    /// the cheaper fix here is to make the total mild, since a bounded-curvature pen path is
    /// already smooth and the relaxation is only removing the emission-quantisation kink.)
    public var relaxLambda: Float = 1.2
    /// Beads younger than this relax at full weight.
    public var relaxFullAge: Float = 1.0
    /// Relaxation weight reaches zero here; beyond, the record is frozen.
    public var relaxZeroAge: Float = 4.0

    /// Speed modulation depth from arousal. Deliberately narrow — speed is what turns
    /// `01` into `10`, so it gets the least dynamic range of any driver.
    public var speedModDepth: Float = 0.25

    /// Head-flare refractory, seconds (§5: ≥ 900 ms, ≈ 1.1 flares/s ceiling).
    public var flareRefractory: Float = 0.90
    /// Flare rise/fall time constants. 2.2τ ≈ 10–90 % time: 66 ms rise, 286 ms fall,
    /// against the §5 minima of 60 ms and 200 ms.
    public var flareRiseTau: Float = 0.030
    public var flareFallTau: Float = 0.130
    /// Peak flare amplitude. Bounded here rather than in the shader's extent so the
    /// §5 luminance ceiling is a CPU-side invariant.
    public var flareCeiling: Float = 0.80

    /// How long a reversal must persist to count as a turn (§2's own "turn" definition).
    public var turnConfirmSeconds: Float = 0.25
    /// Hue step applied at a confirmed turn, so a turn reads as a colour boundary.
    public var turnHueStep: Float = 0.13

    /// Target RMS radius of the figure, world units — the auto-fit setpoint.
    public var framedRadius: Float = 0.62

    public init() {}
}
