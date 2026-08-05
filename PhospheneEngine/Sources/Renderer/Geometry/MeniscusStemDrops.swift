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
    /// Fast band-level envelope the silence gate reads (MEN.3h). ~0.12 s, no floor.
    private var audioGate: Float = 0
    /// How full the arrangement is, 0-1, on a ~3 s envelope (MEN.4a).
    private var arrangement: Float = 0
    /// Mood arousal on a ~6 s envelope — the track's build and release (MEN.4a).
    private var arcEnvelope: Float = 0
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

        // EVERY DROP IS GRID-TIMED (MEN.3g), Matt's call after seven live rounds.
        //
        // The only part of this preset that ever measured as synced was the part taking
        // its timing from the cached BeatGrid — a median 6 ms from the beat in every round
        // from MEN.3c on. Every failure was a drop driven from a live audio signal, and
        // each candidate died to a measurement: separated stems lag 5.2 s; the per-band
        // beat pulses saturate (beatComposite exactly 1.000 on 59 % of frames, in runs up
        // to 600 ms); band deviations are event-shaped but far too sparse to carry the
        // surface. Full evidence in `MENISCUS_PLAN.md` §9 MEN.3f/3g.
        //
        // So the grid supplies ALL timing and the BAR supplies the spatial pattern. §1's
        // claim that "a listener can point at a ripple and say that was the snare" is
        // retired — §7 R3 flagged that legibility as ungrounded and seven live viewings
        // never produced it. Regions are spatial variety keyed to bar position now.
        // THE SILENCE GATE (MEN.3h). Matt: "drops are still falling at silence."
        //
        // Structural, not a tuning miss: nothing in the firing path read CURRENT loudness.
        // The grid keeps ticking through a quiet passage, the dynamics term had a floor so
        // every event still landed, and the only presence gate read STEMS — 5.2 s stale, so
        // it cannot close on a silence that just began. On `2026-08-05T15-06-31Z` the band
        // level is exactly 0.0000 on >25 % of frames and drops rained through all of it.
        // Fast envelope, no floor. D-037 governs what the SCREEN shows at silence (the
        // backdrop still renders), not whether the water is struck when nothing plays.
        let level = max(0, (features.bass + features.mid + features.treble) / 3)
        audioGate += (level - audioGate) * (1 - exp(-dt / 0.12))
        let audible = audioGate > configuration.silenceFloor

        // Dynamics with NO FLOOR — the floor was the bug. A quiet passage now produces
        // genuinely small drops and silence produces none, which is the whole point of
        // §5's loudness row.
        let dynamics = min(audioGate / 0.09, 1.0) * (0.4 + min(max(features.bassDev, 0), 1.5))

        // THE MUSICAL ARC (MEN.4a). Matt: "Music is more than just beat, remember."
        //
        // That is the diagnosis eight rounds of beat-timing work never reached. Meniscus
        // was rhythmically accurate and structurally DEAF: the same drop density, the same
        // placement pattern and the same character on every beat from the first bar to the
        // last. Perfect timing on an unchanging pattern is still a metronome.
        //
        // Measured on `2026-08-05T15-06-31Z` (Hummer), the music moves a great deal across
        // 92 s — arousal 0.19 -> 0.52 -> 0.27, valence swinging through zero twice, every
        // stem rising to a peak at 30-45 s and then falling away — while the only things
        // the preset varied were overall amplitude and camera distance.
        //
        // These drivers are all SECTION-SCALE, which is the point: it is exactly the
        // timescale the stems are good at, so the ~5.2 s stem latency that made them
        // useless for events (MEN.3f) is harmless here. The stems come back for the job
        // they can actually do — telling us how full the arrangement is right now.
        let bandCount = [stems.drumsEnergy, stems.bassEnergy,
                         stems.vocalsEnergy, stems.otherEnergy].filter { $0 > 0.15 }.count
        let fullness = Float(bandCount) / 4
        arrangement += (fullness - arrangement) * (1 - exp(-dt / 3.0))
        let lift = max(0, min(features.arousal, 1))
        arcEnvelope += (lift - arcEnvelope) * (1 - exp(-dt / 6.0))
        // How much of the pattern is playing right now. A sparse intro gets downbeats only;
        // a full chorus gets every beat, the backbeat answer and the offbeat scatter. This
        // is what makes a build FILL IN rather than merely grow louder.
        let density = 0.35 * arcEnvelope + 0.65 * arrangement

        // §5's characters, mapped onto the bar. Drums mark every beat; the bass heave
        // arrives on the downbeat; vocals answer on the backbeat; `other` scatters on the
        // offbeat subdivisions so the surface is never merely pulsing on the beat.
        let beatInBar = ((beatIndex % 4) + 4) % 4
        var firing: [Int] = []
        if clock.beat {
            // The downbeat always answers while anything is playing — it is the spine.
            if beatInBar == 0 { firing.append(1) }
            // Every beat, once the arrangement is past a bare intro.
            if density > 0.25 { firing.append(0) }
            // The backbeat answer arrives when the band fills out.
            if (beatInBar == 1 || beatInBar == 3) && density > 0.5 { firing.append(2) }
        }
        // Offbeat scatter is the top of the arc — the last thing to arrive and the first
        // to go, so a chorus is visibly busier than the verse that set it up.
        if clock.halfBeat && density > 0.55 { firing.append(3) }
        // ASCENDING REGION ORDER IS A CONTRACT, not a coincidence. `lastSites` is emitted
        // in this order and every diagnostic attributes sites to regions by walking
        // `lastPerRegion` alongside it. Appending the downbeat's bass before the drums
        // silently mis-attributed every drop — the region-ordering gate caught it.
        firing.sort()

        for index in firing where audible {

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

    mutating func reset() {
        for i in envelopes.indices {
            envelopes[i] = 0; previous[i] = 0; refractory[i] = 0
        }
        lastSites.removeAll()
        lastForces.removeAll()
        for i in lastPerRegion.indices { lastPerRegion[i] = 0 }
        rng = 0x2545_F491_4F6C_DD1D
        loudness = 0
        audioGate = 0
        arrangement = 0
        arcEnvelope = 0
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
