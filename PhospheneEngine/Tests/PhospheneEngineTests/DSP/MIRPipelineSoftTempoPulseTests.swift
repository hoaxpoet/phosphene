// MIRPipelineSoftTempoPulseTests — CSP.1 (2026-05-26) regression coverage.
//
// Locks the contract that `FeatureVector.softTempoPulse01` is:
//   - zero when the `softTempoPulseEnabled` toggle is off,
//   - zero when no `BeatGrid` is installed (cached BPM unknown),
//   - zero after the fade envelope completes (t ≥ fadeEnd),
//   - phase-humble (trough at t = 0, peak at t = T/2 within the fade window),
//   - within the declared amplitude budget at every observed timestamp,
//   - period-matched to the cached BeatGrid BPM (one peak per beat period),
//   - zero when the cached BPM is non-positive (degenerate grid).
//
// Tests use the public `MIRPipeline.process(...)` surface so the integration
// path is exercised (`elapsedSeconds` accumulation, `liveDriftTracker.hasGrid`
// gate, `FeatureVector` field write). The pulse computation is otherwise a
// pure function of (`elapsedSeconds`, cached BPM, toggle, fade constants).
//
// See CLAUDE.md §Cold-Start Phase Contract + ENGINEERING_PLAN.md §CSP.1.

import Testing
import Foundation
@testable import DSP
@testable import Shared

// MARK: - Helpers

private let fps120bpmBeatSeconds: Double = 0.5      // 60 / 120 = 0.5 s/beat
private let testFps: Float = 60.0
private let testDeltaTime: Float = 1.0 / 60.0       // 0.0167 s/frame
private let testMagnitudes = AudioFixtures.uniformMagnitudes(magnitude: 0.5)

/// Construct a `BeatGrid` at the given BPM with enough beats to keep
/// `LiveBeatDriftTracker.hasGrid` true for the duration of the test.
private func makeBeatGrid(bpm: Double, beats: Int = 64) -> BeatGrid {
    let period = 60.0 / bpm
    let positions = (0..<beats).map { Double($0) * period }
    let downbeats = stride(from: 0, to: positions.count, by: 4).map { positions[$0] }
    return BeatGrid(
        beats: positions,
        downbeats: downbeats,
        bpm: bpm,
        beatsPerBar: 4,
        barConfidence: 1.0,
        frameRate: 50.0,
        frameCount: 1500
    )
}

/// Drive `MIRPipeline` for `frames` ticks at the test fps; return the final
/// FeatureVector.
@discardableResult
private func driveFrames(_ pipeline: MIRPipeline, frames: Int) -> FeatureVector {
    var fv = FeatureVector.zero
    for i in 0..<frames {
        let t = Float(i) * testDeltaTime
        fv = pipeline.process(magnitudes: testMagnitudes, fps: testFps, time: t, deltaTime: testDeltaTime)
    }
    return fv
}

// MARK: - Toggle / Grid gating

@Test func softTempoPulse_toggleOff_isAlwaysZero() {
    let pipeline = MIRPipeline()
    pipeline.softTempoPulseEnabled = false
    pipeline.setBeatGrid(makeBeatGrid(bpm: 120))   // grid present → only the toggle gate

    // Drive several seconds — the toggle gate must keep softTempoPulse01 at 0
    // regardless of where in the fade window we are.
    for i in 0..<300 {                              // 5 s @ 60 fps
        let t = Float(i) * testDeltaTime
        let fv = pipeline.process(magnitudes: testMagnitudes, fps: testFps, time: t, deltaTime: testDeltaTime)
        #expect(fv.softTempoPulse01 == 0,
                "Toggle off but softTempoPulse01 = \(fv.softTempoPulse01) at frame \(i)")
    }
}

@Test func softTempoPulse_noGrid_isAlwaysZero() {
    let pipeline = MIRPipeline()
    // Default: softTempoPulseEnabled = true, no BeatGrid → no cached BPM.
    for i in 0..<300 {
        let t = Float(i) * testDeltaTime
        let fv = pipeline.process(magnitudes: testMagnitudes, fps: testFps, time: t, deltaTime: testDeltaTime)
        #expect(fv.softTempoPulse01 == 0,
                "No grid installed but softTempoPulse01 = \(fv.softTempoPulse01) at frame \(i)")
    }
}

