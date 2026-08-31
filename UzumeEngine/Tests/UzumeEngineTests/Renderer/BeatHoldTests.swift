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
        settleAfter: Float = 0,
        // FTR.14 — 0 is the hard FTR.10 snap, which every pre-existing case here asserts.
        glideBeats: Float = 0,
        renderDeltaTime: Float = 0
    ) -> (staleFraction: Double, distinctHeldValues: Int, seconds: Float) {
        var hold = glideBeats > 0 ? BeatHold(glideBeats: glideBeats) : BeatHold()
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
            let held = hold.update(live, renderDeltaTime: renderDeltaTime)
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

    // MARK: - FTR.13 — eased steps

    /// The raw-float blend is only correct while EVERY field is a `Float`. This is the guard the
    /// blend's doc comment promises: add an `Int32`, a `Bool` or a SIMD member to either struct
    /// and the lerp would reinterpret it as a float and produce garbage, silently.
    @Test("FTR.13: the blended structs are still float-only, so the raw-storage lerp is valid")
    func blendedStructsAreFloatOnly() {
        #expect(MemoryLayout<FeatureVector>.size % MemoryLayout<Float>.size == 0, """
            FeatureVector is \(MemoryLayout<FeatureVector>.size) bytes, not a whole number of \
            Floats — BeatHold.lerp walks it as Float and would read a partial trailing field.
            """)
        #expect(MemoryLayout<StemFeatures>.size % MemoryLayout<Float>.size == 0, """
            StemFeatures is \(MemoryLayout<StemFeatures>.size) bytes, not a whole number of Floats.
            """)
        // A float-only struct round-trips through the blend at t = 0 and t = 1 exactly. A
        // non-float field would still round-trip, so the real guard is the pair above plus
        // `CommonLayoutTest`, which locks both layouts against the MSL definitions.
        var a = FeatureVector(); a.spectralSurge = 0.25; a.bass = 0.5
        var b = FeatureVector(); b.spectralSurge = 0.75; b.bass = 0.1
        #expect(BeatHold.lerp(a, b, 0, clocksFrom: b).spectralSurge == 0.25)
        #expect(BeatHold.lerp(a, b, 1, clocksFrom: b).spectralSurge == 0.75)
        let mid = BeatHold.lerp(a, b, 0.5, clocksFrom: b)
        #expect(abs(mid.spectralSurge - 0.5) < 1e-6, "surge did not blend")
        #expect(abs(mid.bass - 0.3) < 1e-6, "a second field did not blend — is the walk striding?")
    }

    /// Clocks must NOT be blended: a phase lerped across its 1 → 0 wrap runs backwards.
    @Test("FTR.13: clocks come from the live frame, never from the blend")
    func clocksAreNotBlended() {
        var a = FeatureVector(); a.beatPhase01 = 0.97; a.time = 10
        var b = FeatureVector(); b.beatPhase01 = 0.02; b.time = 11
        var live = FeatureVector(); live.beatPhase01 = 0.31; live.time = 12; live.barPhase01 = 0.6
        let out = BeatHold.lerp(a, b, 0.5, clocksFrom: live)
        #expect(out.beatPhase01 == 0.31, "beatPhase01 was blended — 0.97→0.02 lerps BACKWARDS")
        #expect(out.time == 12, "time was blended")
        #expect(out.barPhase01 == 0.6, "barPhase01 was blended")
    }

    /// τ is TEMPO-RELATIVE, so the motion means the same thing at every BPM — the FTR.12c
    /// lesson about per-second quantities silently carrying the tempo.
    @Test("FTR.14: the glide time constant scales with the beat period")
    func glideTauIsTempoRelative() {
        let slow = BeatHold.glideTau(glideBeats: 0.25, beatPeriod: 0.638)   // 94 BPM
        let fast = BeatHold.glideTau(glideBeats: 0.25, beatPeriod: 0.484)   // 124 BPM
        #expect(abs(slow - 0.1595) < 1e-3, "94 BPM τ is \(slow), expected ~160 ms")
        #expect(fast < slow, "τ did not shorten with tempo — the glide would lag on fast tracks")
        // Before the grid yields intervals there is no period; the glide must still run.
        #expect(BeatHold.glideTau(glideBeats: 0.25, beatPeriod: nil) > 0, """
            τ collapsed with no beat period — the glide must work from frame 1, which is the
            pre-grid opening Matt has preferred at three consecutive M7s.
            """)
    }

    /// THE BUG THIS INCREMENT EXISTS FOR. The smoothing factor must come from the RENDER delta,
    /// so the same wall-clock motion happens whatever the frame rate. FTR.13 drove its ease off
    /// `beatPhase01` at ~10 Hz (BUG-087) and rendered a 2-sample staircase.
    @Test("FTR.14: the glide is frame-rate independent, not per-sample")
    func glideIsFrameRateIndependent() {
        let tau: Float = 0.16
        // Advance 160 ms as one 10 Hz-ish step versus ten 60 fps steps: same total travel.
        let oneBigStep = BeatHold.glideAlpha(deltaTime: 0.16, tau: tau)
        var remaining: Float = 1
        for _ in 0..<10 { remaining *= 1 - BeatHold.glideAlpha(deltaTime: 0.016, tau: tau) }
        let manySmall = 1 - remaining
        #expect(abs(oneBigStep - manySmall) < 0.02, """
            160 ms of glide travelled \(oneBigStep) in one step but \(manySmall) in ten — the
            smoothing is per-FRAME, not per-second, so motion speed would follow the frame rate.
            """)
        #expect(abs(oneBigStep - 0.632) < 0.01, "one τ should cover ~63 % of the remaining gap")
        #expect(BeatHold.glideAlpha(deltaTime: 0, tau: tau) == 0, """
            a zero delta advanced the glide — `advanceBeatHold` passes 0 for rows it does not
            draw, and advancing there would glide a subsampled strip at the wrong rate.
            """)
    }

    /// The whole point: with a render clock the value is essentially NEVER still. This is the
    /// bar FTR.13 would have failed — its eased hold left the value unchanged on ~91 % of
    /// rendered frames while every rate- and size-based metric called it smooth.
    @Test("FTR.14: the gliding hold is never motionless for long")
    func glidingHoldNeverFreezes() {
        let out = Self.run(duration: 20, dt: 1.0 / 60.0, beatTime: { Float($0) * 0.5 },
                           settleAfter: 6, glideBeats: 0.25, renderDeltaTime: 1.0 / 60.0)
        // `staleFraction` here counts frames where the returned value differs from the LIVE
        // frame, which under a glide is almost all of them — that is expected and not the
        // question. The question is whether the glide keeps producing NEW values.
        let perSecond = Double(out.distinctHeldValues) / Double(out.seconds)
        #expect(perSecond > 30, """
            the glided value produced only \(String(format: "%.1f", perSecond)) distinct values \
            per second against a 60 fps render clock. Below the render rate it is freezing \
            between beats, which is the "dancing the robot" look rejected at three M7s.
            """)
    }

    /// A hard `BeatHold()` must be untouched by all of the above — its tests above still assert
    /// the FTR.10 snap, and this pins the two apart explicitly.
    @Test("FTR.14: the hard hold is unchanged and still freezes between beats")
    func hardHoldStillSnaps() {
        let hard = Self.run(duration: 20, dt: 1.0 / 60.0, beatTime: { Float($0) * 0.5 },
                            settleAfter: 6)
        let glide = Self.run(duration: 20, dt: 1.0 / 60.0, beatTime: { Float($0) * 0.5 },
                             settleAfter: 6, glideBeats: 0.25, renderDeltaTime: 1.0 / 60.0)
        #expect(hard.distinctHeldValues < glide.distinctHeldValues / 5, """
            the hard hold produced \(hard.distinctHeldValues) distinct values and the glide \
            \(glide.distinctHeldValues) — they should differ by more than 5x, or `BeatHold()` \
            has silently inherited the glide and FTR.10's behaviour is gone.
            """)
    }

    // MARK: - FTR.22 — continuous target

    /// THE DEFECT THIS MODE EXISTS FOR: a value that ARRIVES has to stop. With a beat-latched
    /// target the chase converges before the next target exists, so the geometry moves, arrives,
    /// and waits — Matt's *"precise, start-and-stop pattern, like the robot dance."* Measured on
    /// his capture the shipped build was below 2 % of peak velocity on 46.5 % of frames.
    ///
    /// This asserts the property directly: feed a CONTINUOUSLY changing signal and the
    /// continuous-target mode must keep moving where the latched mode stalls.
    @Test("FTR.22: a continuous target keeps the value moving; a latched target stalls")
    func continuousTargetDoesNotStall() {
        var totalTravel: Double = 0
        func stillFraction(_ hold: BeatHold) -> Double {
            var hold = hold
            var values: [Float] = []
            let dt: Float = 1.0 / 60.0
            var time: Float = 0
            while time < 12 {
                var frame = FeatureVector()
                frame.time = time
                // 120 BPM grid, and a target that never stops moving.
                frame.beatPhase01 = (time / 0.5).truncatingRemainder(dividingBy: 1)
                frame.barPhase01 = 0.5
                frame.spectralSurge = 0.5 + 0.4 * sin(time * 0.9)
                values.append(hold.update(frame, renderDeltaTime: dt).spectralSurge)
                time += dt
            }
            let settled = Array(values.dropFirst(values.count / 2))
            let velocity = zip(settled, settled.dropFirst()).map { abs($1 - $0) }
            // FTR.23 — report ABSOLUTE travel alongside the self-normalised stillness. A
            // fraction of "frames below 2 % of PEAK" cannot detect the whole signal slowing
            // down: FTR.22 improved that figure to 14.8 % while peak velocity fell 44 % and
            // Matt's verdict was "now it barely moves".
            let peak = velocity.sorted()[Int(0.99 * Double(velocity.count - 1))]
            let still = Double(velocity.filter { $0 < peak * 0.02 }.count) / Double(velocity.count)
            totalTravel = Double(velocity.reduce(0, +))
            return still
        }
        let latched = stillFraction(BeatHold(glideBeats: 0.25))
        let latchedTravel = totalTravel
        let continuous = stillFraction(BeatHold(continuousGlideBeats: 0.12, beatSpeedBoost: 1.0))
        let continuousTravel = totalTravel
        // FTR.23 — the no-stall property is worthless if it is bought by slowing everything down.
        #expect(continuousTravel >= latchedTravel * 0.95, """
            continuous-target mode travelled \(continuousTravel) against the latched mode's \
            \(latchedTravel). FTR.22 halved the stillness figure by collapsing peak velocity 44 % \
            and Matt's verdict was "now it barely moves" — absolute travel must not regress.
            """)
        #expect(continuous < latched * 0.6, """
            continuous-target mode is still on \(continuous) of frames against the latched \
            mode's \(latched). The whole point is that a target which never stops moving cannot \
            arrive, so the geometry cannot stall — that is Matt's "start-and-stop" complaint.
            """)
    }

    /// The beat must still be legible — it modulates SPEED. And it must only do so on a trusted
    /// grid: on an untrusted one `beatPhase01` is BeatPredictor's raw-onset estimate, banned as a
    /// motion driver, so the chase has to stay at its base rate.
    @Test("FTR.22: the beat modulates chase speed, and only on a trusted grid")
    func beatModulatesSpeedOnlyWhenTrusted() {
        var reactive = BeatHold(continuousGlideBeats: 0.35, beatSpeedBoost: 3.0)
        var values: [Float] = []
        var time: Float = 0
        while time < 6 {
            var frame = FeatureVector()
            frame.time = time
            frame.beatPhase01 = (time / 0.5).truncatingRemainder(dividingBy: 1)
            frame.barPhase01 = 0                      // no bar clock => never trusted
            frame.spectralSurge = 0.5 + 0.4 * sin(time * 0.9)
            values.append(reactive.update(frame, renderDeltaTime: 1.0 / 60.0).spectralSurge)
            time += 1.0 / 60.0
        }
        #expect(!reactive.isStepping, "the grid must not be trusted with no bar clock")
        #expect(values.contains { $0 != values[0] }, """
            with an untrusted grid the value never moved — the continuous glide must still run, \
            it just must not let an untrusted phase steer its speed.
            """)
    }
}
