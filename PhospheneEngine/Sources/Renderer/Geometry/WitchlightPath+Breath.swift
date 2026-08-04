// WitchlightPath+Breath.swift — the preset's one continuous-energy coupling.
//
// Split out of `WitchlightPath.swift` at WL.4 for the 400-line lint, and it earns a file:
// this is the route added because Witchlight had NO per-frame energy coupling at all, which
// is why four M7 rounds of real fixes never touched "not synced to the music".

import Foundation
import Shared

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
}
