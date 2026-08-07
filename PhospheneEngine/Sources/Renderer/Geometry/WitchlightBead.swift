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
    ///
    /// WL.13: 0.10 → 0.060. Matt, 2026-08-07: *"slow the pen down so the ribbon fills the
    /// frame again."* Removing the cold-start coil left the pen turning less, so it covered
    /// more ground per 30 s trail, the auto-fit zoomed out to hold it, and the ribbon thinned
    /// — distinct bright cores 15 → 4 against a floor of 8.
    ///
    /// The recovery is geometric, not cosmetic. `baseRadius` is SCREEN-space (a fraction of
    /// half the frame height) while bead spacing is `baseSpeed / emissionHz` in WORLD units,
    /// so what decides whether beads read as separate cores is spacing × `viewScale` against
    /// a fixed diameter. A zoomed-out fit shrinks the numerator alone, which is exactly how
    /// they fused. Slowing the pen shortens the trail, the fit comes back in (measured
    /// `viewScale` 1.16 → 1.94) and screen spacing returns to what it was solved for:
    ///
    ///     0.0158 world × 1.94 = 0.0307   vs   0.0264 world × 1.16 = 0.0306 before WL.13
    ///
    /// `emissionHz` therefore stays at 3.79 and is NOT re-solved against the new speed. That
    /// was measured too: coupling the two holds the world-space ratio its derivation assumed,
    /// but the bead is screen-space, so it just removes beads — ribbon share fell to
    /// 0.247–0.355 % across the same sweep, against 0.359–0.387 % with emission left alone.
    ///
    /// Costs `headingTurnsPerTrail`, because ω_max is `baseSpeed / minTurnRadius`: measured
    /// 1.44 → 1.30 (there_there) and 1.76 → 1.44 (love_rehab), both still over the 1.20 band.
    /// 0.050 fills more still (`viewScale` 2.33) and was not taken — it puts there_there at
    /// 1.24, one bad track from the floor.
    public var baseSpeed: Float = 0.060

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

    /// How long the pen runs STRAIGHT when the track's tonal home is not known in advance.
    ///
    /// Witchlight steers on the excursion from tonal home, so before it knows where home is
    /// it cannot know which way to turn. It used to guess — `reset()` left home at 0 rad, an
    /// arbitrary point on the circle of fifths, and the 12 s EMA took ~30 s to walk to the
    /// real centre. For that whole window the excursion held ONE SIGN, so curvature held one
    /// sign and the pen wound a coil. 30 s is also the trail length, so the entire visible
    /// figure for the first half-minute of every track was that convergence, not the music:
    /// measured heading monotonicity 0.82-1.00 over the first 15 s of three real sessions,
    /// against 0.10-0.23 over the whole run (WL.13).
    ///
    /// Matt's call, 2026-08-07: draw a straight run instead. An honest straight line while
    /// the key is still being placed beats a coil that claims to be the harmony and is not.
    ///
    /// Does NOT apply when `ingestTonalHome` supplied a pre-analysed home — then home is
    /// right from frame 1 and there is nothing to wait for. 0 disables the suppression.
    public var homeSettleSeconds: Float = 15

    /// The `home` EMA time constant to use at `age` seconds since `reset()`.
    ///
    /// Running it at `min(homeTau, age)` makes home the unbiased running circular mean of
    /// everything heard so far, settling into the full `homeTau` EMA once it has that much
    /// history — the standard EMA warm-up correction. That is what makes the pen's FIRST
    /// steer, at `homeSettleSeconds`, read a real tonal centre rather than a point 15 s into
    /// a ramp from 0 rad. A pre-analysed home skips it: that is already a whole-clip
    /// estimate, so it earns the full memory from frame 1 and passes `age = .infinity`.
    public func effectiveHomeTau(atAge age: Float) -> Float { min(homeTau, age) }

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

    /// Divisor on the arousal running spread when normalising the pen-speed driver.
    ///
    /// LOWER = wider realised speed swing. WL.8 took this 2.0 → 1.5 to answer "the speed
    /// feels weak", validated on ONE session with a model that omitted the energy gate, and
    /// it shipped a pen that lurches: measured 9.95x realised swing on the 171 BPM session
    /// against ~2.5x before. Sweep it with the probe over REAL sessions, never a partial model.
    public var arousalSpreadDivisor: Float = 1.5

    /// WL.5's energy gate on pen advance: `speed *= min(cap, floor + span * energyBreath)`.
    /// A 0.25…1.75 range is a **7x multiplier on speed** and dominates the arousal route
    /// entirely — it, not the arousal normaliser, is what makes the ribbon lurch.
    /// WL.9b: 0.25…1.75 → 0.55…1.45, Matt's pick from the measured swing table. The old
    /// range is a 7x multiplier on speed and produced a realised swing of ~10x on both his
    /// 171 BPM sessions — "the ribbon builds too fast". 0.55…1.45 measures 3.8x: the energy
    /// still visibly drives the pen, and it stops outrunning itself. The pen still halts
    /// completely in silence — that is the separate `silent` branch, untouched.
    public var energyGateFloor: Float = 0.55
    public var energyGateSpan: Float = 0.9
    public var energyGateCap: Float = 1.45

    /// WL.11 — how much of the measured grid-vs-audio drift to cancel, 0…1. 1 = fire at the
    /// tracker's best estimate of the audible beat; 0 = fire on the grid (pre-WL.11).
    public var driftCompensation: Float = 1.0
    /// Hard cap on the correction, milliseconds. The estimate comes from onset detection,
    /// which is weak on dense material; a mis-thrown accent is worse than a slightly late one.
    public var driftCompensationCapMs: Float = 60

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

    /// WL.10 — bead age, in seconds, included in the SCALE fit. `<= 0` or `>= trailSeconds`
    /// means the whole trail, which is the pre-WL.10 behaviour.
    ///
    /// Matt, 2026-08-06: "Does the camera ever zoom back in when the ribbon is back to making
    /// tighter shapes and forms?" Measured answer on his session: barely — `viewScale` ran
    /// 3.68 → 0.73 over two minutes with almost no recovery. The cause is not a time constant
    /// (the shrink τ was swept 4.0 → 0.5 s and the minimum scale never moved off 0.72); it is
    /// that the fit measures the WHOLE 30 s trail, so a wide passage keeps the target large
    /// for a full half-minute after the pen tightens. There is nothing smaller to frame yet.
    ///
    /// Framing a recent window makes the scale track what the pen is drawing NOW. What it
    /// costs is the faded tail spending more time outside the frame — the same trade WL.7
    /// made deliberately when it aimed the camera at the burning head.
    public var fitWindowSeconds: Float = 12

    /// Target RMS radius of the figure, world units — the auto-fit setpoint.
    public var framedRadius: Float = 0.62

    public init() {}
}
