// WitchlightPath+Events — the discrete and per-frame side effects of the pen's motion.
//
// Split out of `WitchlightPath.swift` to keep both files inside the 400-line lint budget.
// This half owns everything that is NOT the steer-and-advance integrator: the head flare,
// the section contraction, bead emission, ageing/expiry and relaxation. View framing moved
// to `WitchlightPath+Framing.swift` at WL.10 for the 400-line lint.
//
// The members here are `internal` rather than `private` purely because a Swift extension
// in a second file cannot reach file-private state; nothing outside this module touches them.

import Foundation
import Shared

extension WitchlightPath {

    // MARK: - Head flare — the thing that lands ON the beat (WL.8)

    /// Fire the head flare on the BAR DOWNBEAT, not on a bass excursion.
    ///
    /// Matt after WL.7: *"Ribbon feels connected to the music, though how is not obvious."*
    /// Measured on his session `2026-08-05T21-48-13Z` (`WitchlightBeatAlignmentProbe`), the
    /// old `bassDev` trigger fired 110 times in 215 s with a **mean offset of 0.250 beats**
    /// from the nearest beat — 0.25 is exactly the value uniformly-random firing produces,
    /// and 19 % landed within 10 % of a beat against a 20 % chance rate. The one thing in
    /// this preset that flashed in TIME had no relationship to the rhythm whatsoever.
    ///
    /// Everything else here is on a continuous envelope, which is why it reads as connected;
    /// nothing landed on the pulse, which is why "how" was invisible. The beat data was
    /// never missing — the grid locked at 171 BPM in 4/4, and 140 of 141 downbeats already
    /// promoted a bead. But a promoted bead is a mark in SPACE: it records where the downbeat
    /// happened and then drifts away with the trail. Nothing happened at the MOMENT.
    ///
    /// Per bar, not per beat, and that is Matt's call from the measured rates: at 171 BPM a
    /// beat is 0.35 s, so a per-beat head flash is ~2.9/s — strobe territory, and the §5
    /// flash budget would cap the amplitude until each pulse landed soft. A bar is 1.40 s
    /// (0.71/s), which leaves the full `flareCeiling` usable.
    ///
    /// One primitive per visual layer (FA #67): this REPLACES `bassDev` on the head rather
    /// than joining it. Two accent primitives on one layer is the documented "fighting
    /// itself" bug, and the one being removed was measurably noise against the rhythm.
    /// `bassDev` survives only as the no-grid fallback below.
    func advanceFlare(dt: Float, features: FeatureVector) {
        flareRefractoryRemaining = max(0, flareRefractoryRemaining - dt)
        offBeatRefractoryRemaining = max(0, offBeatRefractoryRemaining - dt)

        // No BeatGrid → `barPhase01` is pinned at 0 and never wraps, so the bar route is
        // silently dead. Fall back to the pre-WL.8 bass-excursion trigger rather than
        // leaving those tracks with no accent at all. One primitive at a time, never both.
        let gridActive = gridSilentFor < 2.0

        // Cold-start suppression, implemented HERE because the phase contract says presets
        // that need it implement it themselves. The cached grid installs with reliable BPM
        // and meter but possibly WRONG PHASE, so the first bars can fire off-beat — and an
        // accent that is wrong exactly when the viewer is forming their first impression is
        // worse than no accent. Ramped, not switched: a hard cut-in at 8 s is its own event.
        //
        // Applies ONLY to the grid route: the fallback keys off a bass excursion, which has
        // no phase to be wrong about, so suppressing it buys nothing. Scoping it this way
        // also fixes a live hazard — `trackElapsedS` is populated by `MIRPipeline`, and any
        // path that leaves it at 0 (every synthetic harness did) would otherwise suppress
        // EVERY flare forever, silently, on a route that looks correct in code.
        let warm = gridActive ? smoothstepUnit(features.trackElapsedS, 2.0, 8.0) : 1
        let devAlpha = dt / (8.0 + dt)
        bassDevSlow += (features.bassDev - bassDevSlow) * devAlpha
        // WL.9 — TWO TIERS. Matt's call after WL.8 read "too polite": every beat pulses, the
        // downbeat harder. It is also the more robust routing, and that was HIS observation:
        // the steady pulse now rides the BEAT grid, which is the strong signal, while only
        // the ACCENT rides bar position, which is the weak one (four levers failed to recover
        // bar position from the downbeat activation stream, odd meters worst). If the meter is
        // wrong the pulse is still right and only the emphasis lands on the wrong beat —
        // where WL.8's bar-only routing would have had everything wrong at once.
        //
        // Rate is why this is tempo-gated rather than unconditional. WL.8's "once per bar"
        // was chosen off a 171 BPM track where a bar is 1.40 s (0.71 pulses/s); the same
        // choice on his 80.5 BPM session is a bar every 2.98 s — 0.34/s, one flash per 3.3
        // seconds, which is the whole of "too polite". Per-beat at 80.5 BPM is 1.34/s; at
        // 171 BPM it would be 2.85/s, which is flicker. So off-beats run only when the beat
        // is long enough to read as a pulse.
        let beatSeconds = barPeriod > 0 ? barPeriod / max(features.beatsPerBar, 1) : 0
        let offBeatsAllowed = beatSeconds >= tuning.offBeatMinBeatSeconds

        let fires: Bool
        if gridActive {
            fires = barDownbeatNow
        } else {
            // Running reference rather than a fixed level: `bassDev` measures p95 0.12–0.31
            // and max 0.30–3.92 across the four §2 captures, so a constant trigger would fire
            // continuously on one track and never on another (the fault in source trait #9).
            fires = features.bassDev > max(bassDevSlow * 2.5, 0.03)
        }

        if fires && flareRefractoryRemaining <= 0 && warm > 0.01 {
            flareRefractoryRemaining = tuning.flareRefractory
            flareGoal = tuning.flareCeiling * warm
            flareHold = 0.05
            flareCount += 1
        } else if gridActive && offBeatsAllowed && beatEdgeNow && !barDownbeatNow
                    && offBeatRefractoryRemaining <= 0 && warm > 0.01 {
            // The dimmer tier. It does NOT touch `flareRefractoryRemaining`, so an off-beat
            // pulse can never delay or suppress the next downbeat burst — the bar line is
            // the event that has to be reliable.
            offBeatRefractoryRemaining = tuning.offBeatRefractory
            flareGoal = tuning.flareCeiling * tuning.offBeatShare * warm
            flareHold = 0.05
            offBeatCount += 1
        }
        flareHold -= dt
        if flareHold <= 0 { flareGoal = 0 }
        let tau = flareGoal > flareIntensity ? tuning.flareRiseTau : tuning.flareFallTau
        flareIntensity += (flareGoal - flareIntensity) * (dt / (tau + dt))
        flareIntensity = max(0, min(tuning.flareCeiling, flareIntensity))
    }

