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
//   (b) ADVANCE — bounded-curvature kinematics (Dubins 1957). The pen does not move TO a
//       harmonic position; it advances at a governed speed along a heading, and harmony
//       controls only how fast that heading turns. With fixed speed v and turn rate
//       clamped to ±v/R_min, every arc has radius ≥ R_min — so the pen cannot draw
//       anti-reference `10` (a ball of yarn IS a sequence of sub-pixel-radius reversals).
//       This is the rate governance WITCHLIGHT_DESIGN §2.3 item 3 requires as a mechanism:
//       the measured ~10× cross-track spread in the harmonic rate lives entirely in the
//       CURVATURE term, and curvature is clamped.
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
    public private(set) var heading: Float = 0
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
    private var deviationScale: Float = 0.3

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
    private var arousalSlow: Float = 0
    private var arousalSpread: Float = 0.15

    // Head flare.
    var bassDevSlow: Float = 0
    var flareRefractoryRemaining: Float = 0
    var flareGoal: Float = 0
    var flareHold: Float = 0
    /// Current flare amplitude, 0…`flareCeiling`. Bounded by the §5 budget.
    public internal(set) var flareIntensity: Float = 0
    /// Flare firings since `reset()`.
    public internal(set) var flareCount: Int = 0

    // Bar promotion.
    var previousBarPhase: Float = 0
    var promoteNextBead = false
    /// True on the single frame a bar wraps. WL.8 hoisted it out of `emit` because the
    /// flare now needs it too, and two independent wrap detectors would drift apart.
    var barDownbeatNow = false
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

    // View framing (a VIEW property, not a path property — see `advance`).
    public internal(set) var centroidX: Float = 0, centroidY: Float = 0
    public internal(set) var viewScale: Float = 1
    /// Where the camera AIMS — head-biased, NOT `centroid` (which only fits the scale). `reframe` says why.
    public internal(set) var cameraX: Float = 0, cameraY: Float = 0
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
    public private(set) var clampedFrameCount: Int = 0
    /// ∫|φ̄̇| dt — how far the smoothed harmonic phase travelled, radians. The design's
    /// §2.3 measurement quotes this as "circles over 30 s" (2.1 / 1.7 / 15.4 on the
    /// fixtures); reproducing it here is what proves the steer is reading the real driver.
    public private(set) var phaseTravel: Float = 0
    /// ∫|θ̇| dt — how far the PEN's heading actually turned, radians. `phaseTravel × k`
    /// before clamping; the gap between them is what the clamp removed.
    public private(set) var headingTravel: Float = 0
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
    public private(set) var headingNet: Float = 0
    public var headingMonotonicity: Float {
        headingTravel > 1e-4 ? abs(headingNet) / headingTravel : 0
    }
    public var clampedFraction: Float {
        frameCount > 0 ? Float(clampedFrameCount) / Float(frameCount) : 0
    }

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
        previousBarPhase = 0; promoteNextBead = false; promotionCount = 0
        barDownbeatNow = false; gridSilentFor = 0
        previousSectionIndex = nil; contractGoal = 0; contractHold = 0; contraction = 0
        sectionEventCount = 0
        centroidX = 0; centroidY = 0; viewScale = 1; rmsRadius = 0.4; cameraX = 0; cameraY = 0
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
        let bar = features.barPhase01
        barDownbeatNow = previousBarPhase > 0.85 && bar < 0.15
        previousBarPhase = bar
        if barDownbeatNow { promoteNextBead = true }
        gridSilentFor = bar > 0 ? 0 : gridSilentFor + dt

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

    // MARK: - (b) Bounded-curvature advance

    /// Returns the speed used this frame (world units/second).
    private func advancePen(dt: Float, features: FeatureVector, silent: Bool) -> Float {
        // Arousal against its own running spread — the per-track normalization the
        // measured 0.44–1.57 cross-capture range demands (§2.1).
        //
        // WL.2-i — 20 s → 12 s. Matt's M7: "it looks like the preset makes the same choices
        // about movement." Measured on his capture, the pen's speed varied by 13 % over the
        // whole track, and every sample sat ABOVE the base speed (norm +0.13…+0.64): the pen
        // never slowed down, it only ran fast and slightly faster. A 12 s reference lets the
        // deviation cross zero (norm −0.05…+0.55), so the stroke visibly slows as well as
        // quickens — which is what makes the coupling readable rather than merely present.
        //
        // Deliberately NOT slower. A 90 s reference was simulated first, on the theory that a
        // 20 s window chases the 10–60 s structure it should be measuring against; it makes
        // things worse, pinning two of the three fixtures at a permanently saturated +1 (0 %
        // swing) because the reference never catches up from the warm-up ramp.
        let slowAlpha = dt / (12.0 + dt)
        arousalSlow += (features.arousal - arousalSlow) * slowAlpha
        arousalSpread += (abs(features.arousal - arousalSlow) - arousalSpread) * slowAlpha
        // WL.8 — divisor 2 → 1.5. On Matt's 215 s session the realised swing was 1.42×,
        // against 2.55× on the 21 s fixtures and a gate floor of 1.45: the route passed on
        // material short enough to be dominated by the warm-up ramp and delivered almost
        // nothing on a real listen. The fix is NOT more `speedModDepth` — WL.2-i stopped at
        // 0.45 because lit-pixel share moves non-monotonically with it — the normaliser was
        // the limit. 1.5 gives 1.57× while saturating only 5.5 % of frames (1.0 gives 1.74×
        // but saturates 13.9 %, and bang-bang is not expressive); it is also where the
        // distinctness gate holds: at 1.0 the wider swing grew the trail, the auto-fit
        // zoomed out and distinct beads fell 20 → 4.
        let arousalNorm = max(-1, min(1, (features.arousal - arousalSlow) / (1.5 * max(arousalSpread, 0.05))))

        let energyGate = energyGateForSpeed(silent: silent)
        let speed = tuning.baseSpeed * (1 + tuning.speedModDepth * arousalNorm) * energyGate
        if !silent { speedMin = min(speedMin, speed); speedMax = max(speedMax, speed) }
        // ω_max derived from the speed so the ≥ 8 %-of-frame-height turning-radius bound
        // holds exactly at every speed, rather than only at the nominal one.
        let omegaMax = speed / max(tuning.minTurnRadius, 1e-4)

        // WL.3 SPIKE — three candidate steer models, selected by `tuning.steerMode`.
        // See WitchlightTuning.SteerMode for what each one maps to what.
        let desired: Float
        switch tuning.steerMode {
        case .turnRate:
            desired = silent ? 0 : tuning.steerGain * phaseRate
        case .curvature:
            desired = silent ? 0 : tuning.curvatureGain * smoothedPhase
        case .curvatureDeviation:
            // Per-track gain: scale the deviation against a running estimate of its own
            // magnitude so a track that barely leaves its tonal home still draws a figure.
            // See `WitchlightTuning.normaliseDeviationGain`.
            let deviation = phaseFromHome
            if tuning.normaliseDeviationGain {
                let alpha = dt / (4.0 + dt)
                deviationScale += (max(abs(deviation), 0.05) - deviationScale) * alpha
                let gain = 0.85 * omegaMax / max(0.05, deviationScale)
                desired = silent ? 0 : gain * deviation
            } else {
                desired = silent ? 0 : tuning.curvatureGain * deviation
            }
        }
        let turnRate = max(-omegaMax, min(omegaMax, desired))
        if !silent && abs(desired) >= omegaMax { clampedFrameCount += 1 }

        phaseTravel += abs(phaseRate) * dt
        headingTravel += abs(turnRate) * dt
        headingNet += turnRate * dt
        heading += turnRate * dt
        penX += speed * dt * cos(heading)
        penY += speed * dt * sin(heading)
        return speed
    }
}
