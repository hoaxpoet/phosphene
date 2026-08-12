// BeatHoldTests — the fallback paths of the FTR.10 sample-and-hold.
//
// The hold itself is the easy half. What has to be right is every case where the beat clock
// is NOT trustworthy, because the failure mode is not "the trunk slides a bit" — it is a
// frozen tree, or a tree stepping on raw live onsets. One test per path:
//
//   steady cached grid   → steps, and only on beats
//   10 Hz quantisation   → still steps (the sd bar must survive the real analysis rate)
//   reactive / no grid   → continuous (barPhase01 is identically 0 without a BeatGrid)
//   beat-irregular grid  → continuous (D-154, earned from the interval spread not declared)
//   stalled phase        → continuous, NEVER frozen
//   cold start           → continuous through the first beats
//   track change         → evidence cleared, warm up again
//
// Drive is synthetic here on purpose, and it is not the FA #27 case: this measures a clock,
// not a musical response. The musical evidence is `FractalTreeMeshRenderTest`'s report over
// a real capture.

import Testing
import Foundation
@testable import Renderer
@testable import Shared

@Suite("BeatHold — beat sample-and-hold (FTR.10)")
struct BeatHoldTests {

    /// One frame. `surge` is a ramp in every test below, so "held" and "live" are trivially
    /// distinguishable: if the hold is engaged the returned surge lags the input.
    private static func frame(time: Float, beatPhase: Float, barPhase: Float) -> FeatureVector {
        var f = FeatureVector()
        f.time = time
        f.beatPhase01 = beatPhase
        f.barPhase01 = barPhase
        f.spectralSurge = time      // strictly increasing — a stale sample is visible
        return f
    }

    /// Feed a clock and report, per frame after `settleAfter` seconds, whether the returned
    /// vector was stale (held) or the live one.
    private static func run(
        duration: Float,
        dt: Float,
        beatTime: (Int) -> Float?,   // nil = no beat clock at all (phase pinned)
        barPhase: Float = 0.5,
        settleAfter: Float = 0
    ) -> (staleFraction: Double, distinctHeldValues: Int, seconds: Float) {
        var hold = BeatHold()
        var stale = 0
        var total = 0
        var distinct = Set<Float>()
        var index = 0
        var nextBeat = beatTime(0) ?? .infinity
        var beatIndex = 0
        var lastBeat: Float = 0
        var time: Float = 0
        while time < duration {
            // Phase ramps 0 → 1 between consecutive beat instants.
            var phase: Float = 0
            if nextBeat.isFinite {
                while time >= nextBeat {
                    lastBeat = nextBeat
                    beatIndex += 1
                    nextBeat = beatTime(beatIndex) ?? .infinity
                }
                phase = nextBeat.isFinite
                    ? min(max((time - lastBeat) / (nextBeat - lastBeat), 0), 0.999)
                    : 0
            }
            let live = frame(time: time, beatPhase: phase, barPhase: barPhase)
            let held = hold.update(live)
            if time >= settleAfter {
                total += 1
                if held.spectralSurge != live.spectralSurge { stale += 1 }
                distinct.insert(held.spectralSurge)
            }
            time += dt
            index += 1
        }
        _ = index
        return (Double(stale) / Double(max(total, 1)), distinct.count,
                duration - settleAfter)
    }

    // MARK: - It steps

