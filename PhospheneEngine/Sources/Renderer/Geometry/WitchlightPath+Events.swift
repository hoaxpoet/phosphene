// WitchlightPath+Events — the discrete and per-frame side effects of the pen's motion.
//
// Split out of `WitchlightPath.swift` to keep both files inside the 400-line lint budget.
// This half owns everything that is NOT the steer-and-advance integrator: the head flare,
// the section contraction, bead emission, ageing/expiry, relaxation and view framing.
//
// The members here are `internal` rather than `private` purely because a Swift extension
// in a second file cannot reach file-private state; nothing outside this module touches them.

import Foundation
import Shared

extension WitchlightPath {

    // MARK: - Head flare

    func advanceFlare(dt: Float, features: FeatureVector) {
        flareRefractoryRemaining = max(0, flareRefractoryRemaining - dt)
        // Running reference rather than a fixed level: `bassDev` measures p95 0.12–0.31
        // and max 0.30–3.92 across the four §2 captures, so a constant trigger would fire
        // continuously on one track and never on another (the fault in source trait #9).
        let devAlpha = dt / (8.0 + dt)
        bassDevSlow += (features.bassDev - bassDevSlow) * devAlpha
        let trigger = max(bassDevSlow * 2.5, 0.03)
        if features.bassDev > trigger && flareRefractoryRemaining <= 0 {
            flareRefractoryRemaining = tuning.flareRefractory
            flareGoal = tuning.flareCeiling
            flareHold = 0.05
            flareCount += 1
        }
        flareHold -= dt
        if flareHold <= 0 { flareGoal = 0 }
        let tau = flareGoal > flareIntensity ? tuning.flareRiseTau : tuning.flareFallTau
        flareIntensity += (flareGoal - flareIntensity) * (dt / (tau + dt))
        flareIntensity = max(0, min(tuning.flareCeiling, flareIntensity))
    }

    // MARK: - Section contraction

    func advanceContraction(dt: Float) {
        contractHold -= dt
        if contractHold <= 0 { contractGoal = 0 }
        // ~0.4 s in, ~4 s back out (§3.2).
        let tau: Float = contractGoal > contraction ? 0.15 : 1.40
        contraction += (contractGoal - contraction) * (dt / (tau + dt))
        trailWindow = tuning.trailSeconds * (1 - 0.30 * contraction)
    }

    // MARK: - Emission

    func emit(dt: Float, features: FeatureVector, speed: Float) {
        // Bar downbeat: promote the bead emitted at that instant. Wrap detection follows
        // `LumenPatternEngine.updateBandCounters`; `barPhase01` measured a clean sawtooth
        // on all four §2 captures.
        let bar = features.barPhase01
        if previousBarPhase > 0.85 && bar < 0.15 { promoteNextBead = true }
        previousBarPhase = bar

        // WL.2-i — emit per DISTANCE travelled, not per unit time.
        //
        // `emissionHz` was calibrated at WL.2-f as `speed / (1.2 × 2 × baseRadius)`, i.e. to
        // put beads 1.2 diameters apart — but only while the pen runs at exactly `baseSpeed`.
        // Spacing is `speed / emissionHz`, so a time-based emitter silently ties the ribbon's
        // whole texture to the speed never changing. The moment WL.2-i made the speed route
        // visibly responsive (Matt: "the same choices about movement"), that assumption broke
        // in both directions: at 0.55× the beads closed to 0.66 diameters and fused into the
        // uniform tube of anti-reference `11`, and at 1.45× they opened to 1.74 and dotted.
        // Rendering it made this obvious — a short fat caterpillar of overlapping blobs.
        //
        // Accumulating distance instead pins the spacing at the value WL.2-f settled,
        // whatever the pen is doing. This is not a new look: at `baseSpeed` the two emitters
        // are identical by construction (`speed·dt / (baseSpeed/emissionHz)` reduces to
        // `dt·emissionHz`), so the approved texture is preserved and only its dependence on
        // speed is removed. It is also the more physical model — a burning tip sheds sparks
        // along its PATH, not along the clock.
        let spacing = tuning.baseSpeed / max(tuning.emissionHz, 1)
        emitAccumulator += speed * dt
        var emitted = 0
        while emitAccumulator >= spacing && emitted < 8 {
            emitAccumulator -= spacing
            emitted += 1
            appendBead()
        }
    }

