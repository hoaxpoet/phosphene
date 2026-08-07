// WitchlightPath — the pen, the trail, and the music that steers them.
//
// Pure CPU model, no Metal: `WitchlightStroke` owns the buffers and pipelines and calls
// `advance` once per frame; this file owns everything that decides WHERE the pen goes and
// WHAT COLOUR it lays down. Split out so the path generator is unit-testable against
// synthetic driver inputs without a GPU (`WitchlightPathTests`).
//
// The three mechanisms, in the order `advance` runs them (WITCHLIGHT_DESIGN §3.1):
//
//   (a) HEADING — the harmonic steer. `tonalPhaseFifths` is a ±π circular quantity with a
//       measured median per-frame step of 0.31–1.04 rad, far too noisy to steer a pen raw.
//       It is smoothed by the CR.1.2 / D-198 mechanism already shipped in Phosphene: EMA
//       the sin and cos separately and recombine with `atan2`. NEVER EMA the raw sawtooth.
//
//   (b) ADVANCE — bounded-curvature kinematics (Dubins 1957). Moved to
//       `WitchlightPath+Pen.swift` at WL.9 for the 400-line lint; the rationale lives
//       with the code.
//
//   (c) RELAXATION — age-weighted neighbour averaging (discrete Laplacian curve smoothing,
//       the Taubin λ|μ family). Full weight on beads younger than ~1 s, zero by ~4 s, and
//       FROZEN beyond. The source relaxes its whole buffer forever, which is why its figure
//       slumps; freezing the old part is what makes "a drawing of where the song has been"
//       true rather than decorative.
//
// Deviation semantics throughout (D-026 / FA #31): every driver is read against a
// per-track running reference, never against an absolute level on an AGC-normalized value.

import Foundation
import Shared

// MARK: - WitchlightPath

/// The pen, the ring buffer, and the music envelopes that drive them.
///
/// Not thread-safe by itself; `WitchlightStroke` owns the only instance and touches it
/// from the render loop only.
/// Setter access note: the members the `+Events` extension mutates are `internal(set)`
/// rather than `private(set)` — Swift's file-scoped `private` cannot span the two files the
/// lint budget requires. The public read-only surface is unchanged.
public final class WitchlightPath: AudioResponseMetrics {

    public private(set) var tuning: WitchlightTuning

    /// The trail, oldest first. Rebuilt in emission order every frame so the line strip
    /// has no wrap seam — 1024 × 32 B is a trivial per-frame cost.
    public internal(set) var beads: [WitchlightBead] = []

    // Pen state.
    public internal(set) var heading: Float = 0
    var penX: Float = 0
    var penY: Float = 0
    var emitAccumulator: Float = 0

    // Harmonic state — sin/cos accumulators, NEVER the raw ±π sawtooth.
    private var phaseSin: Float = 0
    private var phaseCos: Float = 1
    private var previousPhase: Float = 0
    var phaseRate: Float = 0
    /// Smoothed harmonic phase φ̄, radians. Also the hue source (§3.4).
    public var smoothedPhase: Float { atan2(phaseSin, phaseCos) }

    // Tonal "home" — a long-τ circular mean of φ̄, for `.curvatureDeviation`.
    /// Running estimate of |deviation from tonal home|, for the per-track gain.
    var deviationScale: Float = 0.3

    private var homeSin: Float = 0
    private var homeCos: Float = 1
    /// Wrapped excursion of φ̄ from the track's tonal home, radians (±π).
    public var phaseFromHome: Float {
        var delta = smoothedPhase - atan2(homeSin, homeCos)
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        return delta
    }

    // Turn detection.
    var turnSign: Float = 0
    var turnCandidateSign: Float = 0
    var turnCandidateAge: Float = 0
    var turnCandidateBeadIndex: Int?
    var hueTurnOffset: Float = 0
    /// Confirmed turns since `reset()` — the §3.2 chord-change event count.
    public internal(set) var turnCount: Int = 0

    // Arousal running reference (deviation semantics — no absolute level on `arousal`).
    // `internal`, not `private`: `advancePen` lives in WitchlightPath+Pen.swift and a Swift
    // extension in a second file cannot reach file-private state.
    var arousalSlow: Float = 0
    var arousalSpread: Float = 0.15

