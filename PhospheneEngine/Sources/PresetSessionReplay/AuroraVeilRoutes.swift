// AuroraVeilRoutes.swift — Per-route specs for the AV.2.h.1 three-channel
// Aurora Veil shader.
//
// Each route here corresponds to one of the three audio→visual mappings in
// `AuroraVeil.metal` after the AV.2.h Three-Channel curation (2026-05-19):
//
//   Route 1 — Vocals melody  → ribbon HUE
//             Gate: `stems.vocals_pitch_confidence > 0.5`
//             Source: `AuroraVeilState.tick(...)` only updates the
//             smoothed-pitch ring when confidence ≥ 0.5. Below the gate,
//             smoothedPitchNorm decays toward the neutral 0.5 baseline.
//             SR.1 measures the GATE (confidence ≥ 0.5) since that is the
//             empirical "does the route ever fire" question PT.1 surfaced.
//
//   Route 2 — Bass transients → BRIGHTNESS pulse
//             Gate: smoothstep(0.30, 0.55, bassDev)
//             Source: AuroraVeil.metal:515.
//             bassDev is `mix(f.bass_dev, stems.bass_energy_dev, stemMix)`
//             with `stemMix = smoothstep(0.02, 0.06, totalStemEnergy)`.
//
//   Route 5 — Drum events    → curtain KINK
//             Gate: smoothstep(0.70, 1.00, drums_energy_dev)
//             Source: AuroraVeilState.swift:82-83 (AV.2.h.1 tuning).
//             The shader reads kinkAccumulator from buffer(6); the gate is
//             evaluated CPU-side in AuroraVeilState.tick(...).
//
// !!! GATE CONSTANTS DUPLICATED FROM SHADER / STATE FILES !!!
// These must stay in sync with the corresponding constants in:
//   - AuroraVeil.metal (kBrightnessGateLo / Hi, line 175-176)
//   - AuroraVeilState.swift (kinkChargeLo / Hi, line 82-83)
//   - AuroraVeilState.swift (pitchConfidenceGate, line 99)
// SR.2 will centralize these in a single Swift declaration shared across
// shader binding + replay tooling; for SR.1 the duplication is documented
// here and enforced by code review.

import Foundation
import Shared

public enum AuroraVeilRouteSpecs {

    /// Vocal pitch confidence gate (Route 1).
    ///
    /// Reads `stems.vocals_pitch_confidence`. Reports the % of frames where
    /// confidence ≥ 0.5 — the empirical "does the route ever fire" question
    /// that PT.1 surfaced (route was 0% across multiple closeouts I authored).
    public static let vocalsPitch = RouteSpec(
        name: "Route 1 — vocals melody → hue",
        description: "Vocal pitch confidence gate. AuroraVeilState only updates "
                   + "smoothedPitchNorm when confidence ≥ 0.5. Below the gate, "
                   + "pitchNorm decays to the neutral 0.5 baseline.",
        inputName: "stems.vocals_pitch_confidence",
        gateThreshold: 0.5,
        partialGateThreshold: nil,
        inputValue: { $0.vocalsPitchConfidence }
    )

    /// Bass brightness pulse gate (Route 2).
    ///
    /// Replicates `mix(f.bass_dev, stems.bass_energy_dev, stemMix)` from the
    /// shader (AuroraVeil.metal:398), then reports the firing rate at both
    /// the LO edge (0.30 — brightness begins to lift) and the HI edge (0.55
    /// — brightness reaches full kBrightnessAmp).
    public static let bassBrightness = RouteSpec(
        name: "Route 2 — bass transients → brightness pulse",
        description: "smoothstep(0.30, 0.55, bassDev). bassDev is the stem-warmup "
                   + "blend of f.bass_dev and stems.bass_energy_dev. Below 0.30 the "
                   + "brightness stays at base 0.85; above 0.55 it reaches +0.30.",
        inputName: "mix(f.bass_dev, stems.bass_energy_dev, stemMix)",
        gateThreshold: 0.30,
        partialGateThreshold: 0.55,
        inputValue: { frame in
            let mix = stemWarmupBlend(frame.totalStemEnergy)
            return frame.bassDev * (1 - mix) + frame.bassEnergyDev * mix
        }
    )

    /// Drum kink gate (Route 5, AV.2.h.1 tuning 0.7/1.0).
    ///
    /// Reads `stems.drums_energy_dev` directly. The CPU-side
    /// `AuroraVeilState.tick(...)` evaluates `smoothstep(0.7, 1.0, drumsDev)`
    /// and accumulates the result into kinkAccumulator. SR.1 reports the
    /// firing rate at the LO and HI gate edges.
    public static let drumsKink = RouteSpec(
        name: "Route 5 — drum events → curtain kink",
        description: "smoothstep(0.70, 1.00, stems.drums_energy_dev). AV.2.h.1 (2026-05-20) "
                   + "tuning from 0.9/1.5 → 0.7/1.0 after the prior gate fired 0% on Billie Jean. "
                   + "Target firing rate: ~0.7% on light-drum music, ~2-3% on heavy-drum.",
        inputName: "stems.drums_energy_dev",
        gateThreshold: 0.70,
        partialGateThreshold: 1.00,
        inputValue: { $0.drumsEnergyDev }
    )

    /// Aurora Veil's three-channel route set (post AV.2.h curation).
    public static let all: [RouteSpec] = [vocalsPitch, bassBrightness, drumsKink]
}