    func appendBead() {
        var bead = WitchlightBead()
        bead.posX = penX
        bead.posY = penY
        bead.posZ = 0                      // the stroke is drawn IN the plane; the plane tumbles
        let rgb = Self.hsvToRGB(hue: hueForPhase(smoothedPhase), saturation: 0.80, value: 1.0)
        bead.colR = rgb.x; bead.colG = rgb.y; bead.colB = rgb.z
        if promoteNextBead {
            bead.promoted = 1
            promoteNextBead = false
            promotionCount += 1
        }
        if beads.count >= capacity { beads.removeFirst() }
        beads.append(bead)
    }

    /// Hue from the smoothed harmonic phase. Both quantities are circular, so the map
    /// wraps with no seam (D-178: relationships, never labels; hue, never brightness).
    func hueForPhase(_ phase: Float) -> Float {
        let base = phase / (2 * .pi) + 0.5 + hueTurnOffset
        return base - floor(base)
    }

    // MARK: - Ageing and expiry

    func ageAndExpire(dt: Float) {
        for index in beads.indices { beads[index].age += dt }
        // Oldest-first ordering means expiry is a prefix drop.
        var expired = 0
        while expired < beads.count && beads[expired].age > trailWindow { expired += 1 }
        if expired > 0 { beads.removeFirst(expired) }
    }

    // MARK: - (c) Age-weighted relaxation

    /// Jacobi Laplacian smoothing with an age-decaying weight. Beads past `relaxZeroAge`
    /// are frozen — "a drawing of where the song has been" is false if the drawing keeps
    /// rewriting itself.
    func relax(dt: Float) {
        guard beads.count >= 3 else { return }
        let full = tuning.relaxFullAge
        let zero = max(tuning.relaxZeroAge, full + 0.001)
        // Rate × dt, so the total smoothing a bead receives over its mutable life is the
        // same at 43 fps (the fixtures) and 60 fps (live) — a per-frame constant silently
        // smooths 40 % harder on the faster machine.
        let rate = tuning.relaxLambda * dt
        var updated = beads
        for index in 1..<(beads.count - 1) {
            let age = beads[index].age
            if age >= zero { continue }
            let weight = age <= full ? 1 : 1 - (age - full) / (zero - full)
            let lambda = min(0.5, rate * weight)
            let midX = 0.5 * (beads[index - 1].posX + beads[index + 1].posX)
            let midY = 0.5 * (beads[index - 1].posY + beads[index + 1].posY)
            updated[index].posX += lambda * (midX - beads[index].posX)
            updated[index].posY += lambda * (midY - beads[index].posY)
        }
        beads = updated
    }

    // MARK: - Framing