    // Head flare.
    var bassDevSlow: Float = 0
    var flareRefractoryRemaining: Float = 0
    var flareGoal: Float = 0
    var flareHold: Float = 0
    /// Current flare amplitude, 0…`flareCeiling`. Bounded by the §5 budget.
    public internal(set) var flareIntensity: Float = 0
    /// Full-amplitude (downbeat) flare firings since `reset()`.
    public internal(set) var flareCount: Int = 0
    /// WL.9 — dimmer off-beat pulses since `reset()`, counted separately so the §5 rate
    /// budget can be read per tier instead of as one blended number.
    public internal(set) var offBeatCount: Int = 0
    var offBeatRefractoryRemaining: Float = 0

    // Bar promotion.
    var previousBarPhase: Float = 0
    var promoteNextBead = false
    /// True on the single frame a bar wraps. WL.8 hoisted it out of `emit` because the
    /// flare now needs it too, and two independent wrap detectors would drift apart.
    var barDownbeatNow = false
    /// WL.9 — true on the frame any BEAT lands, downbeat included. Derived by subdividing
    /// `barPhase01` rather than read from `beatPhase01`, which measured stalled (24 wraps in
    /// 215 s where 614 were due). Subdividing also handles odd meters for free.
    var beatEdgeNow = false
    var previousBeatSlot = -1
    /// Seconds between the last two bar wraps — the runtime tempo estimate the off-beat
    /// tier is gated on. No `bpm` field is needed on FeatureVector.
    var barPeriod: Float = 0
    var timeSinceWrap: Float = 0
    /// WL.11 — the beat tracker's own estimate of how far its grid sits from the audible
    /// beat, seconds, already clamped and smoothed. Fed through the CPU-only runtime tick
    /// (the same bridge `sectionIndex` uses) because it never needs to reach a shader —
    /// no `FeatureVector` field, so no MSL layout contract to break.
    public internal(set) var beatDriftSeconds: Float = 0

    /// Seconds since `barPhase01` last read non-zero. `barPhase01` is documented as
    /// "always 0 in reactive mode (no BeatGrid installed)", so this IS the grid-trust
    /// signal — no separate confidence field needed, and D-154's "beat-irregular tracks
    /// excluded" falls out for free: no grid, no bar pulse.
    var gridSilentFor: Float = 0
    /// Downbeat beads set since `reset()`.
    public internal(set) var promotionCount: Int = 0

    // Section contraction.
    private var previousSectionIndex: UInt32?
    var contractGoal: Float = 0
    var contractHold: Float = 0
    var contraction: Float = 0
    /// Section boundaries ingested since `reset()`.
    public internal(set) var sectionEventCount: Int = 0
    /// WL.12 — deepest trail contraction seen this run, 0…1. The `trail_contraction` route's
    /// visible consequence; 0 means no section boundary ever shortened the trail.
    public internal(set) var contractionPeak: Float = 0

    // View framing (a VIEW property, not a path property — see `advance`).
    public internal(set) var centroidX: Float = 0, centroidY: Float = 0
    public internal(set) var viewScale: Float = 1
    /// Where the camera AIMS — head-biased, NOT `centroid` (which only fits the scale). `reframe` says why.
    public internal(set) var cameraX: Float = 0, cameraY: Float = 0
    /// WL.10 — the centre the SCALE is fitted about. Distinct from `centroid` (whole trail,
    /// drives the aim) because the fit now measures a recent window and a radius must be
    /// measured from the centre of the same points it covers.
    public internal(set) var fitCentroidX: Float = 0, fitCentroidY: Float = 0
    var rmsRadius: Float = 0.4

    // Plane tumble.
    // `internal`, not `private`: the tumble lives in WitchlightPath+Tumble.swift, and a
    // Swift extension in a second file cannot reach file-private state (same reason as
    // the +Events members).
    var tumbleClock: Float = 0
    /// Per-session framing: a phase offset on the tumble oscillators and a roll handedness.
    /// The FIGURE stays a deterministic reading of the music — the same track always draws the
    /// same drawing — but each session views it from a different angle and chirality, so a
    /// repeat play reads as the same figure seen anew rather than an identical stamp. Matt's
    /// call over "same figure exactly" and "different every play" (2026-08-04).
    ///
    /// Injected rather than randomised INSIDE the path: the replay harness, the golden
    /// dHashes and the QG.5 bands all require byte-identical output for identical input.
    /// The app layer sets it once per session; tests render the canonical framing.
    var sessionPhase: Float = 0
    var tumbleHandedness: Float = 1
    /// Current visible age window after section contraction.
    public internal(set) var trailWindow: Float = 30