    /// Hermite ramp, 0 below `lo` and 1 above `hi`. Local rather than shared — the one
    /// caller is right here and `Shared` has no Float smoothstep.
    func smoothstepUnit(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
        let edge = max(0, min(1, (x - lo) / max(hi - lo, 1e-4)))
        return edge * edge * (3 - 2 * edge)
    }

    // MARK: - Section contraction

    func advanceContraction(dt: Float) {
        contractHold -= dt
        if contractHold <= 0 { contractGoal = 0 }
        // ~0.4 s in, ~4 s back out (§3.2).
        let tau: Float = contractGoal > contraction ? 0.15 : 1.40
        contraction += (contractGoal - contraction) * (dt / (tau + dt))
        contractionPeak = max(contractionPeak, contraction)
        trailWindow = tuning.trailSeconds * (1 - 0.30 * contraction)
    }

    // MARK: - Emission

    func emit(dt: Float, features: FeatureVector, speed: Float) {
        // The downbeat that sets `promoteNextBead` is detected in `advance` (WL.8) — the
        // flare needs the same edge, and two wrap detectors would eventually disagree.

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

    // MARK: - Turn confirmation
    //
    // WL.8: moved here from WitchlightPath.swift, by the same reasoning the file header
    // already gives for `advanceTurnDetection` — a confirmed direction change is a discrete
    // EVENT. It was left behind when its sibling moved at WL.4.

    func confirmTurn(newSign: Float) {
        turnSign = newSign
        turnCandidateAge = 0
        turnCount += 1
        hueTurnOffset += tuning.turnHueStep
        // Retro-apply the step to the beads laid since the apex (≤ ~9 beads) so the
        // boundary in the ribbon coincides with the corner in the figure.
        if let apex = turnCandidateBeadIndex, apex < beads.count {
            for index in apex..<beads.count {
                let rgb = Self.hsvToRGB(hue: hueForPhase(smoothedPhase), saturation: 0.80, value: 1.0)
                beads[index].colR = rgb.x
                beads[index].colG = rgb.y
                beads[index].colB = rgb.z
            }
        }
        turnCandidateBeadIndex = nil
    }
}
