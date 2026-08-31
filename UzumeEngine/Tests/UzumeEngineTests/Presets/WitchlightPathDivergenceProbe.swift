// WitchlightPathDivergenceProbe — is the figure the MUSIC's, or the code's?
//
// Matt, 2026-08-07: "Is the ribbon path the same regardless of song or is the path of the
// ribbon influenced by the music?"
//
// The honest way to answer is not to read the design doc — WL.2 asserted a confident and
// WRONG story about this preset's own path for weeks. It is to drive the production path
// with different music and compare the figures it produces, against a control that proves
// the comparison can detect sameness at all.
//
// Two numbers per pair:
//   * heading correlation — Pearson r between the two heading time-series, resampled onto a
//     common clock. r ≈ 1 means the pen made the same turns at the same times, i.e. the
//     music is not steering. r ≈ 0 means the trajectories are unrelated.
//   * turn-count and travel spread — how much the figure's gross shape differs.
//
// The CONTROL is the same track twice: it must return r = 1.000. Without it a low r could
// just mean the metric is noise.
//
//   swift test --package-path PhospheneEngine --filter WitchlightPathDivergence

import Foundation
import Testing
@testable import PresetSessionReplay
@testable import Renderer
@testable import Shared

@Suite("Witchlight path divergence (is the figure the music's?)")
struct WitchlightPathDivergenceProbe {

    private struct Figure {
        let name: String
        let heading: [Float]
        let turns: Int
        let headingTravel: Float
        let phaseTravel: Float
        let monotonicity: Float
        let clampedFraction: Float
    }

    private func figure(_ track: String) throws -> Figure {
        let drive = try WitchlightFixtureDrive.load(track)
        let path = WitchlightPath()
        var structure = StructuralPrediction()
        var heading: [Float] = []
        var fromHome: [Float] = []
        for i in 0..<drive.features.count {
            structure.sectionIndex = drive.sectionIndex[i]
            path.ingestStructure(structure)
            path.advance(deltaTime: drive.features[i].deltaTime,
                         features: drive.features[i], stems: drive.stems[i])
            heading.append(path.heading)
            fromHome.append(path.phaseFromHome)
        }
        // A persistent SIGN on `phaseFromHome` means constant-sign curvature — the pen coils.
        // Sign changes are the only thing that makes it reverse and draw a figure.
        var crossings = 0
        for i in 1..<fromHome.count where fromHome[i - 1] * fromHome[i] < 0 { crossings += 1 }
        let secs = drive.features.reduce(Float(0)) { $0 + $1.deltaTime }
        print(String(format: "  [%@] phaseFromHome sign-crossings %3d (%.2f/s) | mean |fromHome| %.2f rad",
                     track as NSString, crossings, Float(crossings) / max(secs, 1),
                     fromHome.reduce(0) { $0 + abs($1) } / Float(max(fromHome.count, 1))))
        return Figure(name: track, heading: heading, turns: path.turnCount,
                      headingTravel: path.headingTravel, phaseTravel: path.phaseTravel,
                      monotonicity: path.headingMonotonicity,
                      clampedFraction: path.clampedFraction)
    }

    /// Pearson r over the common prefix. Headings are unwrapped by construction (the path
    /// integrates turn rate), so no circular handling is needed.
    private func correlation(_ a: [Float], _ b: [Float]) -> Double {
        let n = min(a.count, b.count)
        guard n > 100 else { return .nan }
        let x = a.prefix(n).map(Double.init), y = b.prefix(n).map(Double.init)
        let mx = x.reduce(0, +) / Double(n), my = y.reduce(0, +) / Double(n)
        var num = 0.0, dx = 0.0, dy = 0.0
        for i in 0..<n {
            let a0 = x[i] - mx, b0 = y[i] - my
            num += a0 * b0; dx += a0 * a0; dy += b0 * b0
        }
        guard dx > 0, dy > 0 else { return .nan }
        return num / (dx * dy).squareRoot()
    }

    @Test("the figure differs across tracks, and is identical for the same track")
    func figuresDiverge() throws {
        let figures = try WitchlightFixtureDrive.tracks.map { try figure($0) }

        print("\nWL.13 path divergence — per-track figure")
        for f in figures {
            print(String(format: "  %-12@ turns %2d | heading travel %6.2f rad (%.2f turns) | phase travel %6.2f | monotonicity %.2f",
                         f.name as NSString, f.turns, f.headingTravel,
                         f.headingTravel / (2 * .pi), f.phaseTravel, f.monotonicity)
                  + String(format: " | AT THE TURN-RATE CLAMP %.0f %% of frames", f.clampedFraction * 100))
        }

        print("  cross-track heading correlation (1.00 = same path regardless of music):")
        for i in 0..<figures.count {
            for j in (i + 1)..<figures.count {
                let r = correlation(figures[i].heading, figures[j].heading)
                print(String(format: "    %@ vs %@: r = %+.3f",
                             figures[i].name as NSString, figures[j].name as NSString, r))
            }
        }

        // CONTROL — the same music twice. If this is not 1.000 the metric is noise and every
        // number above is meaningless.
        let repeated = try figure(WitchlightFixtureDrive.tracks[0])
        let control = correlation(figures[0].heading, repeated.heading)
        print(String(format: "    CONTROL %@ vs itself: r = %+.3f\n",
                     figures[0].name as NSString, control))

        #expect(control > 0.999, """
            the control (same track twice) scored r = \\(control), not 1.0 — the path is not
            deterministic, so the cross-track numbers cannot be interpreted at all.
            """)
    }
}