    @Test("a steady cached grid: the value holds between beats and changes on the beat")
    func steadyGridSteps() {
        // 120 BPM, 10 Hz analysis. 20 s of playback; measure after the 8-interval warm-up.
        let out = Self.run(duration: 20, dt: 0.1,
                           beatTime: { Float($0) * 0.5 }, settleAfter: 6)
        let live = String(format: "%.0f", 100 * (1 - out.staleFraction))
        #expect(out.staleFraction > 0.75,
                "the held vector matched the live one on \(live)% of frames — it is not holding.")
        // 2 beats/s × 14 s ≈ 28 updates. Anything near the frame count (140) means it never
        // engaged; anything near 1 means it froze.
        let perSecond = Double(out.distinctHeldValues) / Double(out.seconds)
        #expect(perSecond > 1.5 && perSecond < 2.5, """
            the held value changed \(String(format: "%.2f", perSecond)) times/s against a \
            2.0/s beat rate — it is not stepping on the beat.
            """)
    }

    @Test("10 Hz phase quantisation on a 60 Hz feed still reads as steady")
    func quantisedPhaseStillSteps() {
        // The production shape: the renderer feeds 60 fps, but `beatPhase01` is recomputed at
        // the ~10 Hz analysis rate, so every measured interval is off by up to one tick. If
        // the steadiness bar cannot survive that, the hold never engages in the live app.
        func quantised(_ index: Int) -> Float {
            let exact = Float(index) * 0.5
            return (exact * 10).rounded() / 10       // snap to the 10 Hz analysis grid
        }
        let out = Self.run(duration: 20, dt: 1.0 / 60, beatTime: quantised, settleAfter: 6)
        #expect(out.staleFraction > 0.75, """
            quantised phase suppressed the hold (stale on only \
            \(String(format: "%.0f", 100 * out.staleFraction))% of frames) — the sd bar is \
            tighter than the analysis rate can support.
            """)
    }

    // MARK: - It falls back

    @Test("reactive mode — no BeatGrid, so no bar clock, so no stepping")
    func reactiveModeStaysContinuous() {
        // `MIRPipeline` writes barPhase01 = 0 whenever no grid is installed and fills
        // beatPhase01 from `BeatPredictor` — raw live onsets, banned as a motion driver.
        // A perfectly regular predictor ramp must still not engage the hold.
        let out = Self.run(duration: 20, dt: 0.1, beatTime: { Float($0) * 0.5 },
                           barPhase: 0, settleAfter: 6)
        #expect(out.staleFraction == 0, """
            the hold engaged with no BeatGrid installed — it would be stepping on live \
            onset-derived phase.
            """)
    }

    @Test("a beat-irregular grid (D-154) never earns the hold")
    func irregularGridStaysContinuous() {
        // Rubato: each beat lands 0.35–0.75 s after the last. Deterministic wobble, no RNG.
        var times: [Float] = [0]
        for index in 1...80 {
            let wobble: Float = [0.35, 0.72, 0.44, 0.68, 0.52][index % 5]
            times.append(times[index - 1] + wobble)
        }
        let out = Self.run(duration: 20, dt: 0.1,
                           beatTime: { $0 < times.count ? times[$0] : nil }, settleAfter: 6)
        #expect(out.staleFraction == 0, """
            the hold engaged on an irregular beat clock — a stepped trunk on a wrong grid is \
            worse than a drifting one (D-154).
            """)
    }

    @Test("a stalled phase leaves the value tracking, never frozen")
    func stalledPhaseNeverFreezes() {
        // Eight good beats, then the clock stops — the WL.2 failure mode. The hold must let
        // go rather than freeze the trunk for the rest of the track.
        let out = Self.run(duration: 30, dt: 0.1,
                           beatTime: { $0 <= 12 ? Float($0) * 0.5 : nil }, settleAfter: 12)
        #expect(out.staleFraction == 0, """
            the value stayed frozen \(String(format: "%.0f", 100 * out.staleFraction))% of \
            frames after the beat clock stopped — a frozen trunk is the one outcome worse \
            than a sliding one.
            """)
    }

    @Test("cold start — nothing steps until the grid has proved itself")
    func coldStartStaysContinuous() {
        // The grid can install with the right BPM and the wrong phase (Cold-Start Phase
        // Contract). Eight consistent intervals is ~4 s at 120 BPM; before that the preset
        // must behave exactly as it did before this increment.
        let out = Self.run(duration: 3.5, dt: 0.1, beatTime: { Float($0) * 0.5 })
        #expect(out.staleFraction == 0, """
            the hold engaged \(String(format: "%.1f", out.seconds)) s into the track, before \
            eight beat intervals could have been observed.
            """)
    }

    @Test("a track change clears the evidence")
    func trackChangeResetsTheEvidence() {
        var hold = BeatHold()
        // Warm up on track A.
        var time: Float = 0
        while time < 10 {
            _ = hold.update(Self.frame(time: time,
                                       beatPhase: (time.truncatingRemainder(dividingBy: 0.5)) / 0.5,
                                       barPhase: 0.5))
            time += 0.1
        }
        #expect(hold.isStepping, "the hold never engaged on the warm-up track")
        // Track B starts: `time` rewinds. Nothing about A's beats says anything about B's.
        let firstOfB = Self.frame(time: 0, beatPhase: 0, barPhase: 0.5)
        let held = hold.update(firstOfB)
        #expect(!hold.isStepping, "beat evidence survived a track change")
        #expect(held.spectralSurge == firstOfB.spectralSurge,
                "the new track's first frame returned the previous track's snapshot")
    }
}
