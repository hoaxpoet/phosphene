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
// Heading correlation — Pearson r between two heading time-series. r ≈ 1 means the pen made
// the same turns at the same times, i.e. the music is not steering it. r ≈ 0 means the
// trajectories are unrelated. It is computed on `path.heading`, UPSTREAM of tumble,
// projection, camera and scale, so no display-stage defect can move it (verified at WL.13
// task 1: varying the per-session tumble framing moves it by 0.000000).
//
// WL.13 promoted this from a probe to a GATE. Three tests, and the second and third exist
// because a band that cannot fail is worse than no band — this preset has shipped two gates
// that measured nothing (an edge-on check pinned at a constant 1.000, and a pumping metric
// identical at every setting), so the ceiling here is accompanied by a control that proves
// the metric can read SAMENESS and a falsification that proves the ceiling can TRIP.
//
//   swift test --package-path PhospheneEngine --filter WitchlightPathDivergence

import Foundation
import Testing
@testable import PresetSessionReplay
@testable import Renderer
@testable import Shared

@Suite("Witchlight path divergence (is the figure the music's?)")
struct WitchlightPathDivergenceProbe {

    /// Ceiling on the cross-track heading correlation.
    ///
    /// The threshold the WL.13 spec named. Before WL.13 the worst pair measured **+0.995**:
    /// `home` was seeded at 0 rad on every track change and took ~30 s to converge, so two
    /// harmonically-quiet tracks both spent the whole trail winding a coil and drew nearly
    /// the same trajectory. With the tonal home known ahead of playback the worst pair is
    /// **+0.808**, so this sits above the shipped value with margin and well below the
    /// regression it exists to catch.
    private static let maxCrossTrackCorrelation = 0.90

    /// Drive a fixture through the production path, with the pre-analysed tonal home
    /// installed — which is what production does for every prepared track. Without it this
    /// would measure the 15 s straight-run FALLBACK on a 21 s clip and gate a path the app
    /// does not draw.
    private static func run(_ track: String) throws -> WitchlightRun {
        let drive = try WitchlightFixtureDrive.load(track)
        return WitchlightRun.drive(drive, preAnalysedHome: WitchlightFixtureDrive.tonalHome(of: drive))
    }

    // MARK: - The gate

    @Test("the figure differs across tracks, and is identical for the same track")
    func figuresDiverge() throws {
        let figures = try WitchlightFixtureDrive.tracks.map { try Self.run($0) }

        print("\nWL.13 path divergence — per-track figure")
        for f in figures {
            print(String(format: "  %-12@ turns/trail %.2f | monotonicity %.2f | sign-crossings %.2f/s | dwell %5.2f s",
                         f.name as NSString, f.turnsPerTrail, f.monotonicity,
                         f.crossingsPerSecond, f.medianSignDwell))
        }

        print("  cross-track heading correlation (1.00 = same path regardless of music):")
        for i in 0..<figures.count {
            for j in (i + 1)..<figures.count {
                let r = witchlightCorrelation(figures[i].heading, figures[j].heading)
                print(String(format: "    %@ vs %@: r = %+.3f  (ceiling %.2f)",
                             figures[i].name as NSString, figures[j].name as NSString,
                             r, Self.maxCrossTrackCorrelation))
                #expect(r <= Self.maxCrossTrackCorrelation, """
                    '\(figures[i].name)' and '\(figures[j].name)' draw the same figure: \
                    heading correlation r = \(String(format: "%.3f", r)), over the \
                    \(Self.maxCrossTrackCorrelation) ceiling. The pen is being steered by the \
                    MECHANISM rather than by the music. The known cause of exactly this is a \
                    tonal `home` that is wrong for the track and takes the whole trail window \
                    to converge, so the curvature holds one sign and the pen winds a coil — \
                    check `ingestTonalHome` is still being called on track change before \
                    looking anywhere else. Do NOT raise this ceiling.
                    """)
            }
        }

        // CONTROL — the same music twice. If this is not 1.000 the metric is noise and every
        // number above is meaningless.
        let repeated = try Self.run(WitchlightFixtureDrive.tracks[0])
        let control = witchlightCorrelation(figures[0].heading, repeated.heading)
        print(String(format: "    CONTROL %@ vs itself: r = %+.3f\n",
                     figures[0].name as NSString, control))

        #expect(control > 0.999, """
            the control (same track twice) scored r = \(control), not 1.0 — the path is not
            deterministic, so the cross-track numbers cannot be interpreted at all.
            """)
    }

    // MARK: - The falsification

    /// **Proof the ceiling above can go red.**
    ///
    /// A gate nobody has watched fail is a gate nobody knows the polarity of. Two DIFFERENT
    /// fixtures are driven with the same harmony-blind steer — their real per-frame energy,
    /// arousal and bar phase are untouched, but `tonal_phase_fifths` is replaced on both by
    /// one identical synthetic sweep. Heading is a pure function of the excursion from tonal
    /// home, so under that substitution two different songs must draw the same figure, and
    /// the gate must catch it.
    ///
    /// Deliberately NOT a constant phase: that pins the excursion at zero, both pens run dead
    /// straight, the heading series have no variance and Pearson r is undefined — a gate that
    /// "fails" on NaN would prove nothing about its ability to detect sameness.
    @Test("the gate trips when the steer is made blind to the music (falsification)")
    func gateCatchesAHarmonyBlindSteer() throws {
        func blindDrive(_ track: String) throws -> WitchlightRun {
            var drive = try WitchlightFixtureDrive.load(track)
            var features = drive.features
            var clock: Float = 0
            for i in 0..<features.count {
                clock += features[i].deltaTime
                features[i].tonalPhaseFifths = sin(clock / 3.0) * .pi
            }
            drive = WitchlightFixtureDrive.Drive(name: track, features: features,
                                                 stems: drive.stems, sectionIndex: drive.sectionIndex)
            return WitchlightRun.drive(drive, preAnalysedHome: WitchlightFixtureDrive.tonalHome(of: drive))
        }

        let a = try blindDrive("so_what")
        let b = try blindDrive("love_rehab")
        let r = witchlightCorrelation(a.heading, b.heading)
        print(String(format: "\nWL.13 falsification — harmony-blind steer on two different tracks: r = %+.3f (ceiling %.2f)\n",
                     r, Self.maxCrossTrackCorrelation))

        #expect(r > Self.maxCrossTrackCorrelation, """
            the harmony-blind steer scored r = \(String(format: "%.3f", r)), which the \
            \(Self.maxCrossTrackCorrelation) ceiling would NOT catch. Two different songs were \
            given an identical harmonic driver and the gate above still passed them, so it is \
            not measuring what it claims to and would not notice the mechanism steering the \
            pen again. Fix the metric or the ceiling — this is the WL.12 dead-gate class.
            """)
    }
}
