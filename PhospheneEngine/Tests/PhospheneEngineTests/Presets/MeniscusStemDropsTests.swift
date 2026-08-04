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
            drops.step(stems: drive.stems[index], field: &field, side: side,
                       dt: dt, configuration: configuration)
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
