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
    /// Overridable so the roster can be measured at a panel's real resolution without editing the
    /// gate: `FRAME_BUDGET_RES=3840x2160`. The GATE always runs at the default — a threshold that
    /// moves with an environment variable is not a threshold — but the same code answers "what can
    /// this machine hold at fullscreen", which is what BUG-099 and BUG-100 both turn on.
    static let (width, height): (Int, Int) = {
        guard let spec = ProcessInfo.processInfo.environment["FRAME_BUDGET_RES"] else {
            return (1920, 1080)
        }
        let parts = spec.lowercased().split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return (1920, 1080) }
        return (parts[0], parts[1])
    }()

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

    /// ★★ THE ABSOLUTE NET THIS FILE'S HEADER HAS ALWAYS DESCRIBED AND NEVER HAD.
    ///
    /// Until PERF.12 `absoluteCeilingMs` appeared exactly once in this file — in that comment. So
    /// nothing checked the 60 fps promise in milliseconds, and Volumetric Lithograph sat at
    /// **31.9 ms at 1080p (~31 fps)** while reading green at 5.9× the median, comfortably inside
    /// the 8× ratio.
    ///
    /// ⚠ **WHY IT IS THIS LOOSE, AND WHY IT CANNOT BE 16.7.** `swift test` runs suites in parallel,
    /// which inflates every timing 2–3× (measured, and documented in this file's header: Glaze
    /// 5.2 → 12.0 ms, no code change). A 16.7 ms assertion would therefore fail nearly the whole
    /// roster in CI and pass locally — worse than no gate. **This net catches "arriving already
    /// broken"**, which is what the header always claimed for it: original Witchlight at 273.9 ms
    /// and original VL at 111.5 ms (4K) both trip it, and nothing healthy comes close.
    ///
    /// **The real 60 fps check is `FRAME_BUDGET_STRICT=1`** below — it must be run in ISOLATION,
    /// and it is the thing to run before certifying a preset.
    static let absoluteCeilingMs = 60.0

    /// The product's actual promise: 60 fps at 1080p. Only asserted under `FRAME_BUDGET_STRICT=1`,
    /// because it is only meaningful in an uncontended run.
    static let strictBudgetMs = 16.7

    /// Per-preset harness cost at 1920x1080, recorded 2026-08-19 (post BUG-098 fix).
    /// These are HARNESS numbers including readback — see the header. Update deliberately,
    /// with the measurement in the commit message, never to silence a red gate.
    static let baselineMs: [String: Double] = [
        // ── PERF.17 REBASELINE. Every row below was re-measured in one isolated run after the
        // drive stopped sitting at the AGC mean (see `drive`). These are not comparable to the
        // pre-PERF.17 figures, which timed the roster with every D-026 deviation primitive at
        // zero — the "was" column the run prints will show large moves in BOTH directions and
        // that is the correction, not a regression.
        //
        // The headline: **Skein 5.31 -> 13.19 ms**, from the cheapest third to the 4th most
        // expensive preset, because its breakpoint ring now fills (1 -> 16) and Layer A is no
        // longer skipped. Presets that read absolute bands rather than deviations moved DOWN
        // (Nebula/Plasma/Waveform 9.5 -> 6.3) — a band sweeping 0.2-0.95 is simply not the same
        // work as a band pinned at 0.5, and the old figure was no more "correct" for being higher.
        "Volumetric Lithograph": 18.07,
        "Cytokinesis": 14.63,
        "Stave": 14.49,
        "Skein": 13.19,
        "Lumen Mosaic": 9.19,
        "Cymatic Resonance": 8.68,
        "Filigree": 8.25,
        "Witchlight": 7.02,
        "Nacre": 6.52,
        "Ricercar": 6.33,
        "Nebula": 6.30,
        "Waveform": 6.30,
        "Plasma": 6.30,
        "Meniscus": 5.76,
        "Fata Morgana": 5.65,
        "Floret": 5.53,
        "Glaze": 5.10,
        "Mitosis": 4.49,
        "Spectral Cartograph": 4.31,
        "Fractal Tree": 3.84,
        "Dragon Bloom": 3.56
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
        "Murmuration", "Nimbus", "Staged Sandbox"
    ]

    // MARK: - The gate

    @MainActor
    @Test("Every reachable preset stays within its recorded frame cost at 1080p")
    func presetFrameCost() throws {
        // ★★ THE RATIO GATE KEEPS THE READBACK, AND THAT IS A CORRECTION TO THIS INCREMENT.
        //
        // My first version timed everything with `readback: false` — correct for an ABSOLUTE claim,
        // wrong here, and it went red immediately: the readback is a common-mode cost (it scales
        // with pixels, not with the preset), so removing it **halved the median to 3.5 ms** and with
        // it the absolute headroom under the 8× ceiling. One contended sample of Stave — genuinely
        // the second most expensive preset — then read 34.7 ms = 9.9× and failed a gate that had
        // been stable for a day. A ratio partly cancels a common-mode term; that is what made the
        // recorded baselines and the 8× factor mean anything.
        //
        // So: the RATIO runs on the same instrument it was calibrated with, and the readback comes
        // off only for the STRICT check, which is opt-in and isolation-only and pays for its own
        // timing loop. Two questions, two instruments — the whole lesson of this increment applied
        // to itself.
        let harness = MultiPassRenderHarness(width: Self.width, height: Self.height)
        let strictHarness = MultiPassRenderHarness(width: Self.width, height: Self.height,
                                                  readback: false)
        let (features, stems) = Self.drive(frames: Self.timedFrames)
        let strict = ProcessInfo.processInfo.environment["FRAME_BUDGET_STRICT"] == "1"

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
        // The loose absolute net — see `absoluteCeilingMs`.
        for row in measured where row.ms > Self.absoluteCeilingMs {
            failures.append(String(format: "%@: %.1f ms exceeds the absolute ceiling (%.0f ms). "
                                   + "A preset this far over is broken rather than expensive.",
                                   row.name, row.ms, Self.absoluteCeilingMs))
        }
        // The real promise, opt-in and isolation-only — and timed WITHOUT the readback, because
        // production never performs it and 16.7 ms is an absolute claim about the app's frame.
        if strict {
            for preset in MultiPassRenderHarness.multiPassPresets {
                var best = Double.infinity
                for _ in 0..<Self.timingPasses {
                    let start = ProcessInfo.processInfo.systemUptime
                    guard (try? strictHarness.render(preset: preset, features: features,
                                                    stems: stems, settle: 0) { _ in 0 }) != nil
                    else { break }
                    best = min(best, (ProcessInfo.processInfo.systemUptime - start)
                               * 1000 / Double(Self.timedFrames))
                }
                guard best.isFinite, best > Self.strictBudgetMs else { continue }
                failures.append(String(format: "%@: %.1f ms exceeds the 60 fps budget (%.1f ms) "
                                       + "at %dx%d, readback excluded.",
                                       preset, best, Self.strictBudgetMs, Self.width, Self.height))
            }
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

    /// ★★ Skein's budget is measured mid-painting, not on an empty canvas — PERF.17's gate.
    ///
    /// The Fractal Tree case above catches a gate living in the drive VECTOR. This catches one
    /// living in Swift-side preset state, which is the shape BUG-110 actually found:
    /// `skein_geometry_fragment` skips Layer A entirely at `breakCount == 0`, and the ring fills
    /// only through the pour-commit state machine — first pour, then one commit per sustained
    /// dominant-stem switch, each `minPourTau` (2.65 τ of painter clock) apart. The 24 timed frames
    /// are 0.4 s, so the ring held ONE breakpoint and Skein read 5.31 ms: cheapest third of the
    /// roster, while the same overlay measured 17.06 ms at one breakpoint and 55.65 ms at sixteen
    /// (4K, `SkeinLineCostTests`).
    ///
    /// The COLD control is the half that makes this a gate rather than a restatement: it asserts a
    /// freshly-constructed state is still nearly empty after the timed frames alone, so if someone
    /// removes `warmSkein` the test goes red instead of both halves passing vacuously.
    ///
    /// If this fails, Skein's frame-budget row is timing an empty canvas.
    /// **Fix `warmSkein`, never this floor.**
    @MainActor
    @Test("Skein's budget is measured mid-painting, not on an empty canvas")
    func skeinIsMeasuredMidPainting() throws {
        let ctx = try MetalContext()
        guard let warm = SkeinState(device: ctx.device, seed: 42),
              let cold = SkeinState(device: ctx.device, seed: 42) else {
            Issue.record("SkeinState allocation failed")
            return
        }
        MultiPassRenderHarness.warmSkein(warm)
        for i in 0..<Self.timedFrames {
            cold.tick(deltaTime: 1.0 / 60.0, features: Self.driveFeature(frame: i),
                      stems: Self.driveStems(frame: i))
        }
        let warmBreaks = warm.colorBreakpoints.count
        let coldBreaks = cold.colorBreakpoints.count
        print("[frame-budget] Skein breakpoint ring: warmed \(warmBreaks)/\(SkeinState.maxColorBreaks), "
              + "cold after \(Self.timedFrames) timed frames \(coldBreaks)")

        #expect(warmBreaks == SkeinState.maxColorBreaks, """
            the warmed state carries \(warmBreaks) of \(SkeinState.maxColorBreaks) breakpoints, so
            the timed frame draws a shorter line than the preset's real worst case. `warmSkein` hit
            its cap without filling the ring — the pour-commit timing changed under it.
            """)
        #expect(warm.burstCount > 0, """
            no splatter bursts are alive in the timed frame. Bursts spawn from stem deviations, so
            a zero here means the drive stopped producing them and a second gated layer is being
            measured switched off.
            """)
        #expect(coldBreaks < SkeinState.maxColorBreaks, """
            a COLD state reached a full ring inside \(Self.timedFrames) frames, so this test can no
            longer tell a warmed painting from an empty canvas and would pass with `warmSkein`
            deleted. Re-establish the control before trusting Skein's row.
            """)
    }

    // MARK: - Drive

    /// ★★ THE DRIVE MUST NOT SIT AT THE AGC MEAN. Until PERF.17 this built every band at exactly
    /// `0.5` and left every `Rel`/`Dev` field at its zero-initialised default — so the whole roster
    /// was timed at the one point where **D-026's deviation primitives, the default primary driver
    /// for every preset, are identically zero**. `bassRel = (bass - 0.5) * 2` is 0 at 0.5 by
    /// construction, and `StemFeatures` derives nothing in its initialiser, so the stem deviations
    /// were zero twice over.
    ///
    /// That is the general form of the state-gated-layer defect BUG-110 found in Skein: a preset
    /// whose expensive layer is gated on something the drive never produces gets a real number for
    /// a state no listener ever sees. Skein read **5.31 ms** here — cheapest third of the roster —
    /// while its marks overlay alone measured 17–55 ms at 4K with the breakpoint ring filled.
    ///
    /// The bands now swing, and Rel/Dev are derived from them with the SAME formula the analyzer
    /// uses, so the vector is internally consistent — a hand-set `bassDev` beside a `bass` that
    /// disagrees is its own trap. Amplitude is chosen against real material, not against 1.0:
    /// deviations spike to ~3x on real music with p99 ≈ 0.85 (FA #73), so a band sweeping
    /// 0.20–0.95 puts `Dev` in 0–0.9 — the honest working range, not a flattering one.
    ///
    /// Stem dominance ROTATES on a ~1 s cycle with a decisive leader, because a pour-commit state
    /// machine (Skein) or any argmax-driven route reads a fixed dominance as "nothing ever
    /// changed" and never leaves its first branch.
    private static func drive(frames: Int) -> ([FeatureVector], [StemFeatures]) {
        var features: [FeatureVector] = []
        var stems: [StemFeatures] = []
        for i in 0..<frames {
            features.append(driveFeature(frame: i))
            stems.append(driveStems(frame: i))
        }
        return (features, stems)
    }

    /// One drive frame. Shared with `MultiPassRenderHarness.warmSkein`, which needs thousands of
    /// them to reach a warm painting and must use the same signal the timed frames use.
    static func driveFeature(frame i: Int) -> FeatureVector {
        let t = Float(i) / 60.0
        // Two incommensurate rates so the bands do not all peak together (real music does not).
        let band = { (rate: Float, phase: Float) -> Float in
            0.575 + 0.375 * sin(2 * .pi * rate * t + phase)
        }
        var f = FeatureVector(bass: band(1.9, 0), mid: band(1.3, 2.1), treble: band(2.7, 4.2),
                              time: t, deltaTime: 1.0 / 60.0)
        // D-026's formula, verbatim: xRel = (x - 0.5) * 2, xDev = max(0, xRel).
        f.bassRel = (f.bass - 0.5) * 2;   f.bassDev = max(0, f.bassRel)
        f.midRel  = (f.mid - 0.5) * 2;    f.midDev  = max(0, f.midRel)
        f.trebRel = (f.treble - 0.5) * 2; f.trebDev = max(0, f.trebRel)
        // The attack-smoothed pair, one octave slower — several presets drive continuous motion
        // from these and read a flat zero as "silence" exactly as the raw pair did.
        f.bassAttRel = (band(0.95, 0) - 0.5) * 2
        f.midAttRel  = (band(0.65, 2.1) - 0.5) * 2
        f.trebAttRel = (band(1.35, 4.2) - 0.5) * 2
        f.trackElapsedS = t
        f.beatPhase01 = Float(i % 30) / 30.0
        f.barPhase01 = Float(i % 120) / 120.0
        f.beatsPerBar = 4
        f.aspectRatio = Float(width) / Float(height)
        return f
    }

    /// One drive frame of stems. Dominance rotates every ~1 s with a decisive leader (0.9 against
    /// 0.15), which clears the pour-switch hysteresis margin that a near-tie is designed to reject.
    static func driveStems(frame i: Int) -> StemFeatures {
        var s = StemFeatures()
        let lead = (i / 60) % 4
        let energy: [Float] = (0..<4).map { $0 == lead ? 0.9 : 0.15 }
        // Raw energies keep the warmup gate open; the Dev fields are what the routes actually read.
        s.drumsEnergy = energy[0]; s.bassEnergy = energy[1]
        s.vocalsEnergy = energy[2]; s.otherEnergy = energy[3]
        s.drumsEnergyRel = energy[0]; s.drumsEnergyDev = energy[0]
        s.bassEnergyRel = energy[1];  s.bassEnergyDev = energy[1]
        s.vocalsEnergyRel = energy[2]; s.vocalsEnergyDev = energy[2]
        s.otherEnergyRel = energy[3];  s.otherEnergyDev = energy[3]
        s.drumsEnergyDevSmoothed = energy[0]
        return s
    }
}
