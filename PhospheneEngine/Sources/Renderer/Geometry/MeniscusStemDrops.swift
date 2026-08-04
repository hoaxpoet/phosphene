// MeniscusStemDrops — the Phosphene placement (MEN.3). THE DIVERGENCE AXIS.
//
// Replaces the source's cepstral placement (`MeniscusDrops`, ported at MEN.2b and kept as
// the oracle). This is the D-121 divergence and the whole reason Meniscus is a Phosphene
// preset rather than a reproduction: a different feature stack end to end — Open-Unmix HQ
// stems + deviation primitives, against a hand-rolled DFT-of-FFT.
//
// WHY IT HAD TO CHANGE, confirmed from Matt's live viewing (2026-08-04) rather than
// argued: the ported placement reads as random. That is not a defect in the port —
// `MENISCUS_PLAN.md` §3 says of the source's mechanism "no listener can perceive the
// mapping", so a faithful port of an inaudible mechanism produces motion that looks
// random BY CONSTRUCTION. MEN.2b's job was to establish the drop distribution the wave
// sim needs and to prove that point with evidence. Both done.
//
// THE MUSICAL ROLE (§1) is what this delivers: "every drop that strikes the water is an
// instrument: the drums land on the near edge, the bass lands deep at the centre, the
// vocal lands high and far, and the ripples that spread from each impact and interfere
// with one another are the arrangement, drawn as a wake." A listener can point at a
// ripple and say "that was the snare" — which was never true of the cepstral placement.
//
// REGION LAYOUT is §5's table. It is explicitly provisional there, and its legibility is
// the plan's own risk R3 ("no empirical grounding for the combination") — assessable only
// in motion against real music at M7.
//
// DENSITY IS THE NAMED RISK (§5): "four sources firing on their own onsets may be far
// sparser than the source's continuous spectral placement". MEN.2b measured what the
// surface actually needs — 1.1 to 39 new impact sites/second across sparse jazz to dense
// electronic — so that target now exists as a number rather than a guess, and
// `MeniscusStemDropsTests` holds this placement to it.

import Foundation
import Shared

// MARK: - MeniscusStemDrops

/// Places drops by STEM, each instrument owning a region of the water surface.
struct MeniscusStemDrops {

    /// One instrument's territory and impact character (§5's table).
    struct Region {
        let name: String
        /// Centre in grid units, 0…1.
        let centre: SIMD2<Float>
        /// Half-extent of the scatter around that centre, 0…1. Jitter within the region
        /// is §7 R5's mitigation: the source's wandering placement has a charm that a
        /// fixed point per stem would lose, and "orderly may read as mechanical".
        let spread: SIMD2<Float>
        /// Stencil radius in cells. 1 = the source's 3×3 punctuation; larger spreads the
        /// impulse into a heave.
        let radius: Int
        /// Force per unit deviation.
        let force: Float
    }

    /// §5's layout. Near edge is +v (the near margin after projection).
    static let regions: [Region] = [
        // Drums — near edge, spread laterally. Sharp, narrow, high: the punctuation.
        Region(
            name: "drums",
            centre: SIMD2(0.5, 0.82),
            spread: SIMD2(0.34, 0.07),
            radius: 1,
            force: 0.30),
        // Bass — deep centre. Broad, low, slow-decaying: a heave rather than a spike, so
        // a wider stencil at lower force.
        Region(
            name: "bass",
            centre: SIMD2(0.5, 0.5),
            spread: SIMD2(0.13, 0.13),
            radius: 3,
            force: 0.13),
        // Vocals — far and high. Narrow and sustained.
        Region(
            name: "vocals",
            centre: SIMD2(0.5, 0.2),
            spread: SIMD2(0.2, 0.07),
            radius: 1,
            force: 0.22),
        // Other — wide, low-amplitude scatter. Texture; keeps the field from ever being
        // fully still, and per §7 R5 it is what stops the layout reading as four fixed
        // points.
        Region(
            name: "other",
            centre: SIMD2(0.5, 0.5),
            spread: SIMD2(0.42, 0.42),
            radius: 1,
            force: 0.09)
    ]

