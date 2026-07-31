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

    /// WL.3 SPIKE — which geometric property the harmonic phase drives.
    ///
    /// WL.2 measured the shipped `.turnRate` model producing an ARC, not a figure, on all
    /// three fixtures, and proved it gain-proof (k = 1.1 / 2.6 / 5.0 render identically).
    /// The diagnosis: `θ̇ = k·φ̄̇` integrates to `θ ≈ k·φ̄`, so a BOUNDED, mean-reverting
    /// circular phase is being fed into an UNBOUNDED geometric property (heading). Heading
    /// then hovers near a constant and the pen goes straight. Any fix has to stop doing that.
    public enum SteerMode: Sendable {
        /// WL.2 shipped model — harmony sets the RATE of turning (WITCHLIGHT_DESIGN §3.1(b)).
        case turnRate
        /// Harmony sets the CURVATURE directly: `θ̇ = clamp(c · φ̄, ±ω_max)`. Now a bounded
        /// driver maps to a bounded property. Sitting on one chord draws a circular arc of a
        /// radius that chord chose; a chord change switches to a different radius, so the
        /// figure is a chain of arcs — lobes — and the shape of each lobe encodes the harmony
        /// that drew it. The Dubins clamp still holds the ball-of-yarn floor.
        case curvature
        /// Harmony sets the curvature as a DEVIATION from the track's own tonal home:
        /// `θ̇ = clamp(c · wrap(φ̄ − home), ±ω_max)`, where `home` is a long-τ circular mean
        /// of φ̄. Sitting in the home key draws a straight run; leaving it bends the stroke;
        /// coming back straightens it again. This is the only one of the three whose driver
        /// is not near-constant within a track — φ̄ has HIGH travel but near-zero net
        /// (circular R 0.24–0.78), so its excursions carry the information and its absolute
        /// value carries almost none. Deviation semantics (D-026) applied to a circular
        /// quantity, which is what the other two modes were missing.
        case curvatureDeviation
    }
    public var steerMode: SteerMode = .turnRate

    /// `k` in `θ̇ = clamp(k · φ̄̇, ±ω_max)`. Measured against the four §2 captures — see
    /// the clamp-fraction instrumentation below, which WL.2's closeout reports.
    public var steerGain: Float = 1.10

    /// `c` in `θ̇ = clamp(c · φ̄, ±ω_max)` for `.curvature`. φ̄ spans ±π, so c ≈ ω_max/π
    /// puts the clamp at the extremes of the circle of fifths and leaves the interior free.
    public var curvatureGain: Float = 0.20

    /// Time constant of the circular running mean that defines "home" for
    /// `.curvatureDeviation`, seconds. Long enough to read as the track's tonal centre
    /// rather than as the current chord.
    public var homeTau: Float = 12.0

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