@Test func softTempoPulse_degenerateZeroBPM_isAlwaysZero() {
    let pipeline = MIRPipeline()
    // Install a non-empty grid with bpm == 0 (the `BeatGrid` initialiser
    // accepts this; the empty grid trips `hasGrid == false`, but a grid
    // with non-empty beats + bpm == 0 trips `hasGrid == true` while the
    // CSP.1 path's `bpm > 0` guard takes effect).
    let degenerate = BeatGrid(
        beats: [0, 0.5, 1.0, 1.5, 2.0],
        downbeats: [0, 2.0],
        bpm: 0,
        beatsPerBar: 4,
        barConfidence: 1.0,
        frameRate: 50.0,
        frameCount: 100
    )
    pipeline.setBeatGrid(degenerate)
    for i in 0..<60 {
        let t = Float(i) * testDeltaTime
        let fv = pipeline.process(magnitudes: testMagnitudes, fps: testFps, time: t, deltaTime: testDeltaTime)
        #expect(fv.softTempoPulse01 == 0,
                "Degenerate bpm=0 grid but softTempoPulse01 = \(fv.softTempoPulse01) at frame \(i)")
    }
}

// MARK: - Phase-humble shape

@Test func softTempoPulse_atFirstFrame_isNearTrough() {
    // Trough-at-t=0 contract: visual warms up smoothly. First frame after
    // reset is `elapsedSeconds = deltaTime ≈ 16.7 ms`. Pulse value at that
    // instant should be very close to 0 (within ~1 % of amplitude budget).
    let pipeline = MIRPipeline()
    pipeline.setBeatGrid(makeBeatGrid(bpm: 120))
    let fv = pipeline.process(
        magnitudes: testMagnitudes,
        fps: testFps,
        time: 0,
        deltaTime: testDeltaTime
    )
    #expect(fv.softTempoPulse01 < 0.005,
            "First-frame softTempoPulse01 = \(fv.softTempoPulse01) — expected near-trough (≪ 0.005)")
}

@Test func softTempoPulse_atHalfPeriod_isNearPeakAmplitude() {
    // At t = T/2 inside the fade window, pulse is at full amplitude (fade = 1)
    // × peak shape value (1.0 × 1.0 = 1.0) × amplitudeBudget (0.25). Allow
    // ~2 % slop for one-frame quantisation.
    let pipeline = MIRPipeline()
    pipeline.setBeatGrid(makeBeatGrid(bpm: 120))         // T = 0.5 s
    // 15 frames @ 60 fps = 0.25 s = T/2. fadeStart = 6 s, well past us.
    let fv = driveFrames(pipeline, frames: 15)
    let expectedPeak = Float(0.25)                       // softTempoPulseAmplitude
    let observed = fv.softTempoPulse01
    #expect(observed > expectedPeak * 0.98 && observed <= expectedPeak * 1.001,
            "T/2 softTempoPulse01 = \(observed) — expected ≈ \(expectedPeak)")
}

@Test func softTempoPulse_atFullPeriod_isNearTrough() {
    // After one full period, the pulse should be back at trough (≈ 0).
    let pipeline = MIRPipeline()
    pipeline.setBeatGrid(makeBeatGrid(bpm: 120))         // T = 0.5 s
    // 30 frames @ 60 fps = 0.5 s = T. fadeStart = 6 s, fade still 1.0.
    let fv = driveFrames(pipeline, frames: 30)
    #expect(fv.softTempoPulse01 < 0.005,
            "Full-period softTempoPulse01 = \(fv.softTempoPulse01) — expected near-trough (≪ 0.005)")
}

// MARK: - Amplitude budget

@Test func softTempoPulse_neverExceedsAmplitudeBudget() {
    let pipeline = MIRPipeline()
    let budget = pipeline.softTempoPulseAmplitude
    pipeline.setBeatGrid(makeBeatGrid(bpm: 120))
    // Drive 4 seconds @ 60 fps = 240 frames. Within fade window (0–6 s
    // full amplitude), the peak value should be ≤ budget by construction.
    for i in 0..<240 {
        let t = Float(i) * testDeltaTime
        let fv = pipeline.process(magnitudes: testMagnitudes, fps: testFps, time: t, deltaTime: testDeltaTime)
        #expect(fv.softTempoPulse01 <= budget + 1e-6,
                "Frame \(i): softTempoPulse01 = \(fv.softTempoPulse01) exceeds budget \(budget)")
        #expect(fv.softTempoPulse01 >= 0,
                "Frame \(i): softTempoPulse01 = \(fv.softTempoPulse01) negative")
    }
}