    /// Loudness envelope, ~1 s — §5's "overall loudness → wave amplitude / surface
    /// liveliness. The whole sheet is calmer in quiet passages and choppier in loud ones."
    /// This row of the routing table was specified from the start and was simply never
    /// implemented, which is why Matt measured drops that looked identical loud or quiet.
    private var loudness: Float = 0
    /// Previous grid beat phase, for wrap detection.
    private var previousBeatPhase: Float = 0
    /// Seconds since the last grid beat. Grid sync falls back to onset-driven when the
    /// grid is absent or stalled — `barPhase01` cannot be tested directly for presence
    /// because it is legitimately 0 at every downbeat.
    private var sinceGridBeat: Float = 99

    private var envelopes = [Float](repeating: 0, count: 4)
    private var previous = [Float](repeating: 0, count: 4)
    private var refractory = [Float](repeating: 0, count: 4)
    private var rng: UInt64 = 0x2545_F491_4F6C_DD1D

    /// Diagnostics.
    private(set) var lastSites: [Int] = []
    private(set) var lastPerRegion = [Int](repeating: 0, count: 4)
    /// Per-drop force this step, parallel to `lastSites` — the intensity gate reads it.
    private(set) var lastForces: [Float] = []

    // MARK: - Per frame

    mutating func step(
        stems: StemFeatures,
        features: FeatureVector,
        field: inout [Float],
        dt: Float,
        configuration: MeniscusConfiguration
    ) {
        lastSites.removeAll(keepingCapacity: true)
        lastForces.removeAll(keepingCapacity: true)
        for i in lastPerRegion.indices { lastPerRegion[i] = 0 }
        // `side` is `configuration.gridN` — taking it as a parameter too was a
        // redundant sixth argument.
        let side = configuration.gridN
        guard side > 4 else { return }

        // DEVIATION PRIMITIVES, never absolute energy (D-026 / FA #31). `drumsEnergyDev`
        // and friends already express "this stem is louder than its own running mean",
        // which is exactly the onset notion a drop needs and is AGC-safe by construction.
        //
        // Drums additionally take `drumsBeat`, the stem's own onset pulse — the
        // `drums_beat` class §5's FA #67 table names for the drums row specifically.
        // INTENSITY (§5's loudness row). Deviation primitives are self-normalising BY
        // CONSTRUCTION — a stem's deviation says how far it sits above its OWN running
        // mean, so a quiet snare and a loud one produce nearly the same value. That is
        // exactly what makes them AGC-safe, and exactly why they carry no dynamics.
        // Measured on Matt's session: drop force vs loudness r = +0.004, quietest and
        // loudest quartiles both at mean force 0.57. The fix is not to abandon deviation
        // (which would reintroduce FA #31) but to add the SEPARATE loudness row the
        // routing table already specifies, on its own ~1 s timescale.
        let instantLoudness = min(max((features.bass + features.mid + features.treble) / 3, 0), 1.4)
        loudness += (instantLoudness - loudness) * (1 - exp(-dt / 0.9))
        let intensity = configuration.stemIntensityFloor
            + (1 - configuration.stemIntensityFloor) * min(loudness / 0.55, 1.8)

        // GRID BEAT, for the drums row. `beatPhase01` sawtooths 0→1 across each beat of
        // the CACHED BeatGrid, so a wrap is a grid beat.
        let beatPhase = features.beatPhase01
        let gridBeat = previousBeatPhase > 0.75 && beatPhase < 0.25
        previousBeatPhase = beatPhase
        sinceGridBeat = gridBeat ? 0 : sinceGridBeat + dt
        // A grid is "live" if a beat has arrived recently. 2 s covers anything down to
        // 30 BPM, and a stalled or absent grid degrades to the onset path rather than
        // silencing the drums entirely.
        let gridLive = sinceGridBeat < 2.0

        let drives: [Float] = [
            max(stems.drumsEnergyDev, stems.drumsBeat),
            stems.bassEnergyDev,
            stems.vocalsEnergyDev,
            stems.otherEnergyDev
        ]

        for index in 0..<4 {
            let drive = max(0, drives[index])
            // Fast attack, slower release — an impact is an event, not a level.
            let alpha = drive > envelopes[index] ? dt / (0.008 + dt) : dt / (0.11 + dt)
            envelopes[index] += alpha * (drive - envelopes[index])
            refractory[index] = max(0, refractory[index] - dt)

            // TIMING. Drums and bass take their timing from the CACHED GRID; vocals and
            // `other` stay onset-driven.
            //
            // This is the audio hierarchy's central rule, and Meniscus was on the wrong
            // side of it: "visuals driven primarily by raw live beat detections feel out
            // of sync", because live onsets jitter and beat-locked motion is valid only
            // on the cached grid (D-153→D-158). Measured on Matt's session, threshold
            // crossings of a smoothed deviation landed a median 200 ms from the nearest
            // beat with only 8-10 % inside the ~60 ms perceptual window — uncorrelated.
            //
            // The grid supplies WHEN; the stem still supplies WHETHER and HOW HARD, so a
            // beat with no drums on it places nothing and a hard hit still lands harder.
            // Bounded footprint (a 3×3 stencil) and no global luminance change, so this
            // satisfies D-157.
            //
            // Vocals and `other` are deliberately NOT quantised — §5 gives them
            // "sustained" and "texture" characters that a grid would make robotic.
            let usesGrid = index < 2 && configuration.stemGridSync && gridLive
            let fired: Bool
            if usesGrid {
                fired = gridBeat && envelopes[index] > configuration.stemPresenceThreshold
            } else {
                fired = envelopes[index] > configuration.stemDropThreshold
                    && previous[index] <= configuration.stemDropThreshold
                    && refractory[index] <= 0
            }
            previous[index] = envelopes[index]
            guard fired else { continue }
            refractory[index] = configuration.stemDropRefractory

            let region = Self.regions[index]
            // Jitter WITHIN the region (§7 R5) — the stem decides the territory, not the
            // exact cell, so repeated hits do not hammer one point.
            let unit = SIMD2(nextUnit(), nextUnit())
            let position = region.centre + (unit * 2 - 1) * region.spread
            let col = Self.wrap(position.x * Float(side), side)
            let row = Self.wrap(position.y * Float(side), side)

            // Force scales with HOW FAR above its own mean the stem is, so a hard snare
            // lands harder than a soft one — the dynamics survive the gate.
            // Force carries BOTH: how far the stem is above its own mean (dynamics
            // within the passage) and the loudness envelope (dynamics across the track).
            let force = min(envelopes[index], 3.0) * region.force
                * configuration.stemDropForce * intensity
            stamp(
                &field,
                side: side,
                cell: (col, row),
                radius: region.radius,
                force: force)
            lastSites.append(row * side + col)
            lastForces.append(force)
            lastPerRegion[index] += 1
        }
    }

