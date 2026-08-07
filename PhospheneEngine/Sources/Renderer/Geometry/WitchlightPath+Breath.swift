// WitchlightPath+Breath.swift — the preset's one continuous-energy coupling.
//
// Split out of `WitchlightPath.swift` at WL.4 for the 400-line lint, and it earns a file:
// this is the route added because Witchlight had NO per-frame energy coupling at all, which
// is why four M7 rounds of real fixes never touched "not synced to the music".

import Foundation
import Shared

// MARK: - Pre-analysed tonal home (WL.13)

extension WitchlightPath {

    /// Install the track's tonal centre, measured ahead of playback.
    ///
    /// `SessionPreparer` already runs the full `MIRPipeline` over each preview clip, so the
    /// circular mean of `tonal_phase_fifths` for a track is known BEFORE its first frame
    /// (`TrackProfile.tonalHomeFifths`). Handing it over means the pen never has to learn
    /// home from a 12 s running mean seeded at 0 rad — the ~30 s convergence that drew a coil
    /// over the whole visible trail at the start of every track (WL.13).
    ///
    /// Delivered through the CPU-only runtime bridge, the same route `sectionIndex` and
    /// `beatDriftSeconds` take: it is a per-TRACK scalar that never reaches a shader, so it
    /// needs no `FeatureVector` field and breaks no MSL layout contract.
    ///
    /// Call AFTER `reset()` — reset clears it, because a home carried across a track boundary
    /// is the previous song's key and would steer the new one confidently wrong.
    public func ingestTonalHome(radians: Float) {
        homeSin = sin(radians)
        homeCos = cos(radians)
        homeIsPreAnalysed = true
    }
}

// MARK: - Energy breath (WL.4)

extension WitchlightPath {

    /// The preset's only per-frame energy coupling, 0…1 centred on 0.5.
    ///
    /// Matt's fourth M7: *"not synced to the music. failure."* Measured against that session,
    /// every one of Witchlight's eight routes ran on a 1–30 s, 10–60 s, per-bar or per-section
    /// envelope, and `bass` / `mid` / `treble` / `bassRel` / `mid_dev` / `treb_dev` were all
    /// alive and all routed to **nothing**. CLAUDE.md's most important design rule is that
    /// continuous energy is the DEFAULT PRIMARY DRIVER and is what makes a visual feel locked
    /// to the music; Witchlight was the one preset with none. So when a listener heard
    /// something happen, nothing on screen happened — which is the complaint, exactly.
    ///
    /// `bassAtt` rather than `bassDev`: measured on that session `bassDev` sits at zero and
    /// spikes (p50 0.000, nonzero 48.8 %), which is an ACCENT signal and is already spoken for
    /// by the head flare, while `bassAtt` is continuously alive (nonzero 97.4 %, p50 0.258,
    /// range 0.43) — the difference between a thing that fires and a thing that breathes.
    /// Distinct primitive, distinct layer, so FA #67 holds.
    ///
    /// Normalised against its own running level (D-026): the absolute value is AGC-dependent
    /// and means different things on different mixes, so an absolute mapping would be FA #31
    /// wearing a different name.
    func updateEnergyBreath(features: FeatureVector, silentNow: Bool) {
        let dt = max(features.deltaTime, 1.0 / 240)
        // ~3 s reference: long enough that a bar's worth of loud does not become "normal",
        // short enough to follow a section change.
        let alpha = dt / (3.0 + dt)
        let value = features.bassAtt
        breathSlow += (value - breathSlow) * alpha
        breathSpread += (abs(value - breathSlow) - breathSpread) * alpha
        let norm = (value - breathSlow) / (2 * max(breathSpread, 0.02))
        energyBreath = 0.5 + 0.5 * max(-1, min(1, norm))
        if !silentNow {
            breathMin = min(breathMin, energyBreath)
            breathMax = max(breathMax, energyBreath)
        }
    }

    /// WL.5 — the pen only draws while there is sound to draw.
    ///
    /// Matt's fifth M7: *"the witchlight pattern is still moving when the preset is idle,
    /// indicating that there is no real beat sync / connection to the music."* He was right,
    /// and it was DESIGNED that way — §3.6 specified "the pen continues to advance at `v₀` …
    /// silence reads as the pen still moving, with nothing to say, which is the honest visual
    /// for it", and `silent` zeroed only the TURN rate, never the speed.
    ///
    /// That reasoning does not survive a viewer. A stroke that advances at the same rate with
    /// and without music is, to anyone watching, a stroke that is not listening — and no
    /// coupling elsewhere can outvote it, because the drawing itself is the subject. This is
    /// the most legible connection the preset can have: the line grows when you hear
    /// something and holds when you do not.
    ///
    /// CONTINUOUS, and CENTRED so that typical energy means NORMAL speed. `energyBreath` is
    /// centred on 0.5, so using it raw multiplied every speed by ~0.5 on average — measured,
    /// that cut the 30 s trail from 96 beads to 71 and dropped ribbon share below its floor.
    /// The gate must change WHEN the pen draws, not how much it draws overall, so
    /// `0.25 + 1.5·b` puts breath 0.5 at exactly 1.0 and spans 0.25…1.75.
    ///
    /// The tangle guard holds at the top of that range by construction: `omegaMax` is derived
    /// from `speed`, so a faster pen gets a proportionally higher turn-rate ceiling and the
    /// ≥ 8 %-of-frame-height minimum radius survives (anti-reference `10`).
    ///
    /// D-037 is unaffected: silence still renders the star field, the bloom and the whole
    /// existing ribbon. D-037 forbids a BLACK frame, not a still one.
    func energyGateForSpeed(silent: Bool) -> Float {
        silent ? 0 : min(tuning.energyGateCap, tuning.energyGateFloor + tuning.energyGateSpan * energyBreath)
    }
}