    /// Follow the trail's centroid and auto-fit its extent.
    ///
    /// A VIEW property, deliberately separate from the path: bounded-curvature kinematics
    /// give a figure whose extent depends on how much the track's harmony moved, so a
    /// fixed camera would frame `01` on one track and a speck on the next. The figure is
    /// music-driven; the framing only keeps it legible and small-in-frame (trait #7).
    ///
    /// WL.7 — the SCALE and the CAMERA are computed from different points, and separating
    /// them is the whole fix for "still not tied to the music".
    ///
    /// Measured (`WitchlightHeadFramingTests`, CPU mirror of `wl_project`): with one shared
    /// centre, the burning head was **off frame on 33 / 35 / 45 % of frames** across the
    /// three fixtures, and outside a 0.9 inset on 40–48 %. That is where every coupling
    /// this preset has actually shows — the flare fires at the head, the newest beads are
    /// the brightest, and the WL.4 breath and WL.5 energy gate both read strongest there.
    /// Roughly two frames in five, the music was driving something the viewer could not
    /// see. Matt's sixth M7 said exactly this ("the ribbon is moving faster than the camera
    /// can catch up") and it was right.
    ///
    /// It happens by construction, not by mis-tuning: the pen advances continuously, so the
    /// head sits at the LEADING EXTREME of the trail while the fit is an RMS radius (~0.6 of
    /// true extent for a roughly linear stroke). With `framedRadius` 0.62 the furthest bead
    /// lands at ≈ 1.03 of the half-frame — just outside — and the head is nearly always the
    /// furthest bead.
    ///
    /// The three WL.6 attempts all tried to fix it by fitting MORE into frame (max-extent
    /// fit, `framedRadius` up to 0.86), which shrinks the drawing, and the WL.2-j
    /// distinctness gate correctly killed all three (23 → 4 distinct beads). This does the
    /// opposite: `viewScale` is left EXACTLY as it was — the drawing's size in frame, and so
    /// bead legibility, is unchanged bit-for-bit — and only the point the camera aims at
    /// moves. The trail's true centroid still sets the scale; the camera sits 60 % of the
    /// way toward the head on a 1.2 s follow.
    ///
    /// Swept over bias × follow on all three fixtures: 0.6 / 1.2 s is the first cell that
    /// reaches 0.0 % head-off-frame on every one. What it costs is the far TAIL — 30 s-old
    /// beads, frozen and dim — leaving frame: bead-frames off screen go 6.0 → 16.6 % on
    /// `so_what`, and IMPROVE on the other two (5.2 → 0.7 %, 14.0 → 11.0 %). Trading the
    /// oldest, dimmest end of the record for the burning tip is the right trade: the tail is
    /// where the music has already been, the head is where it is now.
    func reframe(dt: Float) {
        guard !beads.isEmpty else { return }
        var sumX: Float = 0, sumY: Float = 0
        for bead in beads { sumX += bead.posX; sumY += bead.posY }
        let count = Float(beads.count)
        let targetX = sumX / count, targetY = sumY / count
        let followAlpha = dt / (3.0 + dt)
        centroidX += (targetX - centroidX) * followAlpha
        centroidY += (targetY - centroidY) * followAlpha

        var sumSquares: Float = 0
        for bead in beads {
            let dx = bead.posX - centroidX, dy = bead.posY - centroidY
            sumSquares += dx * dx + dy * dy
        }
        let targetRadius = (sumSquares / count).squareRoot()
        let fitAlpha = dt / (4.0 + dt)
        rmsRadius += (targetRadius - rmsRadius) * fitAlpha
        viewScale = max(0.25, min(4.0, tuning.framedRadius / max(rmsRadius, 0.02)))

        // The camera. Head-biased so the burning tip stays in frame, on a follow short
        // enough to keep up with a pen that quickens 2.5× (WL.2-i) — at 3 s it cannot,
        // which is the lag Matt saw.
        guard let head = beads.last else { return }
        let camAlpha = dt / (1.2 + dt)
        let aimX = centroidX * (1 - 0.6) + head.posX * 0.6
        let aimY = centroidY * (1 - 0.6) + head.posY * 0.6
        cameraX += (aimX - cameraX) * camAlpha
        cameraY += (aimY - cameraY) * camAlpha
    }

    // MARK: - Colour helper

    /// HSV → RGB. Local rather than shared because the hue is frozen into the bead at
    /// emission — the GPU never sees a hue, only a colour.
    static func hsvToRGB(hue: Float, saturation: Float, value: Float) -> SIMD3<Float> {
        let scaled = (hue - floor(hue)) * 6
        let sector = Int(scaled) % 6
        let fraction = scaled - Float(Int(scaled))
        let down = value * (1 - saturation)
        let falling = value * (1 - saturation * fraction)
        let rising = value * (1 - saturation * (1 - fraction))
        switch sector {
        case 0:  return SIMD3(value, rising, down)
        case 1:  return SIMD3(falling, value, down)
        case 2:  return SIMD3(down, value, rising)
        case 3:  return SIMD3(down, falling, value)
        case 4:  return SIMD3(rising, down, value)
        default: return SIMD3(value, down, falling)
        }
    }

    // MARK: - Turn detection (moved from WitchlightPath.swift at WL.4 for the 400-line lint;
    // a confirmed direction change is a discrete EVENT, so this file is its natural home)

    func advanceTurnDetection(dt: Float, silent: Bool) {
        guard !silent else { turnCandidateAge = 0; return }
        let sign: Float = phaseRate > 0.02 ? 1 : (phaseRate < -0.02 ? -1 : 0)
        guard sign != 0 else { turnCandidateAge = 0; return }
        if sign != turnSign {
            if sign == turnCandidateSign {
                turnCandidateAge += dt
                if turnCandidateAge >= tuning.turnConfirmSeconds {
                    confirmTurn(newSign: sign)
                }
            } else {
                turnCandidateSign = sign
                turnCandidateAge = 0
                // Remember the apex so the hue step lands where the stroke actually
                // turned, not where the reversal was confirmed 0.25 s later.
                turnCandidateBeadIndex = beads.count
            }
        } else {
            turnCandidateAge = 0
        }
    }
}
