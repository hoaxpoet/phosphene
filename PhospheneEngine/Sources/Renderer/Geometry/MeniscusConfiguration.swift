// MeniscusConfiguration — the Meniscus surface's tunables and its GPU-side mirror.
//
// Split from `MeniscusSurface` so the behaviour file stays readable: most of these
// carry the reasoning for a value that was got wrong once, and that reasoning is the
// point — a bare number here would be re-broken by the next session.
//
// See `docs/presets/MENISCUS_PLAN.md` §9 for the oracle-derived corrections.

import Metal
import Shared

// MARK: - MeniscusPoint (mirror of MSL `MeniscusPoint`, 8 bytes)

/// One sample on the serpentine path: its display height and the slope term the
/// shading reads. Grid coordinates are NOT stored — the vertex shader recovers
/// them from the path index, which keeps the buffer at 8 B/point.
@frozen
public struct MeniscusPoint: Sendable {
    public var height: Float
    public var slope: Float
}

// MARK: - MeniscusConfig (mirror of MSL `MeniscusConfig`, 60 bytes: 3×uint + 12×float)

struct MeniscusConfig {
    var gridN: UInt32
    var pointCount: UInt32
    var spreadMode: UInt32      // 0 = screen-space X (source), 1 = line normal
    var spread: Float           // half-width of the sideways spread, NDC-x units
    var angleX: Float           // the three Euler angles the source integrates
    var angleY: Float
    var angleZ: Float
    var camDist: Float
    var camHeight: Float
    var focal: Float
    var heightScale: Float
    var slopeGain: Float
    var aspect: Float
    var brightness: Float
    var hue: Float              // sky/glare hue, derived from the Euler angles
}

// MARK: - Configuration

public struct MeniscusConfiguration: Sendable {

