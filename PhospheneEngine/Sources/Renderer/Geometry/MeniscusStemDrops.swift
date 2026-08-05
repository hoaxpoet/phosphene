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
    // --- Predictive beat clock (MEN.3c) ---------------------------------------------
    //
    // `beatPhase01` arrives at 10 Hz — a STAIR-STEP held ~100 ms, not a per-frame ramp —
    // so firing on its wrap edge both quantises the timing and MISSES BEATS: measured on
    // Matt's session, 55 edges detected against 72 actual beats, a 24 % miss rate that
    // reads as erratic. Running a local phase clock between updates fixes both.
    private var localPhase: Float = 0
    private var beatPeriod: Float = 0.5
    private var previousBeatPhase: Float = -1
    private var sinceGridUpdate: Float = 0
    /// Guards one fire per beat, and one per offbeat subdivision.
    private var firedThisBeat = false
    private var firedThisHalf = false
    /// Counts grid beats so the BAR can choose which regions answer (MEN.3g).
    private var beatIndex = 0
    private var sinceGridBeat: Float = 99
    /// Whether the cached grid is delivering updates; false ⇒ degrade to onset-driven
    /// rather than freezing the percussion.
    private var gridLive = false

    private var envelopes = [Float](repeating: 0, count: 4)
    private var previous = [Float](repeating: 0, count: 4)
    private var refractory = [Float](repeating: 0, count: 4)
    /// Per-region stem presence on a ~2.5 s envelope — "is this instrument playing in
    /// this passage", never "did it just hit" (MEN.3f).
    private var presence = [Float](repeating: 0, count: 4)
    private var rng: UInt64 = 0x2545_F491_4F6C_DD1D

    /// Diagnostics.
    private(set) var lastSites: [Int] = []
    private(set) var lastPerRegion = [Int](repeating: 0, count: 4)
    /// Per-drop force this step, parallel to `lastSites` — the intensity gate reads it.
    private(set) var lastForces: [Float] = []
    /// The loudness-derived intensity multiplier applied this step (§5's row).
    private(set) var lastIntensity: Float = 0

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
        lastIntensity = intensity

        let clock = advanceBeatClock(features: features, dt: dt, configuration: configuration)
        if clock.beat { beatIndex &+= 1 }

        // EVERY DROP IS GRID-TIMED (MEN.3g). Matt's call after seven live rounds.
        //
        // The evidence is unambiguous once assembled: the only part of this preset that
        // EVER measured as synced was the part taking its timing from the cached BeatGrid.
        // Grid-timed drops landed a median 6 ms from the beat in every single round. Every
        // failure was a drop driven from a live audio signal, and each candidate died to a
        // measurement:
        //
        //   - SEPARATED STEMS lag the music by ~5.2 s (session `2026-08-05T13-17-18Z`:
        //     drums +5.25 s, bass +5.25, vocals +5.08, other +5.25; r=0.363 at lag 0).
        //     `VisualizerEngine+Audio.swift` documents this as intended — they answer
        //     "what kind of passage is this", a section-scale question.
        //   - THE PER-BAND BEAT PULSES saturate. On `2026-08-05T14-09-24Z`, beatComposite
        //     is exactly 1.000 on 59 % of frames, in runs up to 36 frames (600 ms): they
        //     are onset pulses re-triggered faster than they decay, sampled at the 10 Hz
        //     MIR rate. A drive that is pinned high is a metronome, not music.
        //   - BAND DEVIATIONS are correctly event-shaped but far too sparse to carry the
        //     surface: ~40 % of beats produced a drop against a 55 % bar, and the audio's
        //     share of surface motion collapsed to 17 % against a 50 % bar. Treble is
        //     effectively silent (mid p50 0.029, treble p50 0.004).
        //
        // So the grid supplies ALL timing. What the bar supplies is the SPATIAL pattern:
        // different regions answer on different beats, which is what keeps a fully
        // quantised surface from reading as a metronome. Force still comes from live audio
        // (bass deviation + the loudness envelope), so the dynamics are current even though
        // the timing is not derived from the moment.
        //
        // WHAT THIS GIVES UP, explicitly. §1's claim that "a listener can point at a ripple
        // and say that was the snare" is retired. §7 R3 flagged that legibility as having
        // no empirical grounding, and seven live viewings never produced it. The regions
        // are now spatial variety keyed to bar position, not instrument identity.
        let stemsPresent = updatePresence(stems: stems, dt: dt)

        // Dynamics from the one real-time primitive that measures clean: bass deviation.
        // The floor keeps every grid event landing (a beat with no drop reads as a dropout,
        // which is worse than a soft one); the deviation term is what makes a hard hit
        // land harder than a soft one within the same passage.
        let dynamics = 0.5 + min(max(features.bassDev, 0), 1.5)

        // §5's characters, mapped onto the bar. Drums mark every beat; the bass heave
        // arrives on the downbeat; vocals answer on the backbeat; `other` scatters on the
        // offbeat subdivisions so the surface is never merely pulsing on the beat.
        let beatInBar = ((beatIndex % 4) + 4) % 4
        var firing: [Int] = []
        if clock.beat {
            firing.append(0)
            if beatInBar == 0 { firing.append(1) }
            if beatInBar == 1 || beatInBar == 3 { firing.append(2) }
        }
        if clock.halfBeat { firing.append(3) }

        for index in firing {
            // The stem's one remaining job, and the timescale it is actually good for: a
            // region whose instrument is not playing in this passage stays still.
            guard !stemsPresent || presence[index] > configuration.stemPresenceThreshold
            else { continue }

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
            let force = dynamics * region.force
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

    // MARK: - Predictive beat clock

    /// Advance the local beat clock and report whether a percussion drop should fire now.
    ///
    /// Split out of `step` because it is a distinct concern: `step` decides WHICH stem
    /// strikes WHERE, this decides WHEN.
    private mutating func advanceBeatClock(
        features: FeatureVector,
        dt: Float,
        configuration: MeniscusConfiguration
    ) -> (beat: Bool, halfBeat: Bool) {
        // PREDICTIVE BEAT CLOCK. Fires `stemLeadTime` BEFORE the grid beat, because the
        // ripple is an impulse into a wave field and has to GROW: measured, the visible
        // slope response is only 14 % one frame after impact, ~30 % at 67 ms and ~50 % at
        // 167 ms. So a perfectly-timed drop still reads late — the eye tracks the ring
        // forming, not the impact. Leading by the ripple's perceptual onset puts the
        // visible event on the beat. This is the one thing the CACHED grid buys that a
        // live detector never could: it knows where the next beat WILL be.
        let reportedPhase = features.beatPhase01
        if reportedPhase != previousBeatPhase {
            // A fresh 10 Hz sample: estimate the beat period from how far phase moved,
            // then re-sync the local clock to it.
            if previousBeatPhase >= 0, sinceGridUpdate > 1e-4 {
                var advanced = reportedPhase - previousBeatPhase
                if advanced < 0 { advanced += 1 }              // wrapped
                if advanced > 0.02 && advanced < 0.9 {
                    let measured = sinceGridUpdate / advanced
                    if measured > 0.2 && measured < 2.0 {
                        beatPeriod += (measured - beatPeriod) * 0.25
                    }
                }
            }
            if reportedPhase < localPhase - 0.5 || reportedPhase > localPhase + 0.5 {
                firedThisBeat = false                          // resync crossed a beat
            }
            localPhase = reportedPhase
            previousBeatPhase = reportedPhase
            sinceGridUpdate = 0
            sinceGridBeat = 0
        } else {
            sinceGridUpdate += dt
            sinceGridBeat += dt
        }
        // Advance the local clock between updates so timing is frame-accurate.
        localPhase += dt / max(beatPeriod, 0.05)
        if localPhase >= 1 { localPhase -= 1; firedThisBeat = false }

        // Fire when the NEXT beat is `stemLeadTime` away.
        let leadPhase = 1 - min(configuration.stemLeadTime / max(beatPeriod, 0.05), 0.9)
        let gridBeat = !firedThisBeat && localPhase >= leadPhase
        if gridBeat { firedThisBeat = true }
        // The offbeat, led the same way. `other` rides these so the surface carries motion
        // between the beats rather than pulsing strictly on them — the quantised-metronome
        // risk that MEN.3g's all-grid timing would otherwise walk straight into.
        let halfLead = max(leadPhase - 0.5, 0.02)
        let gridHalf = !firedThisHalf && localPhase >= halfLead && localPhase < leadPhase
        if gridHalf { firedThisHalf = true }
        if localPhase < halfLead { firedThisHalf = false }
        // A grid is "live" if a beat has arrived recently. 2 s covers anything down to
        // 30 BPM, and a stalled or absent grid degrades to the onset path rather than
        // silencing the drums entirely.
        gridLive = sinceGridBeat < 2.0
        return (gridBeat, gridHalf)
    }

    /// Advance each region's stem-presence envelope and report whether separation is
    /// running at all. Smoothed hard on purpose: this answers "is there a bass part in this
    /// section", never "did it just hit", so the live path's ~5 s stem latency is harmless
    /// here — that is the whole basis of the MEN.3f split.
    ///
    /// Returns false when no stem carries energy (warmup, a stem-less path, a fixture with
    /// no stems). Callers must treat that as "every region alive": without it the gate
    /// turns a missing OPTIONAL signal into a dead surface.
    private mutating func updatePresence(stems: StemFeatures, dt: Float) -> Bool {
        let energies: [Float] = [
            max(stems.drumsEnergy, stems.drumsBeat),
            stems.bassEnergy,
            stems.vocalsEnergy,
            stems.otherEnergy
        ]
        let alpha = 1 - exp(-dt / 2.5)
        for index in 0..<4 {
            presence[index] += (energies[index] - presence[index]) * alpha
        }
        return energies.contains { $0 > 0.001 }
    }

    mutating func reset() {
        for i in envelopes.indices {
            envelopes[i] = 0; previous[i] = 0; refractory[i] = 0; presence[i] = 0
        }
        lastSites.removeAll()
        lastForces.removeAll()
        for i in lastPerRegion.indices { lastPerRegion[i] = 0 }
        rng = 0x2545_F491_4F6C_DD1D
        loudness = 0
        localPhase = 0; beatPeriod = 0.5; previousBeatPhase = -1
        sinceGridUpdate = 0; firedThisBeat = false
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