    // Instrumentation — WITCHLIGHT_DESIGN §3.1(b) requires WL.2 to REPORT the fraction of
    // frames spent at the turn-rate clamp on each of the four §2 captures. If a capture
    // sits at the clamp > 80 % of the time the figure degenerates to a circle and
    // `steerGain` comes down; `minTurnRadius` does not go up.
    public private(set) var frameCount: Int = 0

    /// Wall-clock seconds of drive consumed, for per-unit response metrics (QG.5).
    public private(set) var elapsedSeconds: Double = 0
    public internal(set) var clampedFrameCount: Int = 0
    /// ∫|φ̄̇| dt — how far the smoothed harmonic phase travelled, radians. The design's
    /// §2.3 measurement quotes this as "circles over 30 s" (2.1 / 1.7 / 15.4 on the
    /// fixtures); reproducing it here is what proves the steer is reading the real driver.
    public internal(set) var phaseTravel: Float = 0
    /// ∫|θ̇| dt — how far the PEN's heading actually turned, radians. `phaseTravel × k`
    /// before clamping; the gap between them is what the clamp removed.
    public internal(set) var headingTravel: Float = 0
    /// WL.4 — the per-frame energy breath, 0…1 centred 0.5. Lives here rather than in
    /// `WitchlightStroke` so every audio→state mapping is in one place and the QG.5 metrics
    /// seam (which is on this type) can gate it.
    public internal(set) var energyBreath: Float = 0.5
    var breathSlow: Float = 0
    var breathSpread: Float = 0.08
    /// Extremes seen this run — the `ribbonBreathSwing` evidence.
    var breathMin: Float = .greatestFiniteMagnitude
    var breathMax: Float = 0
    /// Slowest and fastest pen speed seen this run — the QG.5 `penSpeedSwing` evidence.
    /// `internal`, not `private`, so the metric can live in `WitchlightPath+Metrics.swift`.
    var speedMin: Float = .greatestFiniteMagnitude
    var speedMax: Float = 0
    /// Net signed heading change. `|headingNet| / headingTravel` near 1 means the pen turned
    /// one way the whole time — the "degenerates to a circle" state design §3.1(b) warns
    /// about when the clamp saturates. Near 0 means it reversed, which is a figure.
    public internal(set) var headingNet: Float = 0
    public var headingMonotonicity: Float {
        headingTravel > 1e-4 ? abs(headingNet) / headingTravel : 0
    }
    public var clampedFraction: Float {
        frameCount > 0 ? Float(clampedFrameCount) / Float(frameCount) : 0
    }

    /// Test seam for sweeping tuning against a real session.
    func overrideTuning(_ new: WitchlightTuning) { tuning = new }

    public init(tuning: WitchlightTuning = WitchlightTuning()) {
        self.tuning = tuning
        self.trailWindow = tuning.trailSeconds
        beads.reserveCapacity(capacity)
    }

    /// Ring capacity: `trailSeconds × emissionHz`, rounded up to the next power of two.
    var capacity: Int { 1024 }

    // MARK: - Lifecycle

    /// Clear the pen, the trail and every envelope.
    ///
    /// Called on preset-apply AND on track change. The `LumenPatternEngine`
    /// `resetBeatTrackingState` precedent is load-bearing for the same reason: a stale φ̄
    /// or `previousBarPhase` across a track boundary lays down a wrong-coloured or
    /// spuriously-promoted first bead.
    /// Set the per-session framing. `fraction` is any value in 0…1 — the app passes one
    /// value per session, tests leave it at the default so output stays deterministic.
    /// Call BEFORE `reset()`, or after: it is independent of the path state.
    public func setSessionFraming(_ fraction: Float) {
        let frac = fraction - fraction.rounded(.down)
        sessionPhase = frac * 2 * .pi
        tumbleHandedness = frac < 0.5 ? 1 : -1
    }

