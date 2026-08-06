// WitchlightPath+Pen — the bounded-curvature advance, mechanism (b) of WITCHLIGHT_DESIGN §3.1.
//
// Split out of `WitchlightPath.swift` at WL.9 for the 400-line lint budget.
//
// The pen does not move TO a harmonic position; it advances at a governed speed along a
// heading, and harmony controls only how fast that heading TURNS. With fixed speed v and
// turn rate clamped to ±v/R_min, every arc has radius >= R_min — so the pen cannot draw
// anti-reference `10` (a ball of yarn IS a sequence of sub-pixel-radius reversals). This is
// the rate governance §2.3 item 3 requires as a MECHANISM: the measured ~10x cross-track
// spread in the harmonic rate lives entirely in the CURVATURE term, and curvature is clamped.

import Foundation
import Shared

extension WitchlightPath {

    // MARK: - (b) Bounded-curvature advance

    /// Returns the speed used this frame (world units/second).
    func advancePen(dt: Float, features: FeatureVector, silent: Bool) -> Float {
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
        let spread = tuning.arousalSpreadDivisor * max(arousalSpread, 0.05)
        let arousalNorm = max(-1, min(1, (features.arousal - arousalSlow) / spread))

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
