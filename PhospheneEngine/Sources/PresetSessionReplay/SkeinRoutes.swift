// SkeinRoutes.swift — Per-route firing specs for the Skein.3 painterly preset.
//
// Skein.3's §5.4 routing is consumed in SkeinState (per-stem onset → splatter burst, dominant
// stem → pour-line colour, broadband energy → painter speed). SR.1 measures firing at the INPUT
// layer from the recorded `SessionFrame`, which carries per-stem energy + the `*_energy_dev`
// deviation primitives (D-026) + vocal pitch — but NOT spectral centroid or attackRatio. So the
// two CHARACTER routes (viscosity ← centroid, flick sharpness ← attackRatio) are NOT measurable
// via SR.1; this file registers the load-bearing STRUCTURAL + PRIMARY couplings that the recorded
// frame can measure, and the closeout states the character routes as "not SR.1-measurable" rather
// than asserting them (the PT.1 rule — never claim a route works without per-route evidence).
//
// Each per-stem route measures how often that stem's `*_energy_dev` is above the SkeinState onset
// threshold (0.13) — i.e. how often that stem lays a burst in its colour. A non-trivial firing
// rate on ≥ 3 stems is the per-route evidence behind the colour-legibility claim ("drums → their
// colour's flicks, bass → their colour's pools, vocals → their colour's lines"). Gates are sized
// to the SkeinState routing (onset threshold 0.13; a strong hit ≳ 0.30). Keep in sync with
// `SkeinState` (onsetDevThreshold, the broadband painter-speed driver).

import Foundation
import Shared

public enum SkeinRouteSpecs {

    /// Broadband energy deviation = mean of the four positive per-stem devs — the painter-speed
    /// driver in `SkeinState._tick` (`(drums+bass+vocals+other dev) * 0.25`).
    private static func broadbandDev(_ frame: SessionFrame) -> Float {
        (max(0, frame.drumsEnergyDev) + max(0, frame.bassEnergyDev)
            + max(0, frame.vocalsEnergyDev) + max(0, frame.otherEnergyDev)) * 0.25
    }

    /// STRUCTURAL — drums → drum-colour FLICKS. A drum onset lays a splatter burst at the painter
    /// position in the drums colour (the onset-burst ring). LO 0.13 = the SkeinState onset
    /// threshold (a burst fires), HI 0.30 = a strong hit (a sharp, prominent flick).
    public static let drumsFlicks = RouteSpec(
        name: "DRUMS → drum-colour flicks (per-stem onset)",
        description: "stems.drums_energy_dev above the onset threshold → a drum-coloured splatter "
                   + "burst at the painter position (the onset-burst ring). Splatter density ∝ "
                   + "drum activity. The drums channel of the per-stem colour legibility.",
        inputName: "stems.drums_energy_dev",
        gateThreshold: 0.13,
        partialGateThreshold: 0.30,
        inputValue: { $0.drumsEnergyDev }
    )

    /// STRUCTURAL — bass → bass-colour POOLS. A bass onset lays a heavy (thick / low-centroid)
    /// burst in the bass colour.
    public static let bassPools = RouteSpec(
        name: "BASS → bass-colour pools (per-stem onset)",
        description: "stems.bass_energy_dev above the onset threshold → a bass-coloured burst at "
                   + "the painter position. Bass tends low-centroid → thick, heavy pools. The bass "
                   + "channel of the per-stem colour legibility.",
        inputName: "stems.bass_energy_dev",
        gateThreshold: 0.13,
        partialGateThreshold: 0.30,
        inputValue: { $0.bassEnergyDev }
    )

    /// STRUCTURAL — vocals → vocal-colour LINES/marks, and (when the dominant stem) the pour-line
    /// colour itself.
    public static let vocalsLines = RouteSpec(
        name: "VOCALS → vocal-colour lines (per-stem onset / dominant line)",
        description: "stems.vocals_energy_dev above the onset threshold → a vocal-coloured burst; "
                   + "when vocals are the dominant (argmax) stem the continuous pour LINE takes the "
                   + "vocals colour. The vocals channel of the per-stem colour legibility.",
        inputName: "stems.vocals_energy_dev",
        gateThreshold: 0.13,
        partialGateThreshold: 0.30,
        inputValue: { $0.vocalsEnergyDev }
    )

    /// STRUCTURAL — harmony/other → connective mid-tone marks, and (when dominant) the line colour.
    public static let harmonyMarks = RouteSpec(
        name: "HARMONY (other) → connective-colour marks (per-stem onset / dominant line)",
        description: "stems.other_energy_dev above the onset threshold → an other-coloured burst; "
                   + "when 'other' is the dominant stem the pour LINE takes the connective mid-tone. "
                   + "The harmony channel of the per-stem colour legibility.",
        inputName: "stems.other_energy_dev",
        gateThreshold: 0.13,
        partialGateThreshold: 0.30,
        inputValue: { $0.otherEnergyDev }
    )

    /// PRIMARY — broadband energy deviation → painter SPEED (busy passages fill faster, the §M7
    /// pacing note) + the dominant stem's pour-line width. Continuous, the dominant coupling.
    /// LO 0.05 = the painter starts accelerating above its base rate; HI 0.18 = a vigorous fill.
    public static let painterSpeed = RouteSpec(
        name: "ENERGY → painter speed + pour flow (PRIMARY)",
        description: "broadband energy deviation = mean(max(0, *_energy_dev)) → the painter clock "
                   + "rate (painterTau; busy passages fill faster) and the dominant stem's pour-line "
                   + "width. The dominant continuous coupling — fires whenever music plays.",
        inputName: "mean(max(0, *_energy_dev))",
        gateThreshold: 0.05,
        partialGateThreshold: 0.18,
        inputValue: { broadbandDev($0) }
    )

    /// The Skein.3 route set. Per-stem onset (colour) routes + the primary painter-speed route.
    /// Viscosity ← centroid and flick-sharpness ← attackRatio are NOT in this set: `SessionFrame`
    /// records no centroid/attackRatio, so SR.1 cannot measure them (stated, not asserted).
    public static let all: [RouteSpec] = [drumsFlicks, bassPools, vocalsLines, harmonyMarks, painterSpeed]
}
