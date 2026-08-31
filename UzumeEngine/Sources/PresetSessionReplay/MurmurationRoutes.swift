// MurmurationRoutes.swift — Per-route firing specs for the shipped 3D Murmuration.
//
// Re-derived for MM.5 cert against the global-envelope coupling of the 3D
// parametric-ellipse flock (`Murmuration3D.metal` + `Murmuration3DGeometry`,
// design §13.5), replacing the retired emergent-Flock2 specs (9056dc48). The
// shipped coupling drives the flock's GLOBAL envelope, computed CPU-side in
// `Murmuration3DGeometry.advanceEnvelopes`:
//
//   ENERGY (PRIMARY) — rawEnergy = (drums + bass + other)/3 + 0.4·vocals, smoothed
//                      (EMA τ≈0.45 s), mapped energyNorm = (energyEnv − 0.18)/0.45.
//                      Drives the morph-clock PACE (vigor), the flock's SWELL +
//                      elongation, and the TRAVERSE range. The dominant continuous
//                      coupling — active whenever music plays.
//   BEAT (ACCENT)    — the drumsBeat pulse → a beat-GATED agitation/banking wave (a
//                      band banks together and a dark band sweeps across as the beat
//                      decays). Quiet passages carry no band.
//   VOCALS           — vocals energy, smoothed → density breathing (the flock
//                      tightens/darkens on vocal phrases).
//
// SR.1 measures firing at the INPUT layer. The recorded `SessionFrame` carries the
// per-stem energies + Dev primitives but NOT drumsBeat, so the beat route is
// measured via `stems.drums_energy_dev` (its faithful onset correlate) and the
// energy route via the rawEnergy reconstruction above (recorded sessions always
// have stems present, so the full-mix fallback path is not exercised here). Gates
// are sized to the measured driver ranges (stem energies ~0.30 mean / ~0.70 p99;
// Dev primitives near-zero, spiking to ~1–2.5 on events). Keep in sync with
// `Murmuration3DGeometry.advanceEnvelopes`.

import Foundation
import Shared

public enum MurmurationRouteSpecs {

    /// rawEnergy reconstruction = (drums + bass + other)/3 + 0.4·vocals — mirrors
    /// `Murmuration3DGeometry.advanceEnvelopes` (stems present in recorded sessions).
    private static func rawEnergy(_ frame: SessionFrame) -> Float {
        (frame.drumsEnergy + frame.bassEnergy + frame.otherEnergy) / 3 + 0.4 * frame.vocalsEnergy
    }

    /// PRIMARY — energy → vigor + swell + drift range. Continuous; the LO gate is the
    /// quiet floor where energyNorm starts driving (rawEnergy ≈ 0.27 ↔ energyNorm ≈
    /// 0.20), HI is the strong-response level (≈ 0.50 ↔ energyNorm ≈ 0.70).
    public static let energy = RouteSpec(
        name: "ENERGY → vigor + swell + drift (PRIMARY)",
        description: "rawEnergy = (drums+bass+other)/3 + 0.4·vocals, smoothed (τ≈0.45 s) → the "
                   + "morph-clock pace, the flock's swell/elongation, and the traverse range. "
                   + "The dominant continuous coupling — fires whenever music is playing.",
        inputName: "(drums+bass+other)/3 + 0.4·vocals",
        gateThreshold: 0.27,
        partialGateThreshold: 0.50,
        inputValue: { rawEnergy($0) }
    )

    /// ACCENT — beat → the beat-gated agitation/banking wave. The shader keys this on
    /// the drumsBeat pulse; `SessionFrame` lacks drumsBeat, so firing is measured via
    /// `drums_energy_dev` (the onset correlate). LO 0.20 = a noticeable hit, HI 0.50 =
    /// a strong hit driving a clear band sweep.
    public static let beatWave = RouteSpec(
        name: "BEAT → agitation/banking wave (ACCENT)",
        description: "drumsBeat pulse → a band banks together and a dark band sweeps across as "
                   + "the beat decays. Beat-gated (no band in quiet passages). Measured via "
                   + "stems.drums_energy_dev — drumsBeat itself is not recorded in SessionFrame.",
        inputName: "stems.drums_energy_dev (≈ drumsBeat onset)",
        gateThreshold: 0.20,
        partialGateThreshold: 0.50,
        inputValue: { $0.drumsEnergyDev }
    )

    /// SECONDARY — vocals → density breathing (the flock tightens/darkens on vocal
    /// phrases). Measured via `vocals_energy_dev` (fires on vocal entries).
    public static let vocalsDensity = RouteSpec(
        name: "VOCALS → density breathing",
        description: "vocals energy, smoothed → the flock tightens/darkens on vocal phrases. "
                   + "Measured via stems.vocals_energy_dev (fires on vocal entries).",
        inputName: "stems.vocals_energy_dev",
        gateThreshold: 0.20,
        partialGateThreshold: 0.50,
        inputValue: { $0.vocalsEnergyDev }
    )

    /// The shipped 3D Murmuration route set (global-envelope couplings, design §13.5).
    public static let all: [RouteSpec] = [energy, beatWave, vocalsDensity]
}
