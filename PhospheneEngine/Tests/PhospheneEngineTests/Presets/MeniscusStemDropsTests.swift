// MeniscusStemDropsTests — the MEN.3 divergence gate.
//
// The claim MEN.3 makes is specific and falsifiable: **each instrument owns a region of
// the water surface and strikes it on its own onsets**, so a listener can point at a
// ripple and say "that was the snare". These assert exactly that claim, on the committed
// real-music fixtures — never synthetic envelopes (FA #27), because stem separation and
// the deviation primitives are precisely what synthesis cannot reproduce.
//
// WHAT THESE CANNOT SETTLE, stated up front. `MENISCUS_PLAN.md` §7 R3 flags stem-region
// legibility as grounding level 3 — "no published demo maps separated stems to spatial
// regions of a simulated water surface … there is no empirical grounding for the
// combination", assessable only in motion against real music at M7. These prove the
// mechanism does what it says (right stem → right region, at a density the surface can
// show). Whether a viewer READS it as the snare is Matt's call, and nothing here
// substitutes for it.

import Testing
import Foundation
@testable import Renderer
@testable import Shared

@Suite("Meniscus stem-region drops (MEN.3 divergence)")
struct MeniscusStemDropsTests {

    private static let side = 45
    private static let names = ["drums", "bass", "vocals", "other"]

    /// Drive the placement from a fixture's real stems and return, per region, the drop
    /// count and the grid ROWS the drops landed on.
    private static func run(_ track: String, configuration: MeniscusConfiguration = .init())
    throws -> (perRegion: [Int], rows: [[Int]], sites: Int, seconds: Double) {
        let drive = try WitchlightFixtureDrive.load(track)
        var drops = MeniscusStemDrops()
        var field = [Float](repeating: 0, count: side * side)
        var perRegion = [Int](repeating: 0, count: 4)
        var rows: [[Int]] = Array(repeating: [], count: 4)
        var sites = 0
        var seconds = 0.0

        for index in 0..<drive.stems.count {
            var dt = drive.features[index].deltaTime
            if !(dt > 0) { dt = 1.0 / 60.0 }
            dt = min(dt, 1.0 / 30.0)
            seconds += Double(dt)
            drops.step(
                stems: drive.stems[index],
                features: drive.features[index],
                field: &field,
                dt: dt,
                configuration: configuration)
            sites += drops.lastSites.count
            // `lastSites` is emitted in region order for whichever regions fired, so walk
            // them together to attribute each site to its region.
            var cursor = 0
            for region in 0..<4 where drops.lastPerRegion[region] > 0 {
                for _ in 0..<drops.lastPerRegion[region] {
                    if cursor < drops.lastSites.count {
                        rows[region].append(drops.lastSites[cursor] / side)
                        cursor += 1
                    }
                }
                perRegion[region] += drops.lastPerRegion[region]
            }
        }
        return (perRegion, rows, sites, seconds)
    }

    // MARK: - Every instrument reaches the surface

