// RayMarchCostCurveTests — is ray-march cost a STEP or a CURVE in marched pixels?
//
// PERF.14 concluded "STEP, not a curve" from two live readings of Volumetric Lithograph
// (0.5 → 175 ms at 4K, 0.4 → ≤ 15 ms) and capped marched pixels on the strength of it.
// PERF.15 then measured the same nominal configuration at 31 ms, 5.6× apart. Both live
// readings have instrument problems the other cannot rule out: PERF.14's cheap end sits
// on the documented ~15.3 ms vsync floor (so its magnitude is unmeasured), and PERF.14's
// own session log is past retention, so its `render_scale=` line cannot be read back.
//
// This sweep answers the part that matters — the SHAPE — without another live session.
// A discontinuity is a discontinuity in any instrument; the harness reading ~0.56× of
// live GPU time shifts the curve, it cannot manufacture or erase a cliff in it.
//
// Readback is OFF deliberately: it is a common-mode cost that scales with pixels, which
// is the sweep variable. `PresetFrameBudgetTests` keeps it for its RATIO gate; an
// absolute cost-vs-area curve must not carry it.
//
// Diagnostic, not a gate: set `RAYMARCH_COST_SWEEP=1` to run. Sizes are DRAWABLE sizes;
// Volumetric Lithograph declares render_scale 0.5, so marched pixels are a quarter of
// each. The harness does not apply PERF.14's own cap, so the sweep sees the raw curve.

import Foundation
import Testing
@testable import Renderer
@testable import Shared

// MARK: - RayMarchCostCurveTests

@MainActor
@Suite("Ray-march cost curve (PERF.16)", .serialized)
struct RayMarchCostCurveTests {

    /// Drawable sizes, ascending. The band PERF.14 places its step in — 1.33 MP marched
    /// (its cap) to 2.07 MP marched (PERF.15's live 4K point) — is sampled four times,
    /// because a cliff between two points is indistinguishable from a curve between two points.
    static let sizes: [(Int, Int)] = [
        (1920, 1080),   // 0.52 MP marched
        (2560, 1440),   // 0.92
        (3072, 1728),   // 1.33  ← PERF.14's cap
        (3328, 1872),   // 1.56
        (3584, 2016),   // 1.81
        (3840, 2160),   // 2.07  ← PERF.15's live 4K reading
        (4352, 2448),   // 2.66
        (4864, 2736),   // 3.33
    ]

    static let timedFrames = 24
    static let passes = 3

    @Test("marched-pixel cost curve for Volumetric Lithograph")
    func costCurve() throws {
        guard ProcessInfo.processInfo.environment["RAYMARCH_COST_SWEEP"] == "1" else { return }

        let preset = "Volumetric Lithograph"
        var rows: [(mp: Double, ms: Double)] = []

        // Ascending, then the first size again at the end: if the machine drifted thermally
        // through the sweep, the repeat disagrees with the original and the run is void.
        for (w, h) in Self.sizes + [Self.sizes[0]] {
            let harness = MultiPassRenderHarness(width: w, height: h, readback: false)
            let (features, stems) = Self.drive(frames: Self.timedFrames, width: w, height: h)
            _ = try? harness.render(preset: preset, features: features, stems: stems,
                                    settle: 6) { _ in 0 }
            var best = Double.infinity
            for _ in 0..<Self.passes {
                let start = ProcessInfo.processInfo.systemUptime
                guard (try? harness.render(preset: preset, features: features, stems: stems,
                                           settle: 0) { _ in 0 }) != nil else { break }
                best = min(best, (ProcessInfo.processInfo.systemUptime - start)
                           * 1000 / Double(Self.timedFrames))
            }
            guard best.isFinite else {
                print("[cost-curve] \(w)x\(h): render failed")
                continue
            }
            let marchedMP = Double(w * h) * 0.25 / 1_000_000
            rows.append((marchedMP, best))
            print(String(format: "[cost-curve] drawable %4dx%-4d  marched %5.2f MP  %8.2f ms  %6.2f ms/MP",
                         w, h, marchedMP, best, best / marchedMP))
        }

        // Ratio between neighbours, against the area ratio between the same pair. A curve holds
        // cost-ratio ≈ area-ratio^k for one k across the sweep; a step puts one pair far above it.
        print("[cost-curve] --- neighbour ratios (cost / area) ---")
        for i in 1..<max(rows.count - 1, 1) {
            let areaRatio = rows[i].mp / rows[i - 1].mp
            let costRatio = rows[i].ms / rows[i - 1].ms
            print(String(format: "[cost-curve] %5.2f -> %5.2f MP: area %.2fx, cost %.2fx, excess %.2fx",
                         rows[i - 1].mp, rows[i].mp, areaRatio, costRatio, costRatio / areaRatio))
        }
        if let first = rows.first, let repeated = rows.last, rows.count > 1 {
            print(String(format: "[cost-curve] thermal control: %.2f ms then %.2f ms (%.1f%% drift)",
                         first.ms, repeated.ms, (repeated.ms / first.ms - 1) * 100))
        }
    }

    private static func drive(frames: Int, width: Int, height: Int)
        -> ([FeatureVector], [StemFeatures]) {
        var features: [FeatureVector] = []
        var stems: [StemFeatures] = []
        for i in 0..<frames {
            var f = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5,
                                  time: Float(i) / 60.0, deltaTime: 1.0 / 60.0)
            f.trackElapsedS = Float(i) / 60.0
            f.barPhase01 = Float(i % 60) / 60.0
            f.beatsPerBar = 4
            f.aspectRatio = Float(width) / Float(height)
            features.append(f)
            var s = StemFeatures()
            s.drumsEnergy = 0.3; s.bassEnergy = 0.3; s.otherEnergy = 0.2; s.vocalsEnergy = 0.1
            stems.append(s)
        }
        return (features, stems)
    }
}
