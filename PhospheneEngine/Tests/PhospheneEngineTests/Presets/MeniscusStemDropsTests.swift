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
    private static func drive(_ track: String, configuration: MeniscusConfiguration = .init())
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
            drops.step(stems: fixture.stems[index], features: f, field: &field,
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

    @Test("drums and bass land ON the cached grid, not near it",
          arguments: ["there_there", "love_rehab"])
    func percussionIsGridLocked(track: String) throws {
        let result = try Self.drive(track)
        try #require(result.beats.count > 8, "\(track): fixture carries no usable BeatGrid")
        // Drums (0) and bass (1) take their timing from the grid; vocals and `other` do not.
        let percussion = result.drops.filter { $0.region < 2 }
        try #require(!percussion.isEmpty, "\(track): no percussion drops at all")

        let errors = percussion.map { drop in
            (result.beats.map { abs(drop.time - $0) }.min() ?? 9) * 1000
        }.sorted()
        let median = errors[errors.count / 2]
        let withinWindow = Double(errors.filter { $0 < 60 }.count) / Double(errors.count)
        print(String(format: "[meniscus-sync] %@: %d percussion drops · median %.0f ms to beat · %.0f%% within 60 ms",
                     track, percussion.count, median, withinWindow * 100))

        // Matt, live 2026-08-04: "not in sync with the music". Measured then: median
        // 200 ms, 8-10 % inside the ~60 ms perceptual window — uncorrelated. Live onset
        // crossings cannot do better; the audio hierarchy says beat-locked motion is valid
        // only on the CACHED grid (D-153→D-158), which is what this asserts.
        #expect(withinWindow > 0.9, """
            \(track): only \(Int(withinWindow * 100)) % of percussion drops land within 60 ms \
            of a grid beat (median \(Int(median)) ms). They are not grid-locked, so they will \
            read as out of sync exactly as they did live.
            """)
    }

    // MARK: - Intensity

    @Test("drop force tracks loudness — quiet passages ripple less than loud ones",
          arguments: ["there_there", "love_rehab"])
    func forceTracksIntensity(track: String) throws {
        let result = try Self.drive(track)
        try #require(result.drops.count > 40, "\(track): too few drops to compare quartiles")
        let byLoudness = result.drops.sorted { $0.loud < $1.loud }
        let quarter = max(byLoudness.count / 4, 1)
        let quiet = byLoudness.prefix(quarter).map { Double($0.force) }
        let loud = byLoudness.suffix(quarter).map { Double($0.force) }
        let quietMean = quiet.reduce(0, +) / Double(quiet.count)
        let loudMean = loud.reduce(0, +) / Double(loud.count)
        let ratio = loudMean / max(quietMean, 1e-6)

        // CORRELATION IS THE GATE, ratio is reported. A quartile ratio partly measures the
        // TRACK: there_there is consistently loud and simply has less dynamic range than
        // love_rehab, so demanding a fixed ratio everywhere would push toward exaggerating
        // dynamics the music does not have. Correlation asks the right question — does
        // force follow loudness at all — and is the direct refutation of what was measured
        // on Matt's session, r = +0.004.
        let forces = result.drops.map { Double($0.force) }
        let louds = result.drops.map { Double($0.loud) }
        let meanForce = forces.reduce(0, +) / Double(forces.count)
        let meanLoud = louds.reduce(0, +) / Double(louds.count)
        let cov = zip(forces, louds).map { ($0 - meanForce) * ($1 - meanLoud) }.reduce(0, +)
        let sdForce = (forces.map { ($0 - meanForce) * ($0 - meanForce) }.reduce(0, +)).squareRoot()
        let sdLoud = (louds.map { ($0 - meanLoud) * ($0 - meanLoud) }.reduce(0, +)).squareRoot()
        let r = cov / max(sdForce * sdLoud, 1e-9)
        print(String(format: "[meniscus-intensity] %@: force vs loudness r=%+.3f · quiet %.3f → loud %.3f (%.2fx)",
                     track, r, quietMean, loudMean, ratio))

        // Matt, live: "nothing tied to the intensity of the music, so the drops look the
        // same regardless of whether the music is quiet / loud". Measured then: r = +0.004,
        // both quartiles at 0.57. Deviation primitives are self-normalising and carry no
        // dynamics BY CONSTRUCTION — §5's separate loudness row is what supplies them.
        // Per-drop force carries SOME intensity, but the dominant carrier is the
        // surface amplitude (§5's actual wording), gated in MeniscusMultiFrameRenderTest.
        // Here the bar only has to show the route reaches the impacts at all — against
        // the r = +0.004 measured on Matt's session.
        #expect(r > 0.10, """
            \(track): force vs loudness r=\(String(format: "%.3f", r)) — the loudness route \
            is not reaching the impacts, and the surface will look the same loud or quiet, \
            which is exactly what Matt reported. Deviation primitives cannot carry this; \
            §5's separate loudness → wave-amplitude row is what does.
            """)
    }
}
