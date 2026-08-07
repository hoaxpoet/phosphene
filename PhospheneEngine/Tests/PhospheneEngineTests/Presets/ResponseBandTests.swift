// ResponseBandTests — QG.5: gate the VISUAL response, not just the primitive.
//
// `RouteCoverageTests` (QG.1) replays the canonical fixtures and asserts every declared
// primitive VARIES. This suite replays the same fixtures and asserts the visual quantity
// each primitive drives actually MOVES A USEFUL AMOUNT.
//
// The two are different assertions and only the first existed, which is why "the gain is
// too low" is a recurring defect class rather than a one-off. Every instance below shipped
// with a GREEN route:
//
//   BUG-027 / CR.1.1  `spectral_centroid × N` traversed < 1 rung of an 11-rung ladder.
//   AGC2              `midDev` / `trebDev` structurally ~0 under a fixed 0.5 pivot.
//   FA #73            deviation primitives spike ~3×; a gain tuned against 1.0 under-drives.
//   Witchlight        pen heading turned 0.20 turns/trail against a needed 1.5+.
//
// A red band is the gate WORKING. File it in KNOWN_ISSUES and fix the preset — never widen
// the band to make it pass. That is the QG.1 floor-tuning rule, and it applies here for the
// same reason: the number came from a measurement, so moving it discards the measurement.
//
// Opt-in per route, exactly as `audio_routes` rolled out at QG.1 — a route with no
// `response` block is simply not gated yet.

import Foundation
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

@Suite("Audio response bands (QG.5)")
struct ResponseBandTests {

    /// Runtime factory per preset. A preset joins the gate by conforming its runtime to
    /// `AudioResponseMetrics` and adding a row here. Presets absent from this table but
    /// declaring a `response` block fail the completeness check below — declaring a band
    /// with no way to measure it is worse than declaring nothing.
    private static func makeRuntime(for presetID: String) -> (any AudioResponseMetrics)? {
        switch presetID {
        case "Witchlight": return WitchlightPath()
        default:           return nil
        }
    }

    /// Drive a runtime over one fixture. Per-preset because the drive shape is
    /// per-paradigm; shared helpers already exist for the presets that have them.
    private static func replay(_ runtime: any AudioResponseMetrics, presetID: String,
                               track: String) throws {
        switch presetID {
        case "Witchlight":
            guard let path = runtime as? WitchlightPath else { return }
            let drive = try WitchlightFixtureDrive.load(track)
            // WL.13 — reset BETWEEN fixtures. The runtime is built once per route and
            // replayed over each track in turn, so without this every metric after the first
            // is a cumulative average over all tracks driven so far and no failure can be
            // attributed to the fixture it names. `run` installs the pre-analysed tonal home,
            // which must follow the reset that clears it.
            path.reset()
            WitchlightFixtureDrive.run(path, over: drive)
        default:
            return
        }
    }

    // MARK: - The gate

    @Test("Every declared response band is met on the canonical fixtures (QG.5)")
    func declaredResponseBandsAreMet() throws {
        var checked = 0

        for preset in _acceptanceFixture.presets {
            let id = preset.descriptor.name
            let banded = preset.descriptor.audioRoutes.filter { $0.response != nil }
            guard !banded.isEmpty else { continue }

            let runtime = try #require(
                Self.makeRuntime(for: id),
                """
                '\(id)' declares a response band but has no runtime registered in \
                ResponseBandTests.makeRuntime. A band nobody can measure is worse than no \
                band — it reads as gated and is not.
                """)

            for route in banded {
                guard let band = route.response else { continue }
                for track in WitchlightFixtureDrive.tracks {
                    try Self.replay(runtime, presetID: id, track: track)
                    let value = try #require(
                        runtime.responseMetric(band.metric),
                        """
                        '\(id)' route '\(route.route)' declares metric '\(band.metric)' but \
                        its runtime does not publish it
                        """)

                    print(String(format: "[response] %@ / %@ / %@: %@ = %.3f  (band %.2f…%@)",
                                 id, route.route, track, band.metric, value, band.min,
                                 band.max.map { String(format: "%.2f", $0) } ?? "∞"))

                    #expect(value >= band.min, """
                        \(id) route '\(route.route)' on '\(track)': \(band.metric) = \
                        \(String(format: "%.3f", value)), below the \(band.min) floor — the \
                        primitive is alive but the VISUAL RESPONSE is inert. This is the \
                        BUG-027 / AGC2 / FA #73 class: a gain chosen against an assumed \
                        range. Fix the preset's gain; do NOT lower the floor — it came from \
                        a measurement, and moving it discards the measurement.
                        """)
                    if let ceiling = band.max {
                        #expect(value <= ceiling, """
                            \(id) route '\(route.route)' on '\(track)': \(band.metric) = \
                            \(String(format: "%.3f", value)), above the \(ceiling) ceiling — \
                            over-driven. For a path-drawing route this is the anti-reference \
                            tangle; for a luminance route it is a flash-safety risk.
                            """)
                    }
                    checked += 1
                }
            }
        }

        #expect(checked > 0, """
            No response bands were checked at all. Either no preset declares one, or the \
            loader returned nothing — a gate that vacuously passes is worse than no gate \
            (the PhotosensitivityCertificationTests static-render lesson).
            """)
    }
}
