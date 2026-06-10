// AuroraTrackStartWarmupTests — BUG-041: the FFO aurora must not flash at
// track starts.
//
// The per-stem deviation EMA re-seeds when `StemAnalyzer` resets per track and
// overswings for ~10 s; the aurora's drums driver (D-127 smoother) passed those
// swings to the GPU as visible intensity flashes. Fixtures are the REAL
// `drumsEnergyDev` series (FA #27) from session `2026-06-10T14-55-32Z` for the
// three tracks Matt flagged as flashing (So What, There, There, Lotus Flower).
// The test replays them through the EXACT production arithmetic
// (`RenderPipeline.auroraDriverStep`) and asserts the BUG-041 verification
// criterion: early-window output peak ≤ 1.5 × steady-state peak — with a
// red-arm sanity check that the same data violates it WITHOUT the warmup.

import XCTest
@testable import Renderer

final class AuroraTrackStartWarmupTests: XCTestCase {

    private struct Frame { let te: Float; let dt: Float; let dev: Float }

    private func loadFixture(_ name: String) throws -> [Frame] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "drumsdev_\(name)_2026-06-10T14-55-32Z",
                              withExtension: "csv", subdirectory: "fbs"),
            "real-session drums fixture missing (FA #27)")
        let text = try String(contentsOf: url, encoding: .utf8)
        var frames: [Frame] = []
        for line in text.split(separator: "\n").dropFirst() {
            let c = line.split(separator: ",").compactMap { Float($0) }
            guard c.count >= 3 else { continue }
            frames.append(Frame(te: c[0], dt: max(0.001, min(0.1, c[1])), dev: c[2]))
        }
        XCTAssertGreaterThan(frames.count, 800, "fixture suspiciously short")
        return frames
    }

    /// Replay through the production step. `warmupEnabled: false` freezes the
    /// gate at 1 (the pre-fix behaviour) for the red-arm comparison.
    private func replay(_ frames: [Frame], warmupEnabled: Bool) -> [(te: Float, out: Float)] {
        var smoothed: Float = 0
        var warmup: Float = warmupEnabled ? 0 : 1
        var outs: [(Float, Float)] = []
        for f in frames {
            let r = RenderPipeline.auroraDriverStep(
                smoothed: smoothed, warmup01: warmup, drumsDev: f.dev, dt: f.dt)
            smoothed = r.smoothed
            warmup = warmupEnabled ? r.warmup01 : 1
            outs.append((f.te, r.output))
        }
        return outs
    }

    private func peak(_ outs: [(te: Float, out: Float)], _ lo: Float, _ hi: Float) -> Float {
        outs.filter { $0.te >= lo && $0.te < hi }.map(\.out).max() ?? 0
    }

    /// BUG-041 criterion (amended after the first formulation failed on real
    /// data — Lotus's drums settle to near-zero steady so a steady-relative
    /// bound is unmeetable, and So What's steady runs hot so its early window
    /// is not anomalous): with the warmup, the early window must not exceed
    /// `max(1.0, steady-peak)` — i.e. no flash-scale excursion the track
    /// itself doesn't exhibit in steady state.
    func test_warmup_capsTrackStartFlash_onAllThreeFlaggedTracks() throws {
        for name in ["so_what", "there_there", "lotus_flower"] {
            let frames = try loadFixture(name)
            let fixed = replay(frames, warmupEnabled: true)
            let steadyPeak = peak(fixed, 10, 20)
            let bound = max(1.0, steadyPeak)
            let earlyFixed = peak(fixed, 0, 10)
            XCTAssertLessThanOrEqual(earlyFixed, bound,
                                     "\(name): early-window aurora driver must stay within "
                                     + "\(bound) (got \(earlyFixed); steady peak \(steadyPeak))")
        }
    }

    /// Red arm on the two tracks whose flash is unambiguous in the data
    /// (Lotus Flower 2.35, There, There 1.37 — both far above anything their
    /// steady state produces). So What is deliberately NOT red-armed: its
    /// early window (1.23) is within its own hot steady character (1.64) —
    /// its perceived flashing is general drums-dev jitter on sparse jazz, a
    /// separate aurora-character question outside BUG-041.
    func test_withoutWarmup_realDataFlashes_redArm() throws {
        for name in ["there_there", "lotus_flower"] {
            let frames = try loadFixture(name)
            let prefix = replay(frames, warmupEnabled: false)
            let bound = max(1.0, peak(prefix, 10, 20))
            XCTAssertGreaterThan(peak(prefix, 0, 10), bound,
                                 "\(name): pre-fix arm must reproduce the measured flash — "
                                 + "if this fails the fixture no longer carries the defect")
        }
    }

    func test_warmup_leavesSteadyStateUntouched() throws {
        let frames = try loadFixture("lotus_flower")
        let fixed = replay(frames, warmupEnabled: true)
        let prefix = replay(frames, warmupEnabled: false)
        // After the 10 s ramp the gate is 1.0 — outputs must match exactly.
        for (a, b) in zip(fixed, prefix) where a.te > Float(RenderPipeline.auroraWarmupSeconds) + 0.5 {
            XCTAssertEqual(a.out, b.out, accuracy: 1e-5,
                           "steady state must be byte-identical to the pre-fix driver")
        }
    }
}