// MARK: - Fade envelope

@Test func softTempoPulse_afterFadeEnd_isZero() {
    let pipeline = MIRPipeline()
    pipeline.setBeatGrid(makeBeatGrid(bpm: 120))
    // Drive 13 seconds @ 60 fps = 780 frames. fadeEnd = 12 s, so the last
    // ~60 frames should observe softTempoPulse01 == 0 regardless of pulse
    // shape position within the period.
    let fv = driveFrames(pipeline, frames: 780)
    #expect(fv.softTempoPulse01 == 0,
            "Post-fade softTempoPulse01 = \(fv.softTempoPulse01) — expected 0")
}

@Test func softTempoPulse_resetReturnsToFullFade() {
    // After `MIRPipeline.reset()` (track change), `elapsedSeconds` returns
    // to 0 and the fade envelope is re-armed at full amplitude.
    let pipeline = MIRPipeline()
    pipeline.setBeatGrid(makeBeatGrid(bpm: 120))
    _ = driveFrames(pipeline, frames: 780)     // past fade window
    // After reset (track change), grid reinstalled, drive past T/2.
    pipeline.reset()
    pipeline.setBeatGrid(makeBeatGrid(bpm: 120))
    let fv = driveFrames(pipeline, frames: 15) // T/2 again
    let expectedPeak = Float(0.25)
    #expect(fv.softTempoPulse01 > expectedPeak * 0.98,
            "Post-reset softTempoPulse01 at T/2 = \(fv.softTempoPulse01) — expected ≈ \(expectedPeak)")
}

// MARK: - Period match

@Test func softTempoPulse_periodMatchesCachedBPM() {
    // Two peaks one period apart (T/2 and 3T/2) should both read the
    // amplitude budget within ~2 %; trough at T should read ≪ both.
    let pipeline = MIRPipeline()
    pipeline.setBeatGrid(makeBeatGrid(bpm: 120))   // T = 0.5 s = 30 frames
    let peakA = driveFrames(pipeline, frames: 15)  // t = 0.25 s = T/2
    let trough = driveFrames(pipeline, frames: 15) // t = 0.50 s = T
    let peakB = driveFrames(pipeline, frames: 15)  // t = 0.75 s = 3T/2
    let budget = Float(0.25)
    #expect(peakA.softTempoPulse01 > budget * 0.98,
            "peakA = \(peakA.softTempoPulse01)")
    #expect(trough.softTempoPulse01 < 0.005,
            "trough = \(trough.softTempoPulse01)")
    #expect(peakB.softTempoPulse01 > budget * 0.98,
            "peakB = \(peakB.softTempoPulse01)")
}

@Test func softTempoPulse_differentBPMs_produceDifferentPeriods() {
    // 60 BPM → T = 1.0 s → peak at t = 0.5 s = 30 frames @ 60 fps.
    // 240 BPM → T = 0.25 s → peak at t = 0.125 s = ~7.5 frames @ 60 fps;
    //          the next peak is at 0.375 s = ~22.5 frames.
    // At 30 frames (= 0.5 s), 240 BPM is at a TROUGH (2 full periods elapsed),
    // while 60 BPM is at a PEAK (T/2).
    let slow = MIRPipeline()
    slow.setBeatGrid(makeBeatGrid(bpm: 60))
    let fast = MIRPipeline()
    fast.setBeatGrid(makeBeatGrid(bpm: 240))
    let slowFv = driveFrames(slow, frames: 30)
    let fastFv = driveFrames(fast, frames: 30)
    #expect(slowFv.softTempoPulse01 > 0.20,
            "60 BPM at t=0.5 s should be near peak; got \(slowFv.softTempoPulse01)")
    #expect(fastFv.softTempoPulse01 < 0.005,
            "240 BPM at t=0.5 s (= 2T) should be at trough; got \(fastFv.softTempoPulse01)")
}
