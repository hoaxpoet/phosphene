// MIRPipelineDriftIntegrationTests — DSP.2 S7 integration tests for the
// MIRPipeline → LiveBeatDriftTracker / BeatPredictor switch behaviour.
//
// Three contracts:
//   1. With a non-empty grid installed, beatPhase01 follows the cached grid
//      regardless of any onset signal — proves drift tracker is consulted.
//   2. With nil/empty grid (reactive mode), beatPhase01 is non-zero after a
//      few onsets — proves BeatPredictor still owns the path.
//   3. Switching the grid mid-stream takes effect on the very next frame.

import Foundation
import Testing
@testable import DSP

// MARK: - Helpers

private func uniformGrid(bpm: Double = 120, beats: Int = 32) -> BeatGrid {
    let period = 60.0 / bpm
    let beatTimes = (0..<beats).map { Double($0) * period }
    let downbeatTimes = stride(from: 0, to: beats, by: 4).map {
        Double($0) * period
    }
    return BeatGrid(
        beats: beatTimes, downbeats: downbeatTimes, bpm: bpm,
        beatsPerBar: 4, barConfidence: 1.0, frameRate: 50, frameCount: 1500
    )
}

/// Magnitude buffer that produces no onsets (silence) — 512 zeros.
private let silenceMagnitudes = [Float](repeating: 0, count: 512)

/// Magnitude buffer with strong sub-bass energy used to coax BeatDetector into
/// firing onset events. Bins 0..3 cover ~20–80 Hz at 48 kHz / 1024 fft.
private let bassImpulseMagnitudes: [Float] = {
    var m = [Float](repeating: 0, count: 512)
    for i in 0..<4 { m[i] = 5.0 }
    return m
}()

@Suite("MIRPipeline → drift tracker integration")
struct MIRPipelineDriftIntegrationTests {

    // MARK: 1. With grid: drift tracker drives phase

    @Test("withGrid_usesDriftTracker")
    func test_withGrid_usesDriftTracker() {
        let mir = MIRPipeline()
        mir.setBeatGrid(uniformGrid(bpm: 120))

        // Drive 1.0 second of silence at 100 fps. Drift tracker has a grid;
        // BeatPredictor would only output zero phase without onsets, but the
        // drift tracker uses cached beats + elapsedSeconds, so phase rises
        // monotonically across each cached 0.5 s beat window.
        let dt: Float = 0.01
        var phases: [Float] = []
        for _ in 0..<100 {
            let fv = mir.process(
                magnitudes: silenceMagnitudes, fps: 100, time: 0, deltaTime: dt
            )
            phases.append(fv.beatPhase01)
        }
        // Phase should reach > 0.5 somewhere in the first second (one full beat).
        let maxPhase = phases.max() ?? 0
        #expect(maxPhase > 0.5,
                "drift tracker should drive phase from grid, max phase = \(maxPhase)")
    }

    // MARK: 2. Without grid: BeatPredictor fallback

    @Test("withoutGrid_fallsBackToBeatPredictor")
    func test_withoutGrid_fallsBackToBeatPredictor() {
        let mir = MIRPipeline()
        // No setBeatGrid call → tracker is empty → BeatPredictor owns phase.

        // Drive 2 s with bass impulses every 0.5 s (120 BPM kick).
        let dt: Float = 0.01
        let beatPeriod: Float = 0.5
        var t: Float = 0
        var lastPhase: Float = 0
        for _ in 0..<200 {
            let frameMod = t.truncatingRemainder(dividingBy: beatPeriod)
            let mags = (frameMod < dt) ? bassImpulseMagnitudes : silenceMagnitudes
            let fv = mir.process(magnitudes: mags, fps: 100, time: 0, deltaTime: dt)
            lastPhase = fv.beatPhase01
            t += dt
        }
        // BeatPredictor needs ≥ 2 onsets to lock; after 4 beats it should
        // produce a non-zero phase between beats. We probe right after the
        // 4-second mark with a no-onset frame.
        let probe = mir.process(
            magnitudes: silenceMagnitudes, fps: 100, time: 0, deltaTime: 0.05
        )
        #expect(probe.beatPhase01 > 0,
                "BeatPredictor fallback should produce non-zero phase after onsets, got \(probe.beatPhase01) (last=\(lastPhase))")
    }

    // MARK: 3. Mid-stream grid switch takes effect immediately

    @Test("gridSwitchMidStream_takesEffectImmediately")
    func test_gridSwitchMidStream_takesEffectImmediately() {
        let mir = MIRPipeline()

        // Phase A: reactive mode (no grid) → phase comes from BeatPredictor.
        // Without onsets, BeatPredictor outputs phase 0.
        let dt: Float = 0.01
        for _ in 0..<10 {
            _ = mir.process(magnitudes: silenceMagnitudes, fps: 100, time: 0, deltaTime: dt)
        }
        let beforeSwitch = mir.process(
            magnitudes: silenceMagnitudes, fps: 100, time: 0, deltaTime: dt
        )
        #expect(beforeSwitch.beatPhase01 == 0,
                "reactive mode with silence → phase 0; got \(beforeSwitch.beatPhase01)")

        // Switch to a grid mid-stream.
        mir.setBeatGrid(uniformGrid(bpm: 120))

        // Drive enough frames for elapsedSeconds to land mid-beat (around 0.25 s
        // into a beat). Since elapsedSeconds is already ~0.11 s from phase A,
        // we just step a little more.
        for _ in 0..<20 {
            _ = mir.process(magnitudes: silenceMagnitudes, fps: 100, time: 0, deltaTime: dt)
        }
        let afterSwitch = mir.process(
            magnitudes: silenceMagnitudes, fps: 100, time: 0, deltaTime: dt
        )
        // Now phase should be drift-tracker driven and non-zero somewhere in
        // [0, 1) — definitely not stuck at 0.
        #expect(afterSwitch.beatPhase01 > 0,
                "after grid switch, drift tracker should produce non-zero phase, got \(afterSwitch.beatPhase01)")
    }
}
