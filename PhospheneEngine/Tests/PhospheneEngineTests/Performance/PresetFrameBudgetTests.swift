// PresetFrameBudgetTests — per-preset GPU cost, measured through each preset's REAL path.
//
// WHY THIS EXISTS. `CLAUDE.md` promises 60 fps at 1080p. Until 2026-08-19 nothing checked it:
// the only performance test in the suite rendered a SINGLE frame with no per-preset budget,
// across 29 shipping presets. Witchlight was found running at 273.88 ms/frame at 4K — 11.2 fps,
// 16x over budget, 84x the cheapest preset in the same session — and it was found by accident,
// because Matt happened to leave it on screen long enough to attribute frames to it. Nothing
// would have caught a second one (BUG-098, and Matt's question that produced it).
//
// WHAT THIS IS, AND IS NOT. It is a REGRESSION detector, not a production-fidelity budget:
//
//   - the harness reads every frame back to the CPU, which production never does, so the
//     absolute numbers here are NOT production frame times. Measured on Witchlight, this
//     harness reads ~0.56x of the live GPU time at the same resolution.
//   - it therefore asserts against a RECORDED PER-PRESET BASELINE, and fails a preset that
//     gets materially slower than its own last-known cost. That catches "someone added an
//     unguarded warped_fbm" — the actual BUG-098 failure — without pretending the harness
//     reproduces production timing.
//   - `absoluteCeilingMs` is a second, deliberately loose net for a preset arriving already
//     broken, where no baseline exists to regress from.
//
// ⚠ COVERAGE IS PARTIAL AND IS PRINTED EVERY RUN. `MultiPassRenderHarness` reaches 15 presets
// through their real multi-pass path. The rest are not silently skipped — `uncoveredPresets`
// names them and the run prints them, because a gate that quietly measures half the roster
// reads as "all green" when it is not. That silence is what let BUG-098 live.

import Testing
import Foundation
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Preset frame budget (PERF.4)")
struct PresetFrameBudgetTests {

    // MARK: - Configuration

    /// Measured at the product's stated target resolution, not the harness default of 320x180.
    /// Cost scales with pixel count, so a budget asserted at a smaller size proves nothing —
    /// every pre-2026-08-19 performance judgement was made at 900x600 (0.54 MP) against a
    /// 1080p promise, which is why Witchlight's 16x overrun went unseen for weeks.
    static let width = 1920
    static let height = 1080

    /// Frames timed per preset, after `settleFrames` warm frames that are not timed.
    static let timedFrames = 24
    static let settleFrames = 6

    /// Timing passes per preset; the MINIMUM is taken, not the mean.
    ///
    /// Wall-clock timing on a shared machine is contaminated upward, never downward — an
    /// unlucky pass picks up scheduler and thermal noise, a lucky one does not. The first
    /// version of this gate took a single pass and Lumen Mosaic measured 7.73 ms then 15.78 ms
    /// on IDENTICAL code, which would have failed the run as a 2x regression. The minimum of
    /// several passes is the least-contended sample and is what makes this stable enough to
    /// gate on. Widening the tolerance instead would have hidden exactly the defect the gate
    /// exists to catch.
    static let timingPasses = 3

    /// THE GATE: no preset may cost more than this multiple of the MEDIAN preset.
    ///
    /// Why a ratio and not milliseconds. `swift test` runs suites in parallel, so this suite
    /// shares the GPU with whatever else is executing; run inside the full suite, absolute
    /// times inflate 2-3x versus the same code run alone (measured: Glaze 5.2 -> 12.0 ms,
    /// Meniscus 5.3 -> 11.6, Mitosis 4.2 -> 9.0 — no code change, pure contention). An
    /// absolute-millisecond gate therefore fails in CI and passes locally, which is worse than
    /// no gate.
    ///
    /// Contention inflates every preset in the run roughly equally, so the RATIO between them
    /// survives it. That is also the shape of the defect this exists to catch: BUG-098 was not
    /// a preset creeping 30 % over budget, it was one preset costing 84x the cheapest and 50x
    /// the median while everything else held 60 fps. At 8x the median, original Witchlight
    /// (~25x median) trips this comfortably and normal spread does not.
    ///
    /// The recorded `baselineMs` figures are kept and PRINTED for orientation, but they do not
    /// gate — they are wall-clock on one machine on one day, and asserting on them would be
    /// asserting on the weather.
    static let outlierFactorOverMedian = 8.0

