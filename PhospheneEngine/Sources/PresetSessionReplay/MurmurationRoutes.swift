// MurmurationRoutes.swift — Per-route specs for the audio-coupled flock.
//
// !!! STALE FOR THE SHIPPED PRESET — re-derive in MM.5 (design §13). !!!
// These three GLOBAL-envelope routes describe the RETIRED emergent Flock2
// substrate (`MurmurationFlock*`, `git rm`'d in 9056dc48). The shipped
// Murmuration is the 3D parametric-ellipse flock (`Murmuration3D.metal`), whose
// audio brain is the proven 2D preset's FOUR routes — bass → drift + elongation,
// drums → turning-wave / banding, other → flutter + curvature, vocals → density
// compression. The firing specs below must be re-derived against
// `murmuration3d_update` before the MM.5 firing-evidence report is trusted; they
// are kept only so the replay harness still loads. DO NOT cite this file's firing
// % as evidence for the shipped preset until MM.5 re-derives it.
//
// --- historical (retired emergent substrate) -------------------------------
// MM.6 musicality rethink (Matt 2026-06-03): drive the flock's GLOBAL envelope
// and let the rich structure (banking waves, feathered edge) EMERGE from the
// Flock2 substrate — three robust global couplings, not four fragile per-bird
// ones (the MM.3 per-bird drum-wave + mid-flutter were swallowed/inverted by the
// self-organizing substrate). Routes were in
// `MurmurationFlockGeometry.computeAudio(features:stemFeatures:dt:)`:
//
//   L1 — bass    → macro drift + envelope elongation (comma/ribbon)
//                  Driver: mix(f.bass_att_rel, stems.bass_energy_rel, stemMix)
//                  (continuous; "fires" = above-average bass present)
//   MV — maneuver → one coordinated heading-swing per BAR, energy-gated and
//                  drum-MODULATED (the banking wave emerges from the swing).
//                  Driver (amplitude): mix(f.bass_dev, stems.drums_energy_dev,
//                  stemMix) × the energy gate; the trigger is the bar downbeat.
//   L5 — vocals  → vertical dilation (breathing)
//                  Driver: stems.vocals_energy_dev × stemMix
//
// SR.1 measures routes at the INPUT layer: for each recorded frame, did the
// route's driver cross its firing gate, and what was the distribution?
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
                   + "anchor macro drift and the envelope elongation (comma/ribbon). "
                   + "Continuous primary driver — fires whenever bass runs above average.",
        inputName: "mix(f.bass_att_rel, stems.bass_energy_dev, stemMix)",
        gateThreshold: 0.20,
        partialGateThreshold: 0.50,
        inputValue: { frame in
            let mix = stemWarmupBlend(frame.totalStemEnergy)
            return frame.bassAttRel * (1 - mix) + frame.bassEnergyDev * mix
        }
    )

    /// MV — bar maneuver amplitude (the coordinated heading-swing; the banking
    /// wave emerges from it). The swing fires once per bar (trigger = barPhase01
    /// downbeat) with amplitude `drums_energy_dev × masterGate`; this reports the
    /// drums-deviation side that modulates how hard each bar swings. LO 0.30 =
    /// the maneuver becomes visible; HI 0.70 = strong-swing territory.
    public static let maneuver = RouteSpec(
        name: "MV — bar maneuver (heading-swing)",
        description: "mix(f.bass_dev, stems.drums_energy_dev, stemMix) modulates the per-bar "
                   + "coordinated heading-swing amplitude (the dark banking wave emerges from "
                   + "it). Bar-triggered + energy-gated so calm passages barely swing.",
        inputName: "mix(f.bass_dev, stems.drums_energy_dev, stemMix)",
        gateThreshold: 0.30,
        partialGateThreshold: 0.70,
        inputValue: { frame in
            let mix = stemWarmupBlend(frame.totalStemEnergy)
            return frame.bassDev * (1 - mix) + frame.drumsEnergyDev * mix
        }
    )

    /// L5 — vocals breathing (vertical dilation / the dark pulse). Stem-only
    /// (vocals are absent from the full-mix fallback); fires on vocal entries.
    public static let vocalsBreath = RouteSpec(
        name: "L5 — vocals → breathing",
        description: "stems.vocals_energy_dev × stemMix. Drives an active vertical spread so "
                   + "the mass dilates on vocal phrases (the McGill blackening↔dilution).",
        inputName: "stems.vocals_energy_dev × stemMix",
        gateThreshold: 0.20,
        partialGateThreshold: 0.50,
        inputValue: { frame in
            frame.vocalsEnergyDev * stemWarmupBlend(frame.totalStemEnergy)
        }
    )

    /// Murmuration's MM.6 route set (global-envelope couplings).
    public static let all: [RouteSpec] = [bassDrift, maneuver, vocalsBreath]
}
