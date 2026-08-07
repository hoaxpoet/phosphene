// WitchlightPenSpeedSweep — WL.13: refill the frame after the coil came out.
//
// Matt, 2026-08-07: "slow the pen down so the ribbon fills the frame again."
//
// Removing the cold-start coil (WL.13) left the pen turning less, so it covers more ground
// in the same 30 s trail, the auto-fit zooms out to hold it, and the ribbon thins: distinct
// bright cores 15 → 4 against a floor of 8, ribbon share 0.406 → 0.359 % against 0.40 %.
//
// `baseSpeed` is the lever, and the reason it works is the camera. Bead spacing is
// `speed / emissionHz` in WORLD units and is multiplied by `viewScale` on the way to the
// screen; `baseRadius` is already SCREEN-space (a fraction of half the frame height,
// `WitchlightConfiguration`), so bead SIZE on screen is fixed while spacing is not:
//
//     screen spacing / diameter = (speed / emissionHz) · viewScale / (2 · baseRadius)
//
// A zoomed-out fit shrinks the numerator against a constant denominator, which is precisely
// how the beads fused. A slower pen draws a shorter trail, the fit comes back IN, spacing
// grows again — so speed alone should recover both gates. The `emissionHz`-coupled arm is
// swept beside it as a check, since `emissionHz` is documented as solved FROM speed at a
// 1.2 spacing ratio, and that derivation assumed a world-space bead.
//
// `headingTurnsPerTrail` pulls the other way: ω_max is `speed / minTurnRadius`, so a slower
// pen turns less per trail. That is the trade this sweep exists to price.
//
//   WITCHLIGHT_SPEED_SWEEP=1 swift test --package-path PhospheneEngine \
//       --filter WitchlightPenSpeedSweep

import Foundation
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

@Suite("Witchlight pen-speed sweep (WL.13)")
struct WitchlightPenSpeedSweep {

    /// The ratio `emissionHz` was solved at: bead centres 1.2 diameters apart.
    private static let spacingRatio: Float = 1.2
    /// `WitchlightConfiguration.baseRadius` — screen-space, a fraction of half frame height.
    private static let baseRadius: Float = 0.011

    private static func tuning(speed: Float, coupleEmission: Bool) -> WitchlightTuning {
        var t = WitchlightTuning()
        t.baseSpeed = speed
        if coupleEmission {
            t.emissionHz = speed / (Self.spacingRatio * 2 * Self.baseRadius)
        }
        return t
    }

    /// Distinct bright cores in the rendered stroke — the WL.2-j gate's own measure,
    /// 4-connected components over luma > 200 with stars excluded by a minimum size.
    private static func distinctCores(_ bgra: [UInt8], width w: Int, height h: Int) -> Int {
        var core = [Bool](repeating: false, count: w * h)
        for idx in 0..<(w * h) {
            let i = idx * 4
            let luma = 0.114 * Double(bgra[i]) + 0.587 * Double(bgra[i + 1]) + 0.299 * Double(bgra[i + 2])
            core[idx] = luma > 200
        }
        var seen = [Bool](repeating: false, count: w * h)
        var count = 0, stack = [Int]()
        for start in 0..<(w * h) where core[start] && !seen[start] {
            seen[start] = true
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            var size = 0
            while let p = stack.popLast() {
                size += 1
                let x = p % w, y = p / w
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                    let q = ny * w + nx
                    if core[q] && !seen[q] { seen[q] = true; stack.append(q) }
                }
            }
            if size >= 8 { count += 1 }
        }
        return count
    }

    private static func ribbonShare(_ bgra: [UInt8], pixels: Int) -> Double {
        var lit = 0
        for i in stride(from: 0, to: bgra.count, by: 4) {
            let luma = 0.114 * Double(bgra[i]) + 0.587 * Double(bgra[i + 1]) + 0.299 * Double(bgra[i + 2])
            if luma > 120 { lit += 1 }
        }
        return 100.0 * Double(lit) / Double(pixels)
    }

    @MainActor
    @Test("pen speed vs the two framing gates and the turns band")
    func sweep() throws {
        guard ProcessInfo.processInfo.environment["WITCHLIGHT_SPEED_SWEEP"] != nil else { return }
        let w = 640, h = 360
        print("\nWL.13 pen-speed sweep — floors: cores >= 8, ribbon share >= 0.40 %, turns/trail >= 1.20")

        for couple in [false] {
            print("  --- emissionHz \(couple ? "COUPLED to speed (ratio held at 1.2)" : "left at 3.79")")
            for speed in [Float(0.10), 0.09, 0.08, 0.07, 0.065, 0.06, 0.055, 0.05] {
                var harness = MultiPassRenderHarness(width: w, height: h)
                harness.witchlightTuning = Self.tuning(speed: speed, coupleEmission: couple)
                let frames: [[UInt8]] = try harness.render(
                    preset: "Witchlight",
                    features: WitchlightSkyLuminanceTests.settledRibbonDrive(),
                    stems: WitchlightSkyLuminanceTests.settledRibbonStems(),
                    settle: 1800) { $0 }
                guard let last = frames.last else { continue }
                // Cores over the last few frames: a single frame's count swings with where
                // the beads happen to land, and a noisy scalar is a bad basis for a pick.
                let coreCounts = frames.suffix(4).map { Self.distinctCores($0, width: w, height: h) }
                let coresMin = coreCounts.min() ?? 0, coresMax = coreCounts.max() ?? 0
                // How far the fit has come back IN — the direct reading of "fills the frame".
                let probe = WitchlightPath()
                probe.overrideTuning(Self.tuning(speed: speed, coupleEmission: couple))
                let sd = WitchlightSkyLuminanceTests.settledRibbonDrive()
                let ss = WitchlightSkyLuminanceTests.settledRibbonStems()
                for i in 0..<1800 {
                    probe.advance(deltaTime: sd[i % sd.count].deltaTime,
                                  features: sd[i % sd.count], stems: ss[i % ss.count])
                }

                // turns/trail on the real fixtures, at the same tuning.
                var turns: [Double] = []
                for track in WitchlightFixtureDrive.tracks {
                    let drive = try WitchlightFixtureDrive.load(track)
                    let path = WitchlightPath()
                    path.overrideTuning(Self.tuning(speed: speed, coupleEmission: couple))
                    WitchlightFixtureDrive.run(path, over: drive)
                    turns.append(path.responseMetric("headingTurnsPerTrail") ?? 0)
                }
                let t = Self.tuning(speed: speed, coupleEmission: couple)
                print(String(format: "    speed %.3f | cores %2d–%2d | share %.3f %% | viewScale %.2f | turns/trail %.2f %.2f %.2f",
                             speed, coresMin, coresMax,
                             Self.ribbonShare(last, pixels: w * h), probe.viewScale,
                             turns[0], turns[1], turns[2]))
            }
        }
        print("")
    }
}