    /// Grid resolution per side. The source's figure is 45; raising it smooths the
    /// surface but closes the raster gaps (`MENISCUS_PLAN.md` §7 R4).
    public var gridN: Int
    /// Multiplier on the source's own frame-rate-normalised damping (`dec_med`). 1.0 is
    /// the source's value; the step applies `damping * (1 - 1.8/fps)`.
    ///
    /// BELOW 1.0 ON PURPOSE — the deliberate divergence that makes the activity readable
    /// as rhythm. At the source's value a ripple outlives its beat (1/e in ~550 ms against
    /// a 350 ms beat at 171 BPM), so ripples always overlap and the field never returns
    /// toward rest. Measured beat-folded modulation depth: 1.00 -> 15 %, 0.97 -> 22 %,
    /// 0.93 -> 29 %, 0.88 -> 48 %, 0.82 -> 76 %. Matt, four rounds running: "the activity
    /// needs to be synced to music, that is the core trouble" — and rhythm needs REST as
    /// much as it needs onsets. The source's damping suits its own continuous cepstral
    /// drop stream; ours is beat-locked punctuation and needs the field to fall between
    /// beats. Cost: shorter ripples interfere less, which weakens §1's "wake" reading.
    public var damping: Float
    /// Vertical exaggeration applied to the height field at projection time.
    public var heightScale: Float
    /// Sideways glow half-width as a FRACTION OF THE PROJECTED ROW SPACING.
    ///
    /// This is the blur Matt named on 2026-08-04, and it was a units error, not taste. It
    /// used to be an absolute NDC value, which says nothing about whether neighbouring
    /// rows merge: at the resting camera the plate spans ~0.65 NDC across 45 rows, so rows
    /// sit ~0.014 apart while the spread was 0.033 — more than twice the gap, so every
    /// line bled into both neighbours and the raster read as a grey sheet. The whole point
    /// of the sideways-only spread (anti-reference 5) is that the gaps SURVIVE.
    ///
    /// Expressed against row spacing it is scale-free: below 0.5 the lines are separated
    /// at any camera distance and any grid resolution, which also makes it robust to the
    /// §6 grid-resolution decision that is still open.
    public var spread: Float
    /// 0 = spread along screen-space X (what the source does), 1 = along the segment's
    /// screen-space normal. MEN.2a task 1a answered this from renders — screen-space X;
    /// the tangent-normal ribbon closes the raster. Full reasoning at the `THE SPREAD`
    /// note in `MeniscusSurface.metal`, and see `yawCentre`, which it constrains.
    public var spreadMode: Int
    /// How fast the silence swell fades out as loudness rises. The swell exists to carry
    /// §4's silence row; once the music is playing the DROPS are meant to be the surface.
    public var swellFadeRate: Float
    /// Amplitude of the silence-state standing swell. Set to 0 and
    /// the surface is whatever the sim is doing on its own.
    public var swellAmplitude: Float
    /// IIR coefficient for the lagged smoothed height the slope term differences
    /// against. 1.0 degenerates to a plain forward difference.
    public var slopeLag: Float
    /// Contrast of the slope→brightness term (trait T3).
    ///
    /// Tied to `swellAmplitude`: a calmer field has proportionally smaller slopes, so
    /// holding the gain fixed while calming the surface trades all-over agitation for
    /// a flat grey sheet — "a soft, evenly-lit version of this looks like fabric, not
    /// water". The two move together. MEN.2b must revisit this once drop impacts
    /// exist: an impact SHOULD saturate to white, so the gain wants to be set from the
    /// calm baseline and allowed to clip on transients, not fitted to the peak.
    public var slopeGain: Float
    /// Peak magnitude of a re-randomised angular velocity, radians/second.
    ///
    /// MEN.2a bounded the heading to ±0.16 rad because a fixed screen-X spread closes
    /// the raster once rows swing off-horizontal (`spread · |sin θ|` perpendicular
    /// fattening). The SOURCE has no such bound — it tumbles freely — because its
    /// dilation radius scales with camera proximity. `spreadTracksDistance` restores
    /// that coupling, which is what buys the free camera back.
    public var tumbleRate: Float
    /// Smoothing time constant on the angular velocities, seconds. Scaled down by
    /// volume at run time so re-aims snap harder when the music is loud.
    public var cameraTau: Float
    /// Resting camera distance, and the half-range of the slow distance oscillation.
    /// The oscillation sweeps the plate between a small floating rhombus and a
    /// frame-filling sheet — measured off the oracle as the largest single change in
    /// the frame over a few seconds.
    public var camDistCentre: Float
    public var camDistSwing: Float
    /// Smoothing time constant on the arousal-driven dolly, seconds. §5 puts this row on
    /// a ~20–40 s timescale — deliberately far slower than the loudness envelope that
    /// drives surface amplitude, so the two read as separate behaviours (FA #67).
    public var dollyTau: Float
    /// Drops on/off.
    public var dropsEnabled: Bool
    /// MEN.3: place drops by STEM REGION (the D-121 divergence) rather than by the
    /// source's cepstral transform. False restores the MEN.2b faithful base, which is
    /// kept as the oracle to A/B against — §2's whole argument for building it.
    public var stemPlacement: Bool
    /// Deviation above a stem's own running mean at which it drops (D-026 / FA #31 — a
    /// deviation, never an absolute level), and the minimum gap between two drops from
    /// the same stem so a sustained note is one impact rather than a machine-gun.
    public var stemDropThreshold: Float
    public var stemDropRefractory: Float
    /// Global scale on the per-region forces in `MeniscusStemDrops.regions`.
    ///
    /// CALIBRATED AGAINST AUDIO SHARE, not chosen. At 1.0 the drops moved the surface
    /// 0.0002 against 0.0203 from autonomous motion — the music caused ~1 % of what was on
    /// screen, which is why four rounds of drop-TIMING work changed nothing visible.
    ///
    /// FORCE AND `damping` ARE COUPLED and must be re-swept together: a faster decay eats
    /// the energy each drop deposits, so shortening the ripple silently flattens the
    /// surface. Dropping damping to 0.88 flattened the plate by 8x at the old force of 25
    /// while every derived gate still read green, because the harness held a hardcoded
    /// copy of the old damping.
    ///
    /// SWEEP AGAINST THE REAL SURFACE, AT LENGTH, ON MORE THAN ONE TRACK. Each of those
    /// three qualifiers cost a wrong answer:
    ///
    /// - `MeniscusAudioShareTests` keeps a private wave loop whose absolute displacement
    ///   does NOT agree with production (peak 0.186 there against 0.032 from the real
    ///   surface at the same force). It is a valid instrument for the audio-vs-autonomous
    ///   RATIO and an invalid one for amplitude. Calibrating on it said force 100.
    /// - A 300-frame (5 s) window landed on a quiet passage and said force 800. The
    ///   scheme's equilibrium amplitude goes as force/(1 - effective damping), and it
    ///   takes ~20 s to get there — at 1200 frames that same 800 is ~4x the reference.
    /// - `there_there` alone said 110; `love_rehab` runs ~1.6x hotter for the same force.
    ///
    /// Honest calibration: 1200 frames (20 s, near equilibrium), both tracks, against the
    /// damping-1.0/force-25 reference the preset had before the ripples were shortened
    /// (rms 0.266 / 0.337). 85 brackets it — 0.78x on `there_there`, 1.27x on
    /// `love_rehab`. Per-track spread that size is the tracks differing, not a mistuning.
    public var stemDropForce: Float
    /// Take drums/bass TIMING from the cached BeatGrid instead of live threshold
    /// crossings (the audio hierarchy's rule; D-153→D-158). Falls back to onset-driven
    /// automatically when no grid is installed.
    public var stemGridSync: Bool
    /// On a grid beat, how much presence a stem needs before it places a drop. LOWER
    /// than `stemDropThreshold` because the grid already supplies the timing — this only
    /// asks "is this instrument playing", so a beat with no drums on it stays silent.
    public var stemPresenceThreshold: Float
    /// Band level below which NO drop is placed, however the grid is ticking (MEN.3h).
    ///
    /// Matt, eighth round: "drops are still falling at silence." Nothing in the firing
    /// path read current loudness — the grid keeps time through a quiet passage, and the
    /// only presence gate came from STEMS, which lag ~5.2 s and so cannot close on a
    /// silence that just began. Measured on `2026-08-05T15-06-31Z` (Hummer): the band
    /// level is exactly 0.0000 on >25 % of frames, with a p50 of 0.093 while the music
    /// plays — so 0.02 separates real silence from the quietest real passage with room to
    /// spare, and the ~0.12 s envelope in front of it opens on the first note of a phrase.
    public var silenceFloor: Float
    /// How far BEFORE the grid beat a percussion drop is stamped, seconds.
    ///
    /// Not a fudge factor — it compensates a measured property of the medium. The impulse
    /// reaches only 14 % of its visible slope response after one frame, ~30 % at 67 ms and
    /// ~50 % at 167 ms (`MeniscusRippleRiseTests`), so the eye sees the ring FORMING well
    /// after the impact. Leading by the ripple's perceptual onset puts the visible event
    /// on the beat. Matt's call, 2026-08-04: start at 120 ms and measure.
    public var stemLeadTime: Float
    /// Amplitude floor at silence.
    ///
    /// Not free to be small: §4's silence row is "a slow standing swell — the sheet
    /// breathes … Never black", so silence must still visibly move. At 0.22 the swell was
    /// scaled to 7.7e-5 per frame against the harness's 8e-5 frozen floor — the surface
    /// was technically alive and perceptually stalling. 0.35 keeps it breathing while
    /// still leaving a 3.5x span up to the loud ceiling.
    public var stemIntensityFloor: Float
    /// Drop constants, READ FROM THE SOURCE (Matt's call, 2026-08-03) rather than
    /// guessed — four rounds of guessing missed the rate by more than 100x.
    ///
    /// `dropGate` is the source's `above(amp, 0.02)`, a hard threshold on the amplitude
    /// of the AGC-NORMALISED, decay-accumulated transform output. FA #31 forbids absolute
    /// thresholds on AGC-normalised BAND ENERGY; this is neither — the source AGCs the
    /// spectrum itself first, which is precisely what my four attempts were missing.
    /// `dropForce` is the source's unit scale; the frame-rate term (60/fps) lives in the
    /// step.
    /// UNITS CONVERSION between Milkdrop's spectrum scale and Phosphene's
    /// `FFTProcessor` magnitudes. Every other drop constant is the source's own value;
    /// this one has no counterpart there, because the source never had to cross between
    /// two different spectra.
    ///
    /// CALIBRATED, NOT CHOSEN. `amp` scales as 1/level², so the multiplier follows in
    /// closed form from where `amp` actually sits relative to the source's 0.02 gate.
    /// Measured on the three committed fixtures (`MeniscusCalibrationProbe`), the
    /// multiplier that puts each track's 98th-percentile amp on the gate is 7.4x
    /// (so_what), 16.7x (there_there) and 24.9x (love_rehab). The 3.4x spread is the
    /// MUSIC differing and is meant to survive — a busier track should place more drops
    /// — so this takes the median rather than flattening them.
    public var dropSpectrumScale: Float
    public var dropGate: Float
    public var dropForce: Float
    /// Force above which an impact counts as a VISIBLE drop. Diagnostic only —
    /// it gates the reported rate, never the physics.
    public var dropVisibleForce: Float
    /// Scale the sideways spread with camera proximity, as the source's comp stage
    /// does. This is what makes a free-tumbling camera compatible with an open raster:
    /// when the plate is far and the rows crowd together, the spread shrinks with it.
    public var spreadTracksDistance: Bool

