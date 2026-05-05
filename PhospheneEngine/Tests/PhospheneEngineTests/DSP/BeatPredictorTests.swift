// BeatPredictorTests — unit tests for the MV-3b beat phase predictor (D-028).
//
// Three contracts:
//   1. Phase rises 0→1 over a 125-BPM click track.
//   2. Phase resets to 0 after 3× estimated-period silence.
//   3. Bootstrap from a known BPM enables valid phase from the first onset
//      (phase stays 0 before any onset; after onset, phase tracks the seeded period).

import Foundation
import Testing
@testable import DSP

// MARK: - Helpers

/// Drive the predictor with `count` beats at the given BPM, returning the
/// phase value captured at the last beat's onset.
private func drivePredictor(
    _ predictor: BeatPredictor,
    bpm: Float,
    count: Int,
    beatPulse: Float = 0.8
) -> [BeatPredictor.Result] {
    let period = 60.0 / Double(bpm)
    var results: [BeatPredictor.Result] = []
    let fps: Double = 120
    let dt = 1.0 / fps
    let totalDuration = period * Double(count) + period * 0.5  // extra half-beat at end
    var time: Double = 0.0

    while time < totalDuration {
        // Fire the beat pulse exactly at each period boundary.
        var pulse: Float = 0
        let phase = time.truncatingRemainder(dividingBy: period)
        if phase < dt { pulse = beatPulse }

        let result = predictor.update(
            subBassOnset: pulse > 0.5, beatMid: 0, beatComposite: 0,
            time: Float(time), deltaTime: Float(dt)
        )
        results.append(result)
        time += dt
    }
    return results
}

// MARK: - Tests

@Test
func beatPredictor_phaseRises0to1_over125BPMClickTrack() {
    let predictor = BeatPredictor()
    // Run at 125 BPM. After a few beats the IIR period should be close to 0.48s.
    let bpm: Float = 125
    let period = Double(60.0 / bpm)  // 0.48s
    let fps = 120.0
    let dt = 1.0 / fps

    // Skip first 4 beats (IIR warmup) then capture one full cycle.
    _ = drivePredictor(predictor, bpm: bpm, count: 4)

    // After warmup, fire one more beat onset and record samples across one period.
    var phases: [Float] = []
    let beatTime = Double(4) * period
    var t = beatTime
    while t < beatTime + period {
        let pulse: Float = (t - beatTime) < dt ? 0.8 : 0
        let res = predictor.update(subBassOnset: pulse > 0.5, beatMid: 0, beatComposite: 0,
                                   time: Float(t), deltaTime: Float(dt))
        phases.append(res.beatPhase01)
        t += dt
    }

    guard !phases.isEmpty else {
        #expect(Bool(false), "No phase samples collected")
        return
    }

    // Phase should start near 0 and end near 1 over one predicted period.
    let firstPhase = phases.first ?? 0
    let lastPhase  = phases.last  ?? 0

    #expect(firstPhase < 0.1,
            "phase at beat onset should be near 0, got \(firstPhase)")
    #expect(lastPhase > 0.85,
            "phase near end of cycle should be near 1, got \(lastPhase)")

    // Phase must be monotonically non-decreasing.
    let isMonotonic = zip(phases, phases.dropFirst()).allSatisfy { $0 <= $1 + 0.001 }
    #expect(isMonotonic, "phase must be monotonically non-decreasing within one period")
}

@Test
func beatPredictor_phaseResets_after3PeriodSilence() {
    let predictor = BeatPredictor()
    let bpm: Float = 120
    let period = Double(60.0 / bpm)   // 0.5s
    let fps = 120.0
    let dt = 1.0 / fps

    // Establish period with 6 beats.
    _ = drivePredictor(predictor, bpm: bpm, count: 6)

    // Advance time by 3.5× the estimated period with no pulses.
    let silenceStart = 6 * period
    let silenceDuration = period * 3.5
    var t = silenceStart
    var lastResult = predictor.update(subBassOnset: false, beatMid: 0, beatComposite: 0,
                                      time: Float(t), deltaTime: Float(dt))
    t += dt
    while t < silenceStart + silenceDuration {
        lastResult = predictor.update(subBassOnset: false, beatMid: 0, beatComposite: 0,
                                      time: Float(t), deltaTime: Float(dt))
        t += dt
    }

    // After 3.5× period of silence the phase should reset to 0 (tempo lost).
    #expect(lastResult.beatPhase01 == 0,
            "phase should reset to 0 after 3× period silence, got \(lastResult.beatPhase01)")
    #expect(lastResult.beatsUntilNext == 1,
            "beatsUntilNext should be 1 when tempo is lost, got \(lastResult.beatsUntilNext)")
}

@Test
func beatPredictor_bootstrap_enablesValidPhaseFromFirstOnset() {
    let predictor = BeatPredictor()
    predictor.setBootstrapBPM(120)   // 0.5s period

    let dt: Float = 1.0 / 60.0  // 60 fps

    // Advance a quarter period without any onset pulse.
    // Expected phase after 0.125s with 0.5s period: ~0.25.
    var t: Float = 0.05   // start slightly after 0 to avoid trigger edge
    var result = predictor.update(subBassOnset: false, beatMid: 0, beatComposite: 0,
                                  time: t, deltaTime: dt)
    t += dt
    while t < 0.25 {
        result = predictor.update(subBassOnset: false, beatMid: 0, beatComposite: 0,
                                  time: t, deltaTime: dt)
        t += dt
    }

    // Before any onset, phase is 0 — bootstrap seeds the period but not lastBeatTime.
    // After the first onset, the seeded period lets the predictor track phase immediately.

    // Fire first real beat and check phase resets to near 0.
    let beatResult = predictor.update(subBassOnset: true, beatMid: 0, beatComposite: 0,
                                      time: t, deltaTime: dt)
    t += dt

    // After the onset, phase should restart near 0.
    let postBeatResult = predictor.update(subBassOnset: false, beatMid: 0, beatComposite: 0,
                                          time: t, deltaTime: dt)
    _ = beatResult   // onset frame may have non-zero phase from previous lastBeatTime

    #expect(postBeatResult.beatPhase01 < 0.1,
            "phase should be near 0 immediately after first onset, got \(postBeatResult.beatPhase01)")

    // Advance half a bootstrapped period (0.25s) frame-by-frame.
    // Time is tracked via deltaTime accumulation inside BeatPredictor — a single
    // call with t+=0.25 would only advance by one dt, not 0.25s.
    var midResult = postBeatResult
    let halfPeriodEnd = t + 0.25
    while t < halfPeriodEnd {
        midResult = predictor.update(subBassOnset: false, beatMid: 0, beatComposite: 0,
                                     time: t, deltaTime: dt)
        t += dt
    }
    #expect(midResult.beatPhase01 > 0.3 && midResult.beatPhase01 < 0.7,
            "phase at half-period should be ~0.5, got \(midResult.beatPhase01)")
}
