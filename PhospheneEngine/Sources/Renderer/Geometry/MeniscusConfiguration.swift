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
    /// Wave-propagation damping per step. < 1 so energy bleeds away.
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
    /// Drops are PORTED BUT NOT CALIBRATED, and are off until they are.
    ///
    /// The placement mechanism is verified (`MeniscusDropsTests`): harmonic spacing
    /// decides position, a structureless spectrum places nothing, impacts are narrow.
    /// What is NOT settled is the force scale. Three attempts measured 297-522, then
    /// 713-838, then 9.7-569 (track-dependent), then 1800 drops/second against a target
    /// of a few — every one of them a guess at a constant §3 does not record. Guessing a
    /// fourth time is the FA #73 failure mode, so the switch stays off and the
    /// calibration is an open question rather than a silently-wrong default.
    public var dropsEnabled: Bool
    /// Drop tunables (MEN.2b — see `MeniscusDrops`).
    ///
    /// `dropThreshold` is a DEVIATION multiple of a bin's own running mean, never an
    /// absolute level on AGC-normalised input (D-026 / FA #31). `dropForceCeiling`
    /// bounds a single impact so a loud transient cannot punch the field into a spike
    /// the wave step then rings on for seconds.
    public var dropThreshold: Float
    public var dropForce: Float
    public var dropForceCeiling: Float
    /// Squash factor mapping the transform's real/imag parts onto the grid. Larger
    /// pushes drops toward the margins; smaller clusters them centrally.
    public var dropSpread: Float
    /// Force above which an impact counts as a VISIBLE drop. Diagnostic only —
    /// it gates the reported rate, never the physics.
    public var dropVisibleForce: Float
    /// Transform energy at which the drop drive reaches full scale. Below it the
    /// drive falls off proportionally, so a structureless or silent spectrum places
    /// nothing rather than stamping every bin at full force.
    public var dropLevelReference: Float
    /// Scale the sideways spread with camera proximity, as the source's comp stage
    /// does. This is what makes a free-tumbling camera compatible with an open raster:
    /// when the plate is far and the rows crowd together, the spread shrinks with it.
    public var spreadTracksDistance: Bool

    public init(
        gridN: Int = 45,
        damping: Float = 0.995,
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
        dropsEnabled: Bool = false,
        dropThreshold: Float = 0.35,
        dropForce: Float = 9.0,
        dropForceCeiling: Float = 0.55,
        dropSpread: Float = 2.6,
        dropVisibleForce: Float = 0.05,
        dropLevelReference: Float = 0.004
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
        self.dropThreshold = dropThreshold
        self.dropForce = dropForce
        self.dropForceCeiling = dropForceCeiling
        self.dropSpread = dropSpread
        self.dropVisibleForce = dropVisibleForce
        self.dropLevelReference = dropLevelReference
    }
}