    public init(
        gridN: Int = 45,
        damping: Float = 0.88,
        heightScale: Float = 0.32,
        spread: Float = 0.45,
        spreadMode: Int = 0,
        swellAmplitude: Float = 0.10,
        swellFadeRate: Float = 6.0,
        slopeLag: Float = 0.35,
        slopeGain: Float = 34.0,
        tumbleRate: Float = 0.55,
        cameraTau: Float = 0.85,
        camDistCentre: Float = 3.05,
        camDistSwing: Float = 1.35,
        dollyTau: Float = 14.0,
        spreadTracksDistance: Bool = true,
        dropsEnabled: Bool = true,
        stemPlacement: Bool = true,
        stemDropThreshold: Float = 0.30,
        stemDropRefractory: Float = 0.09,
        stemDropForce: Float = 85.0,
        stemGridSync: Bool = true,
        stemPresenceThreshold: Float = 0.12,
        silenceFloor: Float = 0.02,
        stemLeadTime: Float = 0.120,
        stemIntensityFloor: Float = 0.35,
        dropSpectrumScale: Float = 10.0,
        dropGate: Float = 0.02,
        dropForce: Float = 1.0,
        dropVisibleForce: Float = 0.05
    ) {
        self.gridN = gridN
        self.damping = damping
        self.heightScale = heightScale
        self.spread = spread
        self.spreadMode = spreadMode
        self.swellAmplitude = swellAmplitude
        self.swellFadeRate = swellFadeRate
        self.slopeLag = slopeLag
        self.slopeGain = slopeGain
        self.tumbleRate = tumbleRate
        self.cameraTau = cameraTau
        self.camDistCentre = camDistCentre
        self.camDistSwing = camDistSwing
        self.dollyTau = dollyTau
        self.spreadTracksDistance = spreadTracksDistance
        self.dropsEnabled = dropsEnabled
        self.stemPlacement = stemPlacement
        self.stemDropThreshold = stemDropThreshold
        self.stemDropRefractory = stemDropRefractory
        self.stemDropForce = stemDropForce
        self.stemGridSync = stemGridSync
        self.stemPresenceThreshold = stemPresenceThreshold
        self.silenceFloor = silenceFloor
        self.stemLeadTime = stemLeadTime
        self.stemIntensityFloor = stemIntensityFloor
        self.dropSpectrumScale = dropSpectrumScale
        self.dropGate = dropGate
        self.dropForce = dropForce
        self.dropVisibleForce = dropVisibleForce
    }
}