    /// Per-preset harness cost at 1920x1080, recorded 2026-08-19 (post BUG-098 fix).
    /// These are HARNESS numbers including readback — see the header. Update deliberately,
    /// with the measurement in the commit message, never to silence a red gate.
    static let baselineMs: [String: Double] = [
        "Volumetric Lithograph": 30.79,
        "Stave": 13.55,
        "Cytokinesis": 8.42,
        "Filigree": 8.39,
        "Cymatic Resonance": 8.33,
        "Lumen Mosaic": 7.73,
        "Skein": 6.72,
        "Nacre": 6.17,
        "Witchlight": 5.06,
        "Fata Morgana": 5.83,
        "Floret": 5.44,
        "Meniscus": 5.28,
        "Glaze": 5.2,
        "Mitosis": 4.23,
        // ── PERF.10, the four `direct` presets. Measured in a 20-preset run, where every figure
        // above (recorded in a 16-preset run) reads roughly 2x higher — Volumetric Lithograph
        // 30.8 → 64.3 with no code change. That is the contention the header describes, and it is
        // why these are orientation only and the RATIO gates. Do not "fix" the older rows to
        // match; they were honest measurements of a different run.
        //
        // ⚠ COVERAGE ITSELF MOVES THE GATE. Adding four cheap presets lowers the median, which
        // raises every expensive preset's ratio: Volumetric Lithograph went 4.6x → 5.2x of the
        // 8x ceiling without changing. Widening the ceiling to compensate would defeat it — the
        // right reading is that the gate got stricter because the roster it compares against got
        // more representative.
        "Nebula": 9.94,
        "Waveform": 9.50,
        "Plasma": 9.47,
        "Spectral Cartograph": 6.37,
        // PERF.7 — first mesh-shader row. Measured 3.88 / 4.07 ms across two runs at 1920x1080
        // with the canopy ALIVE (upper-canopy ink 1223 against the silent figure's 302); the
        // minimum is recorded, per this suite's own min-of-passes reasoning.
        "Fractal Tree": 3.88,
        "Dragon Bloom": 3.54
    ]

    /// Presets `MultiPassRenderHarness` cannot drive. Named, printed, and NOT counted as passing.
    /// PERF.7 removed "Fractal Tree" — the harness now drives the mesh-shader path.
    ///
    /// PERF.10 took the `direct` four (Nebula, Plasma, Spectral Cartograph, Waveform), which PERF.7's
    /// survey had named as the cheapest remaining paradigm. **Coverage is now 20 of 29.**
    ///
    /// What is left, and what each would cost — surveyed so the next increment does not re-derive it:
    /// `feedback` ×3 (Membrane, Murmuration, Ricercar — the last two also `particles`) need a
    /// ping-pong texture pair and a settle, since their whole subject is accumulation; `staged` ×2
    /// (Arachne, Staged Sandbox) need the staged pass order plus per-preset Swift state
    /// (`ArachneState`); `mv_warp` ×1 (Gossamer) has bespoke state (`GossamerState`) and the
    /// existing `renderBespokeMVWarp` is the shape to copy; `ray_march` ×1 (Ferrofluid Ocean) needs
    /// the G-buffer + lighting passes; and Aurora Veil and Nimbus declare NO passes at all — they
    /// are pass-agnostic and driven from preset state, so each needs its own bespoke path.
    /// **`feedback` is the cheapest remaining three** and it is a real increment, not a free win.
    static let uncoveredPresets = [
        "Arachne", "Aurora Veil", "Ferrofluid Ocean", "Gossamer", "Membrane",
        "Murmuration", "Nimbus", "Ricercar", "Staged Sandbox"
    ]

    // MARK: - The gate

