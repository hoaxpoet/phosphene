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
    /// SOLVED at WL.2-e, not chosen. Beads must be spaced further apart than they are
    /// wide or they merge into a smear, which is what shipped: at 34 Hz and
    /// `baseRadius` 0.011 the spacing was 0.0029 world units against a 0.022 diameter —
    /// a ratio of 0.13, i.e. each bead overlapped the next seven times over. The trait
    /// that most identifies the source (`01`, `02`: a thread with discrete sparks ON it)
    /// was therefore absent entirely.
    ///
    /// The fix is FEWER beads, not smaller ones: at 34 Hz the spacing is 0.15 % of frame
    /// height, so any radius that keeps a bead visible also guarantees overlap.
    ///
    /// Re-derived at WL.2-f against the SOURCE's ribbon rather than against an abstract
    /// "looks beaded" ratio. The source's beads read ~1-1.5 % of frame height and nearly
    /// touch (spacing/diameter ~1.2), ~100-150 along the visible length. With
    /// `baseRadius` 0.011 (1.1 % of frame height — the source's size, and the value
    /// originally shipped) that solves to
    ///     emissionHz = speed / (1.2 x 2 x 0.011) = 3.79 Hz  ->  114 beads / 30 s trail.
    ///
    /// Note what this corrects: `baseRadius` was never the defect. WL.2-e shrank it to
    /// 0.008 chasing a ratio of 2.0, which traded a smear for a hairline — the ribbon lost
    /// its presence. Only the emission rate was ever wrong, and the 30 s trail was never
    /// the blocker it appeared to be.
    ///
    /// Emission stays a fixed TIME rate (§3.2), so spacing still encodes pen speed; the
    /// thin line pass keeps the thread continuous between beads.
    public var emissionHz: Float = 3.79

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
    /// **ADOPTED (WL.2/WL.3 integration, 2026-07-31).** Two sessions reached
    /// `.curvatureDeviation` independently — this one via a three-model spike, the
    /// parallel WL.2-a branch via a falsification probe — and by the same reasoning:
    /// D-026 deviation semantics applied to a circular quantity. Evidence:
    /// `docs/diagnostics/WL2A_PEN_KINEMATICS_2026-07-31.md` and
    /// `docs/diagnostics/WL2A_HEADING_AB_2026-07-31.md`. `.turnRate` and `.curvature`
    /// are kept runnable so the falsification stays reproducible, not as live options.
    public var steerMode: SteerMode = .curvatureDeviation

    /// Normalise the deviation gain against the track's own excursion scale.
    ///
    /// A FIXED `curvatureGain` assumes every track's excursions from tonal home have a
    /// similar magnitude, and they do not: circular R runs 0.24–0.78 across the §2
    /// captures, so `love_rehab` (R = 0.241, home genuinely ill-defined) produces much
    /// smaller normalised excursions and its figure stayed an arc under a fixed gain —
    /// the open question the WL.3 spike named. Normalising against a running estimate of
    /// |deviation| is the same construction that dissolved the ~10× cross-track rate
    /// spread in §2.3, and it is what D-026 means by reading a driver relatively.
    public var normaliseDeviationGain: Bool = false

    /// `k` in `θ̇ = clamp(k · φ̄̇, ±ω_max)`. Measured against the four §2 captures — see
    /// the clamp-fraction instrumentation below, which WL.2's closeout reports.
    public var steerGain: Float = 1.10

    /// `c` in `θ̇ = clamp(c · φ̄, ±ω_max)` for `.curvature`. φ̄ spans ±π, so c ≈ ω_max/π
    /// puts the clamp at the extremes of the circle of fifths and leaves the interior free.
    /// SOLVED from measurement at QG.5, not chosen. The response is linear in this gain
    /// while the clamp is idle (measured saturation at 0.20 was 0.0-0.2%), so:
    /// 0.20 produced 0.35-0.55 turns/trail across the fixtures, and 2.20 turns on the
    /// WEAKEST fixture — the middle of the 1.9-2.8 band the WL.2-a probe's legible figures
    /// occupied — needs 0.20 x 2.2 / 0.350 = 1.26.
    ///
    /// At 1.26 the Dubins clamp saturates above |deviation| = 0.50 rad, which the measured
    /// p95 of 0.47-2.47 crosses regularly. That is the bounded-curvature guard finally
    /// DOING something: at 0.20 it engaged on 0.0-0.2% of frames, i.e. the ball-of-yarn
    /// floor was never actually holding anything back, because nothing was turning.
    ///
    /// `ResponseBandTests` (QG.5) holds this honest. If it goes red, fix the gain — do not
    /// widen the band.
    public var curvatureGain: Float = 1.26

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
    /// WL.2-i: 0.25 → 0.45. Matt's M7 — "the preset makes the same choices about movement."
    ///
    /// The route was never dead: `arousal` carries real slow structure (settled window-mean
    /// spread 0.13–0.26 across the fixtures). It was calibrated so shallow that the realised
    /// speed swing was 1.22–1.33×, which no listener connects to the music. At 0.45 the
    /// fixtures swing **2.54–2.58×** — the pen visibly quickens and slackens.
    ///
    /// Stopped at 0.45 rather than pushed further, and the reason is a real constraint, not
    /// caution. Pen speed changes the PATH, the path changes how much the trail overlaps
    /// itself, and the ribbon's lit-pixel share moves with it **non-monotonically** —
    /// measured 0.99 / 1.46 / 0.91 / 0.55 % at depth 0.25 / 0.40 / 0.55 / 0.70. Past ~0.5 the
    /// trail spreads far enough to fall through the WL.2-g luminance floor, and a 1.7× pen is
    /// also the speed at which reference `10` (the unreadable tangle) becomes the risk. 0.45
    /// clears both gates with headroom instead of squeaking past either.
    public var speedModDepth: Float = 0.45

    /// Head-flare refractory, seconds (§5: ≥ 900 ms, ≈ 1.1 flares/s ceiling).
    /// Applies to the FULL-amplitude downbeat burst. The WL.9 off-beat tier is a separate,
    /// much dimmer object with its own interval — see `offBeatRefractory`.
    public var flareRefractory: Float = 0.90

    /// WL.9 — off-beat pulse amplitude, as a fraction of `flareCeiling`.
    ///
    /// Matt, 2026-08-06: "feels too polite… every beat with a harder downbeat." The downbeat
    /// keeps the full §5 burst; the beats between it get this. Deliberately well under half,
    /// so the bar line stays the loudest event in the pattern and the meter is still legible
    /// rather than a flat train of identical flashes.
    public var offBeatShare: Float = 0.42
    /// Minimum interval between off-beat pulses. Shorter than the §5 flare refractory
    /// because the object is dimmer, and bounded so the tier cannot exceed ~2.2 pulses/s.
    public var offBeatRefractory: Float = 0.45
    /// Off-beat pulses only run when a beat is at least this long, i.e. on tracks slow
    /// enough that a per-beat pulse reads as a pulse rather than a flicker. 0.55 s ≈ 109 BPM;
    /// above that the preset stays bar-only, which is what WL.8 shipped.
    public var offBeatMinBeatSeconds: Float = 0.55
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
