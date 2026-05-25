// MIRPipelineDriftIntegrationTests — BSAudit.3.impl.2 integration tests for
// the MIRPipeline → LiveBeatDriftTracker / BeatPredictor / BroadbandPeakDetector
// path. Replaces the DSP.2 S7 cached-grid integration tests now that the
// runtime architecture consumes broadband peaks + a BPM prior instead of
// cached beat positions + sub-bass onset matching.
//
// Three contracts:
//   1. With a BPM prior installed, MIRPipeline drives the drift tracker via
//      its own BroadbandPeakDetector — phase emerges after enough peaks.
//   2. Without a prior (reactive mode), beatPhase01 falls back to
//      BeatPredictor.
//   3. installBPMPrior mid-stream re-configures both the tracker and the
//      broadband peak detector.

import Foundation
import Testing
@testable import DSP
import Shared

// MARK: - Helpers

/// Magnitude buffer that produces no onsets / flux (silence) — 512 zeros.
private let silenceMagnitudes = [Float](repeating: 0, count: 512)

/// Magnitude buffer with strong broadband energy used to coax both the
/// `BeatDetector` and `SpectralAnalyzer.flux` paths into firing.
private let broadbandImpulseMagnitudes: [Float] = {
    var m = [Float](repeating: 0, count: 512)
    // Spread energy across the spectrum so SpectralAnalyzer.flux climbs and
    // BeatDetector band 0 (sub-bass) also fires.
    for i in 0..<4 { m[i] = 5.0 }     // sub-bass
    for i in 4..<16 { m[i] = 3.0 }    // low-bass + low-mid
    for i in 16..<64 { m[i] = 2.0 }   // mid
    for i in 64..<256 { m[i] = 0.5 }  // high
    return m
}()

@Suite("MIRPipeline → drift tracker integration (BSAudit.3)")
struct MIRPipelineDriftIntegrationTests {

    // MARK: 1. With BPM prior: drift tracker drives phase after peaks

    @Test("withPrior_driftTrackerAcquiresPhaseFromBroadbandPeaks")
    func test_withPrior_acquiresPhase() {
        let mir = MIRPipeline()
        mir.installBPMPrior(bpm: 120, character: nil, beatsPerBar: 4)

        // Drive frames at 100 fps, firing impulses at 120 BPM (every 0.5 s
        // → every 50 frames). The pipeline's BroadbandPeakDetector emits
        // peaks that anchor + advance the tracker.
        let dt: Float = 0.01
        let beatPeriod: Float = 0.5
        var t: Float = 0
        for _ in 0..<400 {  // 4 seconds
            let frameMod = t.truncatingRemainder(dividingBy: beatPeriod)
            let mags = (frameMod < dt) ? broadbandImpulseMagnitudes : silenceMagnitudes
            _ = mir.process(magnitudes: mags, fps: 100, time: 0, deltaTime: dt)
            t += dt
        }
        // After 4 seconds with peaks at every 0.5 s, the tracker should be
        // locked (it needs ~5 confirmations to clear lockThreshold=0.80).
        #expect(mir.liveDriftTracker.currentLockState == .locked)
        #expect(mir.liveDriftTracker.currentAccentConfidence > 0.5)
    }

    // MARK: 2. Without prior: BeatPredictor fallback

    @Test("withoutPrior_fallsBackToBeatPredictor")
    func test_withoutPrior_fallsBackToBeatPredictor() {
        let mir = MIRPipeline()
        // No installBPMPrior call → tracker has no prior → BeatPredictor owns phase.

        // Drive 2 s with broadband impulses at 120 BPM.
        let dt: Float = 0.01
        let beatPeriod: Float = 0.5
        var t: Float = 0
        var lastPhase: Float = 0
        for _ in 0..<200 {
            let frameMod = t.truncatingRemainder(dividingBy: beatPeriod)
            let mags = (frameMod < dt) ? broadbandImpulseMagnitudes : silenceMagnitudes
            let fv = mir.process(magnitudes: mags, fps: 100, time: 0, deltaTime: dt)
            lastPhase = fv.beatPhase01
            t += dt
        }
        // BeatPredictor needs ≥ 2 onsets to lock; after several beats it
        // should produce a non-zero phase between beats.
        let probe = mir.process(
            magnitudes: silenceMagnitudes, fps: 100, time: 0, deltaTime: 0.05
        )
        #expect(probe.beatPhase01 > 0,
                "BeatPredictor fallback should produce non-zero phase after onsets, got \(probe.beatPhase01) (last=\(lastPhase))")
    }

    // MARK: 3. Mid-stream prior switch re-configures the pipeline

    @Test("installBPMPriorMidStream_takesEffectImmediately")
    func test_installBPMPriorMidStream() {
        let mir = MIRPipeline()

        // Phase A: reactive mode (no prior) → silence → phase 0 (BeatPredictor).
        let dt: Float = 0.01
        for _ in 0..<10 {
            _ = mir.process(magnitudes: silenceMagnitudes, fps: 100, time: 0, deltaTime: dt)
        }
        let beforeSwitch = mir.process(
            magnitudes: silenceMagnitudes, fps: 100, time: 0, deltaTime: dt
        )
        #expect(beforeSwitch.beatPhase01 == 0,
                "reactive mode with silence → phase 0; got \(beforeSwitch.beatPhase01)")

        // Install a BPM prior mid-stream — both tracker and broadband
        // peak detector reset.
        mir.installBPMPrior(bpm: 120, character: nil, beatsPerBar: 4)
        #expect(mir.liveDriftTracker.currentBPM == 120)
        #expect(mir.liveDriftTracker.currentLockState == .unlocked)

        // Drive peaks — phase emerges.
        let beatPeriod: Float = 0.5
        var t: Float = 0
        for _ in 0..<200 {  // 2 seconds, 4 beats
            let frameMod = t.truncatingRemainder(dividingBy: beatPeriod)
            let mags = (frameMod < dt) ? broadbandImpulseMagnitudes : silenceMagnitudes
            _ = mir.process(magnitudes: mags, fps: 100, time: 0, deltaTime: dt)
            t += dt
        }
        // Even without reaching `.locked`, accent confidence should have
        // climbed and beatPhase01 should have updated.
        #expect(mir.liveDriftTracker.currentAccentConfidence > 0)
    }
}
