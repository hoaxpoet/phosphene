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
    public var damping: Float
    /// Vertical exaggeration applied to the height field at projection time.
    public var heightScale: Float
    /// Half-width of the sideways glow spread at the RESTING camera distance, in NDC-x
    /// units, scaled per-frame by `spreadTracksDistance`.
    ///
    /// It is a fraction of the plate's on-screen size, not an absolute: MEN.2a's 0.070
    /// was calibrated against a camera 1.45 out, and carrying that number to the
    /// restored resting distance of 3.05 made the spread ~2x too wide for the rows and
    /// welded the raster into a solid sheet. Rescaled by 1.45/3.05.
    public var spread: Float
    /// 0 = spread along screen-space X (what the source does), 1 = along the segment's
    /// screen-space normal. MEN.2a task 1a answered this from renders — screen-space X;
    /// the tangent-normal ribbon closes the raster. Full reasoning at the `THE SPREAD`
    /// note in `MeniscusSurface.metal`, and see `yawCentre`, which it constrains.
    public var spreadMode: Int
    /// Amplitude of the MEN.2a placeholder standing swell (task 6). Set to 0 and
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
    /// Period of the distance oscillation, seconds.
    public var dollyPeriod: Float
    /// Drops on/off.
    public var dropsEnabled: Bool
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
        damping: Float = 1.0,
        heightScale: Float = 0.32,
        spread: Float = 0.033,
        spreadMode: Int = 0,
        swellAmplitude: Float = 0.10,
        slopeLag: Float = 0.35,
        slopeGain: Float = 34.0,
        tumbleRate: Float = 0.55,
        cameraTau: Float = 0.85,
        camDistCentre: Float = 3.05,
        camDistSwing: Float = 1.35,
        dollyPeriod: Float = 19.0,
        spreadTracksDistance: Bool = true,
        dropsEnabled: Bool = true,
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
        self.slopeLag = slopeLag
        self.slopeGain = slopeGain
        self.tumbleRate = tumbleRate
        self.cameraTau = cameraTau
        self.camDistCentre = camDistCentre
        self.camDistSwing = camDistSwing
        self.dollyPeriod = dollyPeriod
        self.spreadTracksDistance = spreadTracksDistance
        self.dropsEnabled = dropsEnabled
        self.dropSpectrumScale = dropSpectrumScale
        self.dropGate = dropGate
        self.dropForce = dropForce
        self.dropVisibleForce = dropVisibleForce
    }
}