    mutating func reset() {
        for i in envelopes.indices { envelopes[i] = 0; previous[i] = 0; refractory[i] = 0 }
        lastSites.removeAll()
        lastForces.removeAll()
        for i in lastPerRegion.indices { lastPerRegion[i] = 0 }
        rng = 0x2545_F491_4F6C_DD1D
        loudness = 0
        previousBeatPhase = 0
    }

    // MARK: - Impact

    /// Radially-weighted stencil on the torus. `radius` 1 reproduces the source's 3×3
    /// punctuation; larger radii spread the same impulse into the broad heave §5 asks of
    /// the bass row.
    private func stamp(_ field: inout [Float], side: Int, cell: (col: Int, row: Int),
                       radius: Int, force: Float) {
        for dy in -radius...radius {
            for dx in -radius...radius {
                let distanceSq = Float(dx * dx + dy * dy)
                guard distanceSq <= Float(radius * radius) + 0.01 else { continue }
                let weight = 1 / (1 + distanceSq)
                let wrappedRow = ((cell.row + dy) % side + side) % side
                let wrappedCol = ((cell.col + dx) % side + side) % side
                field[wrappedRow * side + wrappedCol] -= force * weight
            }
        }
    }

    /// Deterministic — a given track renders identically twice.
    private mutating func nextUnit() -> Float {
        rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float((rng >> 33) & 0xFF_FFFF) / Float(0xFF_FFFF)
    }

    private static func wrap(_ value: Float, _ side: Int) -> Int {
        let wrapped = Int(value.rounded(.down)) % side
        return wrapped < 0 ? wrapped + side : wrapped
    }
}
