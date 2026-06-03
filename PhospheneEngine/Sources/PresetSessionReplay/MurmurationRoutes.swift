// MurmurationRoutes.swift — Per-route specs for the MM.3 audio-coupled flock.
//
// Each route corresponds to one of the four audio→visual mappings ported from
// the original Particles.metal onto the boids substrate in
// `MurmurationFlockGeometry.computeAudio(features:stemFeatures:dt:)` (design
// §3.2). SR.1 measures routes at the INPUT layer: for each recorded frame, did
// the route's driver cross its firing gate, and what was the distribution?
//
//   L1 — bass   → macro drift + elongation
//                 Driver: mix(f.bass_att_rel, stems.bass_energy_rel, stemMix)
//                 (continuous; "fires" = above-average bass present)
//   L2 — drums  → orientation/banking wave (per-beat accent, energy-gated)
//                 Driver: mix(f.bass_dev, stems.drums_energy_dev, stemMix)
//   L4 — mid    → edge-weighted flutter
//                 Driver: mix(f.mid_att_rel, stems.other_energy_rel, stemMix)
//   L5 — vocals → density compression (breathing)
//                 Driver: stems.vocals_energy_dev × stemMix
//
// !!! GATE / BLEND CONSTANTS MIRROR THE CONFORMER !!!
// `stemMix = smoothstep(0.02, 0.06, totalStemEnergy)` (D-019) and the firing
// thresholds below mirror the effective drive points in
// MurmurationFlockGeometry.computeAudio. The recorded `SessionFrame` exposes the
// *Dev primitives (not *Rel); Dev = max(0, Rel), which is the firing-relevant
// half — the firing % is therefore a conservative read of each continuous
// route. Keep these in sync with the conformer (SR.2 will centralise).

import Foundation
import Shared

public enum MurmurationRouteSpecs {

    /// L1 — bass macro drift + elongation (the PRIMARY continuous driver).
    /// Reports how often above-average bass is present to drift/stretch the
    /// flock. Continuous (no hard gate); the 0.20 LO edge is "noticeably driving".
    public static let bassDrift = RouteSpec(
        name: "L1 — bass → drift + elongation",
        description: "mix(f.bass_att_rel, stems.bass_energy_dev, stemMix). Drives the "
                   + "roost macro drift and the guide-segment elongation (comma/ribbon). "
                   + "Continuous primary driver — fires whenever bass runs above average.",
        inputName: "mix(f.bass_att_rel, stems.bass_energy_dev, stemMix)",
        gateThreshold: 0.20,
        partialGateThreshold: 0.50,
        inputValue: { frame in
            let mix = stemWarmupBlend(frame.totalStemEnergy)
            return frame.bassAttRel * (1 - mix) + frame.bassEnergyDev * mix
        }
    )

    /// L2 — drum turning-wave (per-beat ACCENT, gated by the master energy lever).
    /// The curl wave amplitude is `drums_energy_dev × masterGate`; this reports
    /// the drums-deviation side. LO 0.30 = the wave becomes visible; HI 0.70 =
    /// strong-wave territory (matches the Aurora Veil drum-kink convention).
    public static let drumsWave = RouteSpec(
        name: "L2 — drums → orientation wave",
        description: "mix(f.bass_dev, stems.drums_energy_dev, stemMix). Fires the curl "
                   + "turning-wave (a rolling dark band) on drum transients. Energy-gated "
                   + "so calm passages stay wave-free.",
        inputName: "mix(f.bass_dev, stems.drums_energy_dev, stemMix)",
        gateThreshold: 0.30,
        partialGateThreshold: 0.70,
        inputValue: { frame in
            let mix = stemWarmupBlend(frame.totalStemEnergy)
            return frame.bassDev * (1 - mix) + frame.drumsEnergyDev * mix
        }
    )

    /// L4 — mid edge flutter. The recorded frame lacks `mid_att_rel`, so the
    /// stem "other" deviation (which dominates once stems arrive, stemMix≈1) is
    /// the measurable proxy. Fires when above-average mid/other energy shimmers
    /// the feathered edge.
    public static let midEdge = RouteSpec(
        name: "L4 — mid → edge flutter",
        description: "stems.other_energy_dev × stemMix (≈ the mix(f.mid_att_rel, "
                   + "stems.other_energy_rel, stemMix) driver once stems arrive). Adds "
                   + "edge-weighted shimmer to the feathered periphery.",
        inputName: "stems.other_energy_dev × stemMix",
        gateThreshold: 0.20,
        partialGateThreshold: 0.50,
        inputValue: { frame in
            frame.otherEnergyDev * stemWarmupBlend(frame.totalStemEnergy)
        }
    )

    /// L5 — vocals breathing (density compression / the dark pulse). Stem-only
    /// (vocals are absent from the full-mix fallback); fires on vocal entries.
    public static let vocalsBreath = RouteSpec(
        name: "L5 — vocals → breathing",
        description: "stems.vocals_energy_dev × stemMix. Tightens inter-bird spacing so "
                   + "the mass contracts on vocal phrases (the dark pulse).",
        inputName: "stems.vocals_energy_dev × stemMix",
        gateThreshold: 0.20,
        partialGateThreshold: 0.50,
        inputValue: { frame in
            frame.vocalsEnergyDev * stemWarmupBlend(frame.totalStemEnergy)
        }
    )

    /// Murmuration's MM.3 route set.
    public static let all: [RouteSpec] = [bassDrift, drumsWave, midEdge, vocalsBreath]
}