    public func reset() {
        beads.removeAll(keepingCapacity: true)
        heading = 0; penX = 0; penY = 0; emitAccumulator = 0
        phaseSin = 0; phaseCos = 1; previousPhase = 0; phaseRate = 0
        homeSin = 0; homeCos = 1
        turnSign = 0; turnCandidateSign = 0; turnCandidateAge = 0
        turnCandidateBeadIndex = nil; hueTurnOffset = 0; turnCount = 0
        arousalSlow = 0; arousalSpread = 0.15
        breathSlow = 0; breathSpread = 0.08
        energyBreath = 0.5
        breathMin = .greatestFiniteMagnitude; breathMax = 0
        bassDevSlow = 0; flareRefractoryRemaining = 0
        flareGoal = 0; flareHold = 0; flareIntensity = 0; flareCount = 0
        offBeatCount = 0; offBeatRefractoryRemaining = 0
        previousBarPhase = 0; promoteNextBead = false; promotionCount = 0
        barDownbeatNow = false; gridSilentFor = 0; beatDriftSeconds = 0
        beatEdgeNow = false; previousBeatSlot = -1; barPeriod = 0; timeSinceWrap = 0
        previousSectionIndex = nil; contractGoal = 0; contractHold = 0; contraction = 0
        sectionEventCount = 0; contractionPeak = 0
        centroidX = 0; centroidY = 0; viewScale = 1; rmsRadius = 0.4; cameraX = 0; cameraY = 0
        fitCentroidX = 0; fitCentroidY = 0
        tumbleClock = 0
        trailWindow = tuning.trailSeconds
        frameCount = 0; clampedFrameCount = 0; phaseTravel = 0; headingTravel = 0; headingNet = 0
        speedMin = .greatestFiniteMagnitude; speedMax = 0
        elapsedSeconds = 0
        deviationScale = 0.3
    }

    /// Ingest the live structural-section prediction.
    ///
    /// Delivered by the app layer through the `RenderPipeline.latestStructuralPrediction`
    /// bridge (the Skein.ENGINE.3 / D-151 precedent) because `StructuralPrediction` is
    /// CPU-only and does not reach the `ParticleGeometry.update` signature.
    /// Ingest the live grid-vs-audio drift estimate.
    ///
    /// Sign follows `LiveBeatDriftTracker.currentDriftMs`: **positive means the audible beats
    /// arrive EARLIER than the grid predicts**, so a positive value makes the pulse LEAD.
    /// Getting this backwards would double the error rather than cancel it.
    ///
    /// Clamped hard at +/-`driftCompensationCapMs`: the estimate is derived from onset
    /// detection, which is weak on dense material, and an accent thrown a third of a beat by
    /// a bad estimate is far worse than one sitting 25 ms late. Smoothed because a pulse
    /// whose timing jitters frame to frame reads as sloppiness, not correction — though the
    /// signal is already slow (autocorrelation +0.985 at 1 s on real sessions).
    public func ingestBeatDrift(milliseconds: Float) {
        let cap = tuning.driftCompensationCapMs
        let clamped = max(-cap, min(cap, milliseconds)) * 0.001
        let alpha: Float = 0.02
        beatDriftSeconds += (clamped * tuning.driftCompensation - beatDriftSeconds) * alpha
    }

    public func ingestStructure(_ structure: StructuralPrediction) {
        defer { previousSectionIndex = structure.sectionIndex }
        guard let previous = previousSectionIndex, previous != structure.sectionIndex else { return }
        contractGoal = 1
        contractHold = 0.4
        sectionEventCount += 1
    }

    // MARK: - Per-frame advance