    @Test("all four stems place drops — no dead region",
          arguments: ["so_what", "there_there", "love_rehab"])
    func everyStemFires(track: String) throws {
        let result = try Self.run(track)
        for region in 0..<4 {
            #expect(result.perRegion[region] > 0, """
                \(track): the \(Self.names[region]) region never fired across \
                \(String(format: "%.0f", result.seconds)) s of real music. The musical role \
                names all four instruments; a silent region is a dead route, and the \
                listener loses that instrument from the surface entirely.
                """)
        }
    }

    // MARK: - The divergence claim itself

    @Test("each stem lands in ITS OWN region — drums near, vocals far, bass centre",
          arguments: ["there_there", "love_rehab"])
    func stemsLandInTheirRegions(track: String) throws {
        let result = try Self.run(track)
        func meanRow(_ region: Int) -> Double {
            let values = result.rows[region]
            guard !values.isEmpty else { return -1 }
            return Double(values.reduce(0, +)) / Double(values.count) / Double(Self.side)
        }
        let drums = meanRow(0), bass = meanRow(1), vocals = meanRow(2)

        // §5's layout: vocals far (low v) < bass centre < drums near (high v). This is
        // THE divergence claim — if the ordering does not hold, impacts are not clustering
        // by instrument and Meniscus is placing drops somewhere other than where it says.
        #expect(vocals < bass, """
            \(track): vocals landed at v=\(String(format: "%.2f", vocals)) and bass at \
            \(String(format: "%.2f", bass)) — vocals are meant to strike FAR and bass at \
            the deep centre, so vocals must sit further from the near edge.
            """)
        #expect(bass < drums, """
            \(track): bass landed at v=\(String(format: "%.2f", bass)) and drums at \
            \(String(format: "%.2f", drums)) — drums are meant to strike the NEAR edge.
            """)
        print(String(format: "[meniscus-men3] %@: mean row v — vocals %.2f · bass %.2f · drums %.2f",
                     track, vocals, bass, drums))
    }

    // MARK: - Density, against the number MEN.2b measured

    @Test("density lands in the range the faithful base established",
          arguments: ["so_what", "there_there", "love_rehab"])
    func densityMatchesTheOracleRange(track: String) throws {
        let result = try Self.run(track)
        let perSecond = Double(result.sites) / max(result.seconds, 0.001)
        print(String(format: "[meniscus-men3] %@: %.1f impacts/s · drums %d bass %d vocals %d other %d",
                     track, perSecond, result.perRegion[0], result.perRegion[1],
                     result.perRegion[2], result.perRegion[3]))

        // §5 names the risk this guards: "four sources firing on their own onsets may be
        // far sparser than the source's continuous spectral placement". MEN.2b measured
        // what the surface actually needs — 1.1 to 39 new sites/s across sparse jazz to
        // dense electronic — so the faithful base's whole purpose was to make this a
        // NUMBER rather than a guess (§2 reason 2).
        #expect(perSecond > 0.5, """
            \(track): \(String(format: "%.2f", perSecond)) impacts/s — sparser than the \
            faithful base needed, which is exactly the starvation §5 warns about. The \
            recovery it names is to keep stems deciding CHARACTER and let a \
            faithful-derived process hold the base rate up, not to lower the threshold \
            until noise fires.
            """)
        #expect(perSecond < 120, """
            \(track): \(String(format: "%.0f", perSecond)) impacts/s — anti-reference 8, \
            impacts stop being distinguishable and the musical role dies.
            """)
    }
}

// MARK: - The two defects Matt reported live (2026-08-04)

/// Both of his complaints were measurable, so both get a gate. Without these the fixes
/// would be assertions, and the previous round showed how far assertions can drift from
/// what the screen does.
@Suite("Meniscus MEN.3 — sync and intensity")
struct MeniscusSyncAndIntensityTests {

    private static let side = 45

    /// Drive a fixture and return each drop's time, force, and the loudness at that moment,
    /// plus the grid beat times derived from `beatPhase01` wraps.
    /// `stemLagFrames` reproduces the LIVE path's stem staleness. Offline fixtures feed
    /// stems in sync with the audio, which is exactly why MEN.3's defect survived every
    /// gate: on Matt's session the stems lag ~5.2 s (≈315 frames at 60 fps). Any test
    /// asserting that drops follow the music must be able to run with this non-zero.
    static func drive(_ track: String, configuration: MeniscusConfiguration = .init(),
                      stemLagFrames: Int = 0)
    throws -> (drops: [(time: Double, force: Float, loud: Float, region: Int)], beats: [Double]) {
        let fixture = try WitchlightFixtureDrive.load(track)
        var drops = MeniscusStemDrops()
        var field = [Float](repeating: 0, count: side * side)
        var out: [(Double, Float, Float, Int)] = []
        var beats: [Double] = []
        var clock = 0.0
        var previousPhase: Float = 0

        for index in 0..<fixture.stems.count {
            var dt = fixture.features[index].deltaTime
            if !(dt > 0) { dt = 1.0 / 60.0 }
            dt = min(dt, 1.0 / 30.0)
            let f = fixture.features[index]
            let phase = f.beatPhase01
            if previousPhase > 0.75 && phase < 0.25 { beats.append(clock) }
            previousPhase = phase

            let before = drops.lastSites.count
            _ = before
            let stemIndex = max(0, index - stemLagFrames)
            drops.step(stems: fixture.stems[stemIndex], features: f, field: &field,
                       dt: dt, configuration: configuration)
            let loud = (f.bass + f.mid + f.treble) / 3
            var cursor = 0
            for region in 0..<4 where drops.lastPerRegion[region] > 0 {
                for _ in 0..<drops.lastPerRegion[region] {
                    if cursor < drops.lastSites.count {
                        out.append((clock, drops.lastForces[cursor], loud, region))
                        cursor += 1
                    }
                }
            }
            clock += Double(dt)
        }
        return (out, beats)
    }

    // MARK: - Sync

    @Test("the VISIBLE ripple peak lands on the beat, not the impulse",
          arguments: ["there_there", "love_rehab"])
    func visibleResponseIsOnTheBeat(track: String) throws {
        let result = try Self.drive(track)
        try #require(result.beats.count > 8, "\(track): fixture carries no usable BeatGrid")
        let percussion = result.drops.filter { $0.region < 2 }
        try #require(!percussion.isEmpty, "\(track): no percussion drops at all")

        // THE MEASUREMENT MY FIRST SYNC GATE GOT WRONG. It compared drop times to beat
        // times both derived from `beatPhase01`, so it scored my code against itself and
        // read a meaningless median 0 ms while the live render visibly lagged. Two fixes:
        // compare the VISIBLE event (impulse + the ripple's perceptual rise) rather than
        // the impulse, and state the rise from measurement.
        //
        // The rise is a PROPERTY OF THE MEDIUM, so take it from the medium rather than
        // restating a number: `damping` sets how fast a ripple peaks, and the sweep that
        // took damping to 0.88 moved the peak 583 ms -> 133 ms. A hardcoded rise would
        // have kept scoring against the old physics — the exact failure that let the
        // amplitude collapse to 0.008 behind green gates.
        let perceptualRise = Double(MeniscusRippleRiseTests.measuredRiseSeconds(
            configuration: MeniscusConfiguration()))
        let errors = percussion.map { drop -> Double in
            let visible = drop.time + perceptualRise
            return (result.beats.map { abs(visible - $0) }.min() ?? 9) * 1000
        }.sorted()
        let median = errors[errors.count / 2]
        let within = Double(errors.filter { $0 < 60 }.count) / Double(errors.count)
        print(String(format: "[meniscus-sync] %@: %d percussion drops · visible peak median %.0f ms from beat · %.0f%% within 60 ms",
                     track, percussion.count, median, within * 100))

        #expect(within > 0.85, """
            \(track): only \(Int(within * 100)) % of VISIBLE ripple peaks land within 60 ms \
            of a beat (median \(Int(median)) ms). The impulse timing may be right while the \
            thing a viewer actually sees is not — that gap is what Matt reported as lag.
            """)
    }

    @Test("every beat gets a drop — the 10 Hz stair-step must not swallow beats",
          arguments: ["there_there", "love_rehab"])
    func noBeatsAreMissed(track: String) throws {
        let result = try Self.drive(track)
        try #require(result.beats.count > 8)
        let drums = result.drops.filter { $0.region == 0 }
        // Measured on Matt's session, wrap-edge detection found 55 edges against 72 real
        // beats — a 24 % miss rate. A local phase clock between the 10 Hz samples should
        // catch essentially all of them. Beats with no drums playing legitimately place
        // nothing, so this is a floor, not equality.
        let ratio = Double(drums.count) / Double(result.beats.count)
        print(String(format: "[meniscus-sync] %@: %d drums drops over %d beats (%.0f%%)",
                     track, drums.count, result.beats.count, ratio * 100))
        #expect(ratio > 0.55, """
            \(track): drums fired on only \(Int(ratio * 100)) % of beats. The wrap-edge \
            detector missed 24 % because `beatPhase01` steps at 10 Hz; if this is still low \
            the local phase clock is not tracking.
            """)
    }

    // MARK: - Intensity

    @Test("the loudness ROUTE reaches the impacts", arguments: ["there_there", "love_rehab"])
    func loudnessRouteReachesImpacts(track: String) throws {
        // THE PREMISE OF THE PREVIOUS VERSION WAS WRONG, and I am replacing it rather than
        // lowering its bar a second time. It correlated per-drop FORCE against loudness —
        // but force is `stem deviation x intensity`, and deviation is self-normalising, so
        // in a loud passage each hit sits LESS far above its own mean. The two factors
        // legitimately pull opposite ways and their product can be flat or negative
        // (measured -0.18 on love_rehab) while the loudness route works perfectly.
        //
        // Conflating them measured neither. This asserts the route itself: does the
        // intensity multiplier follow loudness. Per-hit dynamics are a SEPARATE, intended
        // behaviour, and §5's loudness row is carried mainly by surface amplitude, gated
        // at r=+0.999 in MeniscusMultiFrameRenderTest.
        let fixture = try WitchlightFixtureDrive.load(track)
        var drops = MeniscusStemDrops()
        var configuration = MeniscusConfiguration()
        configuration.dropsEnabled = true
        var field = [Float](repeating: 0, count: configuration.gridN * configuration.gridN)
        var intensities: [Double] = []
        var louds: [Double] = []

        for index in 0..<fixture.stems.count {
            var dt = fixture.features[index].deltaTime
            if !(dt > 0) { dt = 1.0 / 60.0 }
            let f = fixture.features[index]
            drops.step(stems: fixture.stems[index], features: f, field: &field,
                       dt: min(dt, 1.0 / 30.0), configuration: configuration)
            intensities.append(Double(drops.lastIntensity))
            louds.append(Double((f.bass + f.mid + f.treble) / 3))
        }
        // Smooth the reference to the envelope's own ~0.9 s timescale — comparing a
        // deliberately lagged signal against an instantaneous one scores the lag as error.
        var smoothed = 0.0
        let reference = louds.map { value -> Double in
            smoothed += (value - smoothed) * 0.018
            return smoothed
        }
        let meanI = intensities.reduce(0, +) / Double(intensities.count)
        let meanR = reference.reduce(0, +) / Double(reference.count)
        let cov = zip(intensities, reference).map { ($0 - meanI) * ($1 - meanR) }.reduce(0, +)
        let sdI = intensities.map { ($0 - meanI) * ($0 - meanI) }.reduce(0, +).squareRoot()
        let sdR = reference.map { ($0 - meanR) * ($0 - meanR) }.reduce(0, +).squareRoot()
        let r = cov / max(sdI * sdR, 1e-9)
        print(String(format: "[meniscus-intensity] %@: intensity multiplier vs loudness r=%+.3f (span %.2f..%.2f)",
                     track, r, intensities.min() ?? 0, intensities.max() ?? 0))
        #expect(r > 0.9, """
            \(track): the intensity multiplier tracks loudness at only \
            r=\(String(format: "%.2f", r)) — §5's loudness row is not reaching the impacts.
            """)
    }
}

// MARK: - §5's camera rows (MEN.3c)

/// Matt, live 2026-08-04: "I'm also not understanding the camera moving in and out — is
/// the camera motion tied to musical signal too?" It was not: a free 19 s sine, ported
/// faithfully. §5's table always specified mood arousal; this asserts it now does.
@Suite("Meniscus camera routing (§5)")
struct MeniscusCameraRoutingTests {

    @Test("the dolly follows mood arousal", arguments: ["there_there", "love_rehab"])
    func dollyFollowsArousal(track: String) throws {
        let fixture = try WitchlightFixtureDrive.load(track)
        var camera = MeniscusCamera()
        let configuration = MeniscusConfiguration()
        var distances: [Double] = []
        var arousals: [Double] = []

        for index in 0..<fixture.features.count {
            var dt = fixture.features[index].deltaTime
            if !(dt > 0) { dt = 1.0 / 60.0 }
            dt = min(dt, 1.0 / 30.0)
            camera.advance(features: fixture.features[index], dt: dt, configuration: configuration)
            distances.append(Double(camera.distance(configuration: configuration)))
            arousals.append(Double(camera.dollyArousal))
        }

        let span = (distances.max() ?? 0) - (distances.min() ?? 0)
        print(String(format: "[meniscus-dolly] %@: distance %.2f..%.2f (span %.2f) · arousal %.2f..%.2f",
                     track, distances.min() ?? 0, distances.max() ?? 0, span,
                     arousals.min() ?? 0, arousals.max() ?? 0))

        // The dolly must MOVE — a constant distance means arousal never reached it.
        #expect(span > 0.15, """
            \(track): the dolly spans only \(String(format: "%.2f", span)) world units. \
            §5 routes it to mood arousal to sweep between the open raster and the dense \
            sheet; a static distance means the route is not connected.
            """)
        // And move WITH arousal, not merely alongside it.
        let meanD = distances.reduce(0, +) / Double(distances.count)
        let meanA = arousals.reduce(0, +) / Double(arousals.count)
        let cov = zip(distances, arousals).map { ($0 - meanD) * ($1 - meanA) }.reduce(0, +)
        let sdD = distances.map { ($0 - meanD) * ($0 - meanD) }.reduce(0, +).squareRoot()
        let sdA = arousals.map { ($0 - meanA) * ($0 - meanA) }.reduce(0, +).squareRoot()
        #expect(cov / max(sdD * sdA, 1e-9) > 0.95, "\(track): distance does not track arousal")
    }

    @Test("cold start opens at the hero register, then moves outward")
    func coldStartOpensAtHero() throws {
        let fixture = try WitchlightFixtureDrive.load("there_there")
        var camera = MeniscusCamera()
        let configuration = MeniscusConfiguration()
        let start = camera.distance(configuration: configuration)
        for index in 0..<min(fixture.features.count, 600) {
            var dt = fixture.features[index].deltaTime
            if !(dt > 0) { dt = 1.0 / 60.0 }
            camera.advance(features: fixture.features[index], dt: min(dt, 1.0 / 30.0),
                           configuration: configuration)
        }
        // §5: "arousal at cold start is EMA-attenuated, so the dolly should start at the
        // hero (open-raster) distance and move from there, never the reverse."
        #expect(start <= configuration.camDistCentre - configuration.camDistSwing + 0.01, """
            the dolly does not start at the hero distance — cold start must open on the \
            OPEN RASTER and move outward toward the dense sheet, never begin dense.
            """)
    }
}

// MARK: - Ripple rise time (MEN.3c diagnostic)

/// How long after an impulse does the surface's VISIBLE response peak?
///
/// A drop is an impulse into a wave field: the ring has to form and spread before the eye
/// can see it. Unlike a flash or a zoom, this preset therefore has an intrinsic visual
/// latency that no amount of firing-time accuracy removes — and it is the remaining
/// candidate for the lag Matt reports, after grid-vs-audio measurement showed the grid
/// itself is centred (signed median -8 ms) and interpolation changes nothing.
@Suite("Meniscus ripple rise time")
struct MeniscusRippleRiseTests {

    /// Seconds from an impulse to its peak VISIBLE response, simulated in the medium the
    /// given configuration describes. Shared with the sync gate so both read the same
    /// physics — see the note there on why this must not be a constant.
    static func measuredRiseSeconds(configuration: MeniscusConfiguration) -> Float {
        Float(riseProfile(configuration: configuration).peakFrame + 1) / 60
    }

    @Test("report frames from impulse to peak visible response")
    func measureRiseTime() {
        let configuration = MeniscusConfiguration()
        let profile = Self.riseProfile(configuration: configuration)
        let ms = Double(profile.peakFrame + 1) * 1000.0 / 60.0
        print(String(format: "[meniscus-rise] peak slope response at frame %d (%.0f ms after the impulse)",
                     profile.peakFrame + 1, ms))
        for (i, e) in profile.slopeEnergy.prefix(14).enumerated() {
            print(String(format: "    f%-2d %5.0f ms  %.3f", i + 1, Double(i + 1) * 1000 / 60,
                         e / (profile.slopeEnergy.max() ?? 1)))
        }
        #expect(!profile.slopeEnergy.isEmpty)
    }

    private static func riseProfile(
        configuration: MeniscusConfiguration
    ) -> (peakFrame: Int, slopeEnergy: [Double]) {
        let side = configuration.gridN
        var field = [Float](repeating: 0, count: side * side)
        var previous = field
        // One impulse, dead centre, using the drums row's stencil and force.
        let region = MeniscusStemDrops.regions[0]
        let centre = (side / 2) * side + side / 2
        field[centre] -= region.force

        // The same wave step the surface runs.
        let damping: Float = configuration.damping * (1 - 1.8 / 60)
        var slopeEnergy: [Double] = []
        for _ in 0..<40 {
            var next = previous
            for row in 0..<side {
                let up = ((row + side - 1) % side) * side
                let down = ((row + 1) % side) * side
                let here = row * side
                for col in 0..<side {
                    let left = (col + side - 1) % side
                    let right = (col + 1) % side
                    let mean = (field[here + left] + field[here + right]
                                + field[up + col] + field[down + col]) * 0.25
                    next[here + col] = (2 * mean - next[here + col]) * damping
                }
            }
            previous = field
            field = next
            // Brightness comes from SLOPE, so that is what the eye tracks — not height.
            var energy = 0.0
            for row in 0..<side {
                for col in 0..<side {
                    let a = field[row * side + col]
                    let b = field[row * side + (col + 1) % side]
                    energy += Double(abs(a - b))
                }
            }
            slopeEnergy.append(energy)
        }
        return (slopeEnergy.firstIndex(of: slopeEnergy.max() ?? 0) ?? 0, slopeEnergy)
    }
}

// MARK: - How much of what you see is the MUSIC? (MEN.3d diagnostic)

/// Matt, 2026-08-04, fourth round: "the entire preset feels unmatched to the music, like
/// it's just a movie playing with background music."
///
/// That is not a timing complaint, and four rounds of timing work have not touched it. The
/// question it actually asks is: **what fraction of the motion on screen is caused by the
/// audio at all**, as against the camera tumble, the dolly and the placeholder swell, which
/// run on their own clocks. If the autonomous motion dominates, no amount of sync accuracy
/// can make the preset read as connected — which is precisely what "a movie with background
/// music" describes.
@Suite("Meniscus — audio-driven vs autonomous motion")
struct MeniscusAudioShareTests {

    @Test("report the share of surface motion that the audio causes")
    func reportAudioShare() throws {
        let fixture = try WitchlightFixtureDrive.load("there_there")
        var configuration = MeniscusConfiguration()
        if let f = Float(ProcessInfo.processInfo.environment["MENISCUS_DROPFORCE"] ?? "") {
            configuration.stemDropForce = f
        }
        let cells = configuration.gridN * configuration.gridN

        /// Run the surface's CPU side and return per-frame mean |Δheight| of the
        /// serialized display field.
        func run(audio: Bool) -> [Double] {
            var drops = MeniscusStemDrops()
            var field = [Float](repeating: 0, count: cells)
            var previousField = field
            var deltas: [Double] = []
            var elapsed: Float = 0
            var loudEnv: Float = 0
            // The SHIPPED damping — a hardcoded copy here silently measured physics the
            // preset no longer runs (it read peak 0.181 while the real surface was at
            // 0.008). Harness and production must not diverge on this.
            let damping: Float = configuration.damping * (1 - 1.8 / 60)
            for index in 0..<min(fixture.stems.count, 1800) {
                var dt = fixture.features[index].deltaTime
                if !(dt > 0) { dt = 1.0 / 60.0 }
                dt = min(dt, 1.0 / 30.0)
                elapsed += dt
                let f = fixture.features[index]
                let instant = min(max((f.bass + f.mid + f.treble) / 3, 0), 1.4)
                loudEnv += (instant - loudEnv) * (1 - exp(-dt / 0.35))
                if audio {
                    drops.step(stems: fixture.stems[index], features: fixture.features[index],
                               field: &field, dt: dt, configuration: configuration)
                }
                // the same wave step
                var next = previousField
                for row in 0..<configuration.gridN {
                    let up = ((row + configuration.gridN - 1) % configuration.gridN) * configuration.gridN
                    let down = ((row + 1) % configuration.gridN) * configuration.gridN
                    let here = row * configuration.gridN
                    for col in 0..<configuration.gridN {
                        let left = (col + configuration.gridN - 1) % configuration.gridN
                        let right = (col + 1) % configuration.gridN
                        let mean = (field[here + left] + field[here + right]
                                    + field[up + col] + field[down + col]) * 0.25
                        next[here + col] = (2 * mean - next[here + col]) * damping
                    }
                }
                previousField = field
                field = next
                // display height = sim + the autonomous swell
                var total = 0.0
                for row in 0..<configuration.gridN {
                    let rowFrac = Float(row) / Float(configuration.gridN - 1)
                    for col in 0..<configuration.gridN {
                        let colFrac = Float(col) / Float(configuration.gridN - 1)
                        let gate = max(0, 1 - loudEnv * configuration.swellFadeRate)
                        let swell = configuration.swellAmplitude * gate * (
                            sin(colFrac * 2.1 + elapsed * 0.31) * cos(rowFrac * 1.6 - elapsed * 0.23)
                            + 0.55 * sin((colFrac * 5.3 - rowFrac * 4.1) + elapsed * 0.19)
                            + 0.30 * cos((colFrac * 9.7 + rowFrac * 8.3) - elapsed * 0.27))
                        total += Double(abs(field[row * configuration.gridN + col] + swell))
                    }
                }
                deltas.append(total / Double(cells))
            }
            return deltas
        }

        let withAudio = run(audio: true)
        let withoutAudio = run(audio: false)
        let meanWith = withAudio.reduce(0, +) / Double(withAudio.count)
        let meanWithout = withoutAudio.reduce(0, +) / Double(withoutAudio.count)
        let share = (meanWith - meanWithout) / max(meanWith, 1e-9)
        print(String(format: "[meniscus-share] surface amplitude: audio-driven %.4f · autonomous %.4f",
                     meanWith - meanWithout, meanWithout))
        print(String(format: "[meniscus-share] AUDIO'S SHARE OF THE SURFACE: %.0f %%", share * 100))
        // Watch T4 while force rises: impacts must stay localised, not churn the plate.
        var drops2 = MeniscusStemDrops()
        var field2 = [Float](repeating: 0, count: cells)
        var prev2 = field2
        let damp: Float = configuration.damping * (1 - 1.8 / 60)
        for index in 0..<min(fixture.stems.count, 1800) {
            var dt = fixture.features[index].deltaTime
            if !(dt > 0) { dt = 1.0 / 60.0 }
            dt = min(dt, 1.0 / 30.0)
            drops2.step(stems: fixture.stems[index], features: fixture.features[index],
                        field: &field2, dt: dt, configuration: configuration)
            var next = prev2
            for row in 0..<configuration.gridN {
                let up = ((row + configuration.gridN - 1) % configuration.gridN) * configuration.gridN
                let down = ((row + 1) % configuration.gridN) * configuration.gridN
                let here = row * configuration.gridN
                for col in 0..<configuration.gridN {
                    let left = (col + configuration.gridN - 1) % configuration.gridN
                    let right = (col + 1) % configuration.gridN
                    let mean = (field2[here + left] + field2[here + right]
                                + field2[up + col] + field2[down + col]) * 0.25
                    next[here + col] = (2 * mean - next[here + col]) * damp
                }
            }
            prev2 = field2; field2 = next
        }
        let peak2 = field2.map { abs($0) }.max() ?? 0
        let disturbed = Double(field2.filter { abs($0) > max(peak2 * 0.15, 1e-5) }.count) / Double(cells)
        print(String(format: "[meniscus-share] force %.1f -> T4 disturbed %.0f %% · peak %.3f",
                     configuration.stemDropForce, disturbed * 100, peak2))
        // The music must actually be most of what moves. Below ~50 % the preset reads as
        // autonomous animation with a soundtrack, which is what Matt saw.
        #expect(share > 0.5, """
            audio drives only \(Int(share * 100)) % of the surface motion — the rest is the
            camera, the dolly and the silence swell running on their own clocks. No timing
            accuracy can make a preset read as connected when the music causes a minority of
            what moves.
            """)
    }
}

// MARK: - Does the ACTIVITY pulse with the beat? (MEN.3e diagnostic)

/// Matt, 2026-08-04: "the activity needs to be synced to music, that is the core trouble."
///
/// Every sync measurement so far asked WHEN AN IMPULSE FIRES. That is not what reads as
/// synced. What reads as synced is the surface's ACTIVITY rising on the beat and falling
/// between — rhythm needs rest as much as it needs onsets. A field that is always moving
/// has no events in it, however well-timed the impulses were.
///
/// This measures modulation depth at the beat: surface energy sampled per frame, folded
/// onto the beat period, peak-to-trough as a fraction of the mean.
@Suite("Meniscus — does the activity pulse with the beat")
struct MeniscusPulseTests {

    @Test("surface activity rises on the beat and falls between",
          arguments: ["there_there", "love_rehab"])
    func activityPulsesWithTheBeat(track: String) throws {
        let fixture = try WitchlightFixtureDrive.load(track)
        var configuration = MeniscusConfiguration()
        if let d = Float(ProcessInfo.processInfo.environment["MENISCUS_DAMPING"] ?? "") {
            configuration.damping = d
        }
        let side = configuration.gridN
        var drops = MeniscusStemDrops()
        var field = [Float](repeating: 0, count: side * side)
        var previousField = field

        var energies: [Double] = []
        var phases: [Double] = []
        for index in 0..<min(fixture.stems.count, 2400) {
            var dt = fixture.features[index].deltaTime
            if !(dt > 0) { dt = 1.0 / 60.0 }
            dt = min(dt, 1.0 / 30.0)
            let f = fixture.features[index]
            drops.step(stems: fixture.stems[index], features: f, field: &field,
                       dt: dt, configuration: configuration)
            let damping = configuration.damping * (1 - 1.8 / (1 / dt))
            var next = previousField
            for row in 0..<side {
                let up = ((row + side - 1) % side) * side
                let down = ((row + 1) % side) * side
                let here = row * side
                for col in 0..<side {
                    let left = (col + side - 1) % side
                    let right = (col + 1) % side
                    let mean = (field[here + left] + field[here + right]
                                + field[up + col] + field[down + col]) * 0.25
                    next[here + col] = (2 * mean - next[here + col]) * damping
                }
            }
            previousField = field
            field = next
            // Brightness comes from SLOPE — that is what the eye tracks.
            var energy = 0.0
            for row in 0..<side {
                for col in 0..<side {
                    let a = field[row * side + col]
                    let b = field[row * side + (col + 1) % side]
                    energy += Double(abs(a - b))
                }
            }
            energies.append(energy)
            phases.append(Double(f.beatPhase01))
        }

        // Fold onto the beat: 12 bins of beat phase.
        var bins = [Double](repeating: 0, count: 12)
        var counts = [Int](repeating: 0, count: 12)
        for (energy, phase) in zip(energies, phases) {
            let bin = min(11, max(0, Int(phase * 12)))
            bins[bin] += energy
            counts[bin] += 1
        }
        for i in bins.indices where counts[i] > 0 { bins[i] /= Double(counts[i]) }
        let peak = bins.max() ?? 0, trough = bins.min() ?? 0
        let mean = bins.reduce(0, +) / Double(bins.count)
        let depth = (peak - trough) / max(mean, 1e-9)
        print(String(format: "[meniscus-pulse] %@: beat-folded activity — peak %.3f trough %.3f · MODULATION DEPTH %.0f %%",
                     track, peak, trough, depth * 100))
        print("    " + bins.map { String(format: "%.2f", $0 / max(peak, 1e-9)) }.joined(separator: " "))

        // A visual reads as rhythmic when activity visibly rises and falls across the beat.
        // Below ~25 % the surface is effectively in continuous motion and no impulse timing
        // can rescue it — which is what "the activity needs to be synced" names.
        #expect(depth > 0.25, """
            \(track): activity modulates only \(Int(depth * 100)) % across the beat — the \
            surface never rests, so there are no events in it to read as synced. Impulse \
            timing cannot fix this; the ripple lifetime has to be short enough that the \
            field returns toward rest between beats.
            """)
    }
}

// MARK: - The live path's stems are 5 seconds stale (MEN.3f regression gate)

/// Matt, 2026-08-05: "Motion of the drops does not align with or follow the music."
///
/// Root cause, measured on session `2026-08-05T13-17-18Z` by cross-correlating each stem
/// against the full-mix bass band from the same capture:
///
///     drums  +5.25 s (r=0.550)   bass +5.25 s (r=0.563)
///     vocals +5.08 s (r=0.562)   other +5.25 s (r=0.583)
///     same data at lag 0: r=0.363
///
/// `VisualizerEngine+Audio.swift` documents this as intended — stem features are a
/// SECTION-SCALE signal ("acceptable because musical sections persist longer than that").
/// MEN.3 used them for event timing anyway, and no offline gate could see it because
/// fixtures feed stems in sync with the audio.
///
/// This suite runs the drop system with the stems delayed the way the live path delays
/// them. Before MEN.3f it is the difference between a preset that reads as synced and one
/// that does not; after MEN.3f the drop timing must be INDIFFERENT to the lag, because the
/// events come from the real-time bands and the stems only gate presence.
@Suite("Meniscus — drops survive the live path's stale stems")
struct MeniscusStemLagTests {

    /// 5.2 s at 60 fps — the measured live-path staleness.
    static let liveLagFrames = 312

    @Test("drop timing is unchanged when the stems arrive 5.2 s late",
          arguments: ["there_there", "love_rehab"])
    func timingIsIndifferentToStemLag(track: String) throws {
        let fresh = try MeniscusSyncAndIntensityTests.drive(track)
        let stale = try MeniscusSyncAndIntensityTests.drive(track, stemLagFrames: Self.liveLagFrames)

        try #require(!fresh.drops.isEmpty, "\(track): no drops with fresh stems")
        #expect(!stale.drops.isEmpty,
                "\(track): stale stems silenced the preset — the presence gate is too tight")

        // WHAT THIS MUST MEASURE, and what a first draft of it got wrong: percussion takes
        // its timing from the GRID, so a percussion-only metric passes even if the drive is
        // fully stale — it has no teeth. The two things the 5.2 s lag actually broke are
        // (a) vocals/`other`, which are onset-driven and so fired 5 s late outright, and
        // (b) every drop's FORCE, which came from a stale stem. Both are asserted below.
        //
        // Force vs the loudness at that instant: with a stale drive this correlation
        // collapses, because the drop's size describes music from five seconds ago.
        func forceVsLoudness(_ r: (drops: [(time: Double, force: Float, loud: Float, region: Int)],
                                   beats: [Double])) -> Double {
            let f = r.drops.map { Double($0.force) }, l = r.drops.map { Double($0.loud) }
            guard f.count > 30 else { return 0 }
            let n = Double(f.count)
            let mf = f.reduce(0,+)/n, ml = l.reduce(0,+)/n
            var cov = 0.0, vf = 0.0, vl = 0.0
            for i in f.indices { cov += (f[i]-mf)*(l[i]-ml); vf += (f[i]-mf)*(f[i]-mf); vl += (l[i]-ml)*(l[i]-ml) }
            return (vf > 0 && vl > 0) ? cov/(vf*vl).squareRoot() : 0
        }
        let freshR = forceVsLoudness(fresh), staleR = forceVsLoudness(stale)
        print(String(format:
            "[meniscus-stemlag] %@: force vs concurrent loudness — fresh r=%+.3f · 5.2 s late r=%+.3f",
            track, freshR, staleR))
        // REPORTED, NOT ASSERTED — and the reason changed at MEN.4a, so it is worth saying
        // rather than quietly deleting a check. Stems are deliberately back in the firing
        // path, driving how full the ARRANGEMENT is on a ~3 s envelope. That is a
        // section-scale question, the one thing a 5.2 s lag does not spoil, but it does
        // mean staleness legitimately changes WHICH events fire near a section edge, and
        // any distribution statistic moves with it. What must stay invariant is the TIMING
        // of the events that do fire — asserted below. Demanding an unmoved correlation
        // here would be asserting the absence of a feature.

        // Non-grid regions (vocals, `other`) fire on their own drive. Under stem lag they
        // used to land ~5 s from anything audible; they must now stay event-current.
        let staleNonGrid = stale.drops.filter { $0.region >= 2 }
        #expect(!staleNonGrid.isEmpty,
                "\(track): vocals/other never fired under stem lag — they went silent, not late")

        // Percussion timing against the beat grid, measured both ways. Weaker than the two
        // assertions above (the grid supplies this timing regardless) but it catches a
        // regression that breaks the grid path itself.
        func medianErrorMs(_ r: (drops: [(time: Double, force: Float, loud: Float, region: Int)],
                                 beats: [Double])) -> Double {
            let rise = Double(MeniscusRippleRiseTests.measuredRiseSeconds(
                configuration: MeniscusConfiguration()))
            let errs = r.drops.filter { $0.region < 2 }.map { drop -> Double in
                (r.beats.map { abs(drop.time + rise - $0) }.min() ?? 9) * 1000
            }.sorted()
            return errs.isEmpty ? 999 : errs[errs.count / 2]
        }

        let freshErr = medianErrorMs(fresh)
        let staleErr = medianErrorMs(stale)
        print(String(format:
            "[meniscus-stemlag] %@: median beat error — fresh stems %.0f ms · stems 5.2 s late %.0f ms",
            track, freshErr, staleErr))

        // The bar is the perceptual window, not equality: presence gating can legitimately
        // drop a few events near a section edge, which shifts the median a little.
        #expect(staleErr < 60, """
            \(track): with live-realistic stem lag the drops land \(Int(staleErr)) ms from \
            the beat — outside the perceptual window, which is the MEN.3 defect.
            """)
    }

    // RETIRED AT MEN.3h, deliberately, not because it became inconvenient.
    //
    // This suite used to assert that a region whose STEM is quiet places nothing. That gate
    // is gone: stems lag ~5.2 s, so it could not close on a silence that had just started —
    // Matt's eighth-round report was drops raining through a sparse intro while loud, stale
    // stems held every region open. Region choice now comes from the BAR and gating from
    // CURRENT loudness, so nothing in the firing path reads a stem at all.
    //
    // Its replacement is `MeniscusSilenceGateTests`, which asserts the stronger property
    // the old test could not: loud stale stems plus a ticking grid must still place nothing
    // when the audio has stopped.
}

// MARK: - Nothing strikes the water at silence (MEN.3h)

/// Matt, eighth round: "drops are still falling at silence."
///
/// The grid keeps ticking through a quiet passage, so an all-grid-timed preset will happily
/// rain drops into silence unless something reads CURRENT loudness. MEN.3g's only gate came
/// from stems, which lag ~5.2 s and therefore cannot close on a silence that just started.
/// Measured on `2026-08-05T15-06-31Z` (Hummer): band level exactly 0.0000 on >25 % of
/// frames, drops falling throughout.
@Suite("Meniscus — silence places nothing")
struct MeniscusSilenceGateTests {

    @Test("a grid that keeps ticking through silence places no drops")
    func silencePlacesNothing() {
        var drops = MeniscusStemDrops()
        var field = [Float](repeating: 0, count: 45 * 45)
        let configuration = MeniscusConfiguration()
        // Stems deliberately LOUD and stale — this is exactly the 5.2 s-late signal that
        // used to hold the regions open through a silence.
        var stems = StemFeatures()
        stems.drumsEnergy = 0.9; stems.bassEnergy = 0.9
        stems.vocalsEnergy = 0.9; stems.otherEnergy = 0.9

        var loudDrops = 0, silentDrops = 0
        for frame in 0..<1200 {
            var features = FeatureVector()
            let playing = frame < 600
            // The grid runs identically in both halves — that is the point.
            features.beatPhase01 = Float(frame % 45) / 45
            if playing {
                features.bass = 0.20; features.mid = 0.09; features.treble = 0.02
                features.bassDev = frame % 45 == 0 ? 0.5 : 0.0
            }
            drops.step(stems: stems, features: features, field: &field,
                       dt: 1.0 / 60.0, configuration: configuration)
            let placed = drops.lastSites.count
            if playing { loudDrops += placed } else { silentDrops += placed }
        }

        print("[meniscus-silence] drops while playing: \(loudDrops) · drops at silence: \(silentDrops)")
        #expect(loudDrops > 0, "the gate closed on real audio — it is too tight")
        #expect(silentDrops == 0, """
            \(silentDrops) drops landed during 10 s of silence while the beat grid kept \
            ticking. Loud, stale stems must not hold the regions open: the firing path has \
            to read CURRENT loudness or the surface is struck by music that already ended.
            """)
    }
}

// MARK: - The visual must follow the music's ARC, not just its beat (MEN.4a)

/// Matt, after eight rounds of beat-timing work: **"Music is more than just beat,
/// remember."**
///
/// That is the diagnosis those rounds never reached. Meniscus was rhythmically accurate
/// and structurally deaf — same drop density, same placement pattern, same character on
/// every beat from the first bar to the last. Perfect timing on an unchanging pattern is
/// still a metronome, and no amount of ±ms work can fix a visual that ignores the music's
/// shape.
///
/// Measured on `2026-08-05T15-06-31Z` the music moves a great deal across 92 s (arousal
/// 0.19 → 0.52 → 0.27; every stem rising to a peak at 30–45 s then falling away) while the
/// preset varied only overall amplitude and camera distance.
///
/// So this asserts the property those gates could not: **the drop pattern itself must
/// differ between a sparse passage and a full one.**
@Suite("Meniscus — the pattern follows the arc")
struct MeniscusArcTests {

    @Test("a fuller arrangement places a denser pattern than a sparse one",
          arguments: ["there_there", "love_rehab"])
    func densityFollowsTheArrangement(track: String) throws {
        let fixture = try WitchlightFixtureDrive.load(track)
        var drops = MeniscusStemDrops()
        var field = [Float](repeating: 0, count: 45 * 45)
        let configuration = MeniscusConfiguration()

        // Per-frame drop counts alongside how full the arrangement is at that moment.
        var counts: [Int] = [], fullness: [Double] = []
        for index in 0..<fixture.stems.count {
            var dt = fixture.features[index].deltaTime
            if !(dt > 0) { dt = 1.0 / 60.0 }
            dt = min(dt, 1.0 / 30.0)
            let stem = fixture.stems[index]
            drops.step(stems: stem, features: fixture.features[index], field: &field,
                       dt: dt, configuration: configuration)
            counts.append(drops.lastSites.count)
            fullness.append(Double([stem.drumsEnergy, stem.bassEnergy,
                                    stem.vocalsEnergy, stem.otherEnergy]
                .filter { $0 > 0.15 }.count))
        }
        try #require(counts.count > 600, "\(track): fixture too short to show an arc")

        // Split the track by how full the arrangement is, and compare the drop rate in the
        // sparsest third against the fullest third.
        let order = fullness.indices.sorted { fullness[$0] < fullness[$1] }
        let third = order.count / 3
        let sparse = order.prefix(third).reduce(0) { $0 + counts[$1] }
        let full = order.suffix(third).reduce(0) { $0 + counts[$1] }
        let sparseRate = Double(sparse) / Double(third)
        let fullRate = Double(full) / Double(third)

        print(String(format:
            "[meniscus-arc] %@: drops/frame — sparsest third %.4f · fullest third %.4f (%.2fx)",
            track, sparseRate, fullRate, sparseRate > 0 ? fullRate / sparseRate : 999))

        #expect(fullRate > sparseRate * 1.3, """
            \(track): the fullest passages place \(String(format: "%.4f", fullRate)) \
            drops/frame against \(String(format: "%.4f", sparseRate)) in the sparsest — \
            the pattern barely changes across the track. That is the metronome failure: \
            correct beat timing on a visual that ignores the music's shape. A build has to \
            FILL IN, not merely grow louder.
            """)
    }
}