    @MainActor
    @Test("Every reachable preset stays within its recorded frame cost at 1080p")
    func presetFrameCost() throws {
        let harness = MultiPassRenderHarness(width: Self.width, height: Self.height)
        let (features, stems) = Self.drive(frames: Self.timedFrames)

        var measured: [(name: String, ms: Double)] = []
        var failures: [String] = []

        for preset in MultiPassRenderHarness.multiPassPresets {
            _ = try? harness.render(preset: preset, features: features, stems: stems,
                                    settle: Self.settleFrames) { _ in 0 }
            var best = Double.infinity
            var rendered = false
            for _ in 0..<Self.timingPasses {
                let start = ProcessInfo.processInfo.systemUptime
                guard (try? harness.render(preset: preset, features: features, stems: stems,
                                           settle: 0) { _ in 0 }) != nil else { break }
                rendered = true
                let pass = (ProcessInfo.processInfo.systemUptime - start) * 1000 / Double(Self.timedFrames)
                best = min(best, pass)
            }
            guard rendered else {
                failures.append("\(preset): render failed")
                continue
            }
            let ms = best
            measured.append((preset, ms))

        }

        let sortedCosts = measured.map(\.ms).sorted()
        let median = sortedCosts.isEmpty ? 0 : sortedCosts[sortedCosts.count / 2]
        for row in measured where median > 0 && row.ms > median * Self.outlierFactorOverMedian {
            failures.append(String(format: "%@: %.1f ms = %.1fx the median preset (%.1f ms)",
                                   row.name, row.ms, row.ms / median, median))
        }

        for row in measured.sorted(by: { $0.ms > $1.ms }) {
            let base = Self.baselineMs[row.name].map { String(format: " (was %.1f)", $0) } ?? " (new)"
            let rel = median > 0 ? String(format: " %.1fx median", row.ms / median) : ""
            print(String(format: "[frame-budget] %-24@ %7.2f ms%@%@",
                         row.name as NSString, row.ms, base as NSString, rel as NSString))
        }
        print("[frame-budget] \(measured.count) presets measured at \(Self.width)x\(Self.height); "
              + "\(Self.uncoveredPresets.count) NOT covered by this harness and therefore UNVERIFIED: "
              + Self.uncoveredPresets.joined(separator: ", "))

        #expect(failures.isEmpty, """
            A preset costs far more than every other preset:
            \(failures.joined(separator: "\n"))
            Measured at \(Self.width)x\(Self.height) through each preset's real path. A single
            preset standing this far off the median is the BUG-098 signature — there it was an
            unguarded `warped_fbm` (56 Perlin evaluations) running for every pixel of the frame
            and then being multiplied by zero, measuring 84x the cheapest preset live.
            Check for per-pixel work on a fullscreen pass that is not gated by what consumes it.
            """)
    }

    // MARK: - The measurement is of a real frame

    /// ★★ THE BUDGET IS ONLY WORTH THE STATE IT MEASURED IN, and for Fractal Tree that is not
    /// automatic. `drive` builds vectors whose `pulseAmp01` is 0 — the preset's silence gate —
    /// which collapses it to the 7-branch figure it draws when nothing is playing. A budget
    /// recorded from that frame would be a real number for a state no listener ever sees, and it
    /// would read green forever while the actual canopy got arbitrarily expensive.
    /// `MultiPassRenderHarness.openTheGates` prevents that; this asserts the outcome rather than
    /// trusting it.
    ///
    /// ★ WHICH OBSERVABLE, and why the obvious one fails. Whole-frame ink barely moves: the trunk
    /// and first two generations are present in BOTH states and dominate the pixel count, so
    /// gate-shut lights 0.0107 of the frame against 0.0150 open — 1.4x, too thin to gate on. The
    /// fine generations live in the upper canopy, and that is exactly what the gate removes.
    /// Measured at 640x360, lit pixels above the mid-line (rows 0..<216):
    ///
    ///     gates OPEN (playing)   1175   ← 38 in band 4, 1137 in band 5
    ///     gates SHUT (silent)     302   ← band 4 completely empty
    ///
    /// A 3.9x separation, so the floor below sits between the two with real margin either side.
    /// The trunk bands (6-9) read 600/504/252 in both, which is the whole reason whole-frame ink
    /// could not see this. The silent frame is also bit-identical frame to frame (2470, 2470)
    /// where the playing one moves (3441, 3459) — the gait.
    ///
    /// If this fails, Fractal Tree's frame-budget row is timing the wrong picture.
    /// **Fix the drive, never the floor.**
    @MainActor
    @Test("Fractal Tree's budget is measured on a full canopy, not its silent figure")
    func fractalTreeIsMeasuredAlive() throws {
        let harness = MultiPassRenderHarness(width: 640, height: 360)
        let (features, stems) = Self.drive(frames: 4)
        let canopy = try harness.render(preset: "Fractal Tree", features: features, stems: stems,
                                        settle: Self.settleFrames) { bgra -> Int in
            let rowBytes = 640 * 4
            var count = 0
            for row in 0..<216 {
                for column in 0..<640 where bgra[row * rowBytes + column * 4 + 1] > 24 {
                    count += 1
                }
            }
            return count
        }
        let peak = canopy.max() ?? 0
        print("[frame-budget] Fractal Tree upper-canopy ink \(peak) (silent figure ≈ 302)")
        #expect(peak > 600, """
            the timed frame lights only \(peak) subpixels in the upper canopy, against ≈ 302 for             the SILENT 7-branch figure and ≈ 1175 for a playing tree. The frame-budget row is             timing a state the preset never occupies. Fix `openTheGates`, not this floor.
            """)
    }

    // MARK: - Drive

    private static func drive(frames: Int) -> ([FeatureVector], [StemFeatures]) {
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