    /// Advance one frame: steer, move, emit, age, relax, reframe.
    public func advance(deltaTime: Float, features: FeatureVector, stems: StemFeatures) {
        let dt = min(max(deltaTime > 0 ? deltaTime : 1.0 / 60.0, 1.0 / 240.0), 1.0 / 30.0)
        frameCount += 1
        elapsedSeconds += Double(dt)
        let mixEnergy = features.bass + features.mid + features.treble

        // WL.5 — silence is decided by the LIVE MIX ALONE, and the `&& stemTotal` that used to
        // be here is why Matt kept seeing the pattern move with no music playing.
        //
        // Measured on session `2026-08-05T13-06-38Z`: across a 5.5 s stretch where every mix
        // band read exactly 0.000000, the stems read drums 0.52 / bass 0.57 / vocals 1.07 /
        // other 0.67 — the separator runs on a lagging buffer and HOLDS its last values, so
        // `stemTotal <= 0` was essentially never true and the whole `silent` branch was dead
        // code. The mix bands collapse immediately, so they are the honest test for "is there
        // sound right now"; stems no longer get a vote on whether the room is quiet.
        let silent = mixEnergy <= 1e-6

        // WL.5 — the plane holds still in silence too. With the pen gated, the tumble was the
        // only thing still moving when the audio stopped, and "the pattern is still moving
        // when the preset is idle" is the complaint being answered; a drawing that keeps
        // rotating itself is still a drawing that is not listening. Stars and bloom continue
        // (they are the room, not the subject) so D-037's non-black frame is unaffected.
        if !silent { tumbleClock += dt }

        // WL.8 — the bar wrap is detected ONCE, here, ahead of everything that reacts to it.
        //
        // WL.11 — and the phase is SHIFTED by the tracker's own drift estimate before any edge
        // is taken off it. Advancing the phase makes every edge — bar and beat alike — fire
        // earlier by that amount, which is what "positive drift = beats arrive early" asks
        // for, and it needs no second code path for the negative case.
        //
        // Why this is not a re-run of the parked tracker work (D-206): it does not try to fix
        // the GRID. The grid keeps its phase; the consumer subtracts the error the tracker
        // already publishes and nobody was reading. Matt's "beat match is close but not
        // exact" measured 25 ms median / 91 ms worst on his session, against a pulse that is
        // otherwise exact on the grid.
        let rawBar = features.barPhase01
        let bar: Float
        if barPeriod > 0 && beatDriftSeconds != 0 {
            let shifted = rawBar + beatDriftSeconds / barPeriod
            bar = shifted - floor(shifted)
        } else {
            bar = rawBar
        }
        barDownbeatNow = previousBarPhase > 0.85 && bar < 0.15
        previousBarPhase = bar
        if barDownbeatNow { promoteNextBead = true }
        gridSilentFor = rawBar > 0 ? 0 : gridSilentFor + dt
        timeSinceWrap += dt
        if barDownbeatNow { barPeriod = timeSinceWrap; timeSinceWrap = 0 }
        // WL.9 — beat edges by subdividing the bar. `beatsPerBar` carries the meter, so 7/8
        // subdivides into 7 and the pulse stays musical without a special case.
        let perBar = max(1, Int(features.beatsPerBar.rounded()))
        let slot = min(perBar - 1, Int(bar * Float(perBar)))
        beatEdgeNow = slot != previousBeatSlot && previousBeatSlot >= 0
        previousBeatSlot = slot

        advanceHarmonicPhase(dt: dt, features: features)
        updateEnergyBreath(features: features, silentNow: silent)
        let speed = advancePen(dt: dt, features: features, silent: silent)
        advanceTurnDetection(dt: dt, silent: silent)
        advanceFlare(dt: dt, features: features)
        advanceContraction(dt: dt)
        emit(dt: dt, features: features, speed: speed)
        ageAndExpire(dt: dt)
        relax(dt: dt)
        reframe(dt: dt)
    }

    // MARK: - (a) Harmonic steer

    private func advanceHarmonicPhase(dt: Float, features: FeatureVector) {
        let alpha = dt / (tuning.phaseTau + dt)
        let raw = features.tonalPhaseFifths
        phaseSin += (sin(raw) - phaseSin) * alpha
        phaseCos += (cos(raw) - phaseCos) * alpha
        let homeAlpha = dt / (tuning.homeTau + dt)
        homeSin += (sin(raw) - homeSin) * homeAlpha
        homeCos += (cos(raw) - homeCos) * homeAlpha
        let phi = atan2(phaseSin, phaseCos)
        // Wrapped difference — the phase is circular, so a −π→+π step is a small move.
        var delta = phi - previousPhase
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        previousPhase = phi
        // NO second smoothing stage. φ̄ is ALREADY the CR.1.2-smoothed phase, and an extra
        // EMA on its signed rate cancels the reversals that carry the harmonic motion:
        // measured, it cut the phase travel from the design §2.3 figures (2.1 / 1.7 / 15.4
        // circles per 30 s) to 0.85 / 1.09 / 3.95, and the pen drew a straight line. The
        // derivative of an EMA-smoothed circular phase needs no further filtering.
        phaseRate = delta / dt
    }
}
