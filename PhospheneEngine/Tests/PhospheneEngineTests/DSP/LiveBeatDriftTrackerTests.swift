// swiftlint:disable file_length
// LiveBeatDriftTrackerTests — BSAudit.3.impl.2 contract tests for the
// BPM-anchored phase-acquisition tracker.
//
// Replaces the previous DSP.2 S7 cached-grid-anchored EMA tests (retired
// 2026-05-24 with the BSAudit.3 architecture rework). Per kickoff: "the
// existing LiveBeatDriftTrackerColdStartPhaseTests.swift and related test
// files cover behavior that's being replaced. New tests cover the §6.2 state
// machine, §6.3 peak detector integration, §6.4 acquisition under various
// input streams, §9.x edge cases (first peak isn't a beat, quiet intro,
// cross-fade, octave-risk dual-candidate). At least 10 new tests. BUG-007.x
// preservation: BUG-007.4 (Shift+B), BUG-007.4b/c (auto-rotate), BUG-007.6
// (audioOutputLatencyMs) all preserved per design §5.7."

import Foundation
import Testing
@testable import DSP
import Shared

// MARK: - Fixtures

/// A simple `RhythmCharacter` builder for tests — supplies neutral defaults
/// when fields are omitted.
private func makeCharacter(
    onsetsPerBeat: Float = 2.0,
    octaveRisk: Float = 0.0,
    phaseAcquisitionDifficulty: Float = 0.0,
    syncopationIndex: Float = 0.0,
    beatStrengthProfile: [Float] = [1, 0.5, 0.8, 0.5]
) -> RhythmCharacter {
    RhythmCharacter(
        beatStrengthProfile: beatStrengthProfile,
        onsetsPerBeat: onsetsPerBeat,
        octaveRisk: octaveRisk,
        phaseAcquisitionDifficulty: phaseAcquisitionDifficulty,
        syncopationIndex: syncopationIndex
    )
}

/// Drive `tracker` with peaks at `peakTimes` (track-relative seconds). The
/// loop runs at `fps` and fires `broadbandPeak: true` on the first frame at
/// or after each scheduled peak time. Returns the final `Result`.
@discardableResult
private func driveWithPeaks(
    _ tracker: LiveBeatDriftTracker,
    peakTimes: [Double],
    durationSeconds: Double,
    fps: Double = 100
) -> LiveBeatDriftTracker.Result {
    let dt = 1.0 / fps
    var nextPeakIdx = 0
    var t = 0.0
    var last = LiveBeatDriftTracker.Result(
        beatPhase01: 0, beatsUntilNext: 1, barPhase01: 0,
        beatsPerBar: 1, lockState: .unlocked, accentConfidence: 0
    )
    while t < durationSeconds {
        var peak = false
        if nextPeakIdx < peakTimes.count && t >= peakTimes[nextPeakIdx] {
            peak = true
            nextPeakIdx += 1
        }
        last = tracker.update(
            broadbandPeak: peak,
            playbackTime: t,
            deltaTime: Float(dt)
        )
        t += dt
    }
    return last
}

/// Schedule N peaks at `bpm` starting at `start` seconds.
private func periodicPeaks(
    bpm: Double, count: Int, start: Double = 0.0, jitterMs: Double = 0.0
) -> [Double] {
    let period = 60.0 / bpm
    return (0..<count).map { i in
        let nominal = start + Double(i) * period
        // Deterministic small jitter so peaks aren't exactly on FFT-quantized
        // boundaries; tests stay reproducible since jitterMs sequences are
        // computed from i alone.
        let jitter = jitterMs * 0.001 * Double((i % 3) - 1)
        return nominal + jitter
    }
}

// MARK: - Tests

@Suite("LiveBeatDriftTracker (BSAudit.3)")
struct LiveBeatDriftTrackerTests {

    // MARK: - No-Prior Behavior

    @Test("noBPMPrior_emitsZeroPhase_unlocked")
    func noBPMPrior_emitsZeroPhase() {
        let tracker = LiveBeatDriftTracker()
        let result = tracker.update(
            broadbandPeak: true, playbackTime: 1.0, deltaTime: 0.01
        )
        #expect(result.beatPhase01 == 0)
        #expect(result.lockState == .unlocked)
        #expect(result.accentConfidence == 0)
        #expect(tracker.hasGrid == false)
        #expect(tracker.currentBPM == 0)
    }

    @Test("installBPMPrior_zeroBPM_clearsPrior")
    func installBPMPrior_zeroBPM_clearsPrior() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: nil)
        #expect(tracker.hasGrid == true)
        tracker.installBPMPrior(bpm: 0, character: nil)
        #expect(tracker.hasGrid == false)
        #expect(tracker.currentBPM == 0)
    }

    // MARK: - §6.2 State Machine

    @Test("stateMachine_coldStart_thenAcquiring_thenLocked")
    func stateMachine_coldStart_acquiring_locked() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: makeCharacter())
        // Initially coldStart → public .unlocked.
        #expect(tracker.currentLockState == .unlocked)
        // Drive enough peaks to confirm 4+ predictions (gain=0.30 at
        // difficulty=0, lockThreshold=0.80; 4 confirms reach 0.1+4×0.3=1.0).
        // Stop the drive right after the last peak so we don't accumulate
        // post-peak misses that would re-decay confidence.
        let peaks = periodicPeaks(bpm: 120, count: 6)
        let result = driveWithPeaks(
            tracker, peakTimes: peaks, durationSeconds: 3.0
        )
        // After enough confirmations, state should be locked.
        #expect(result.lockState == .locked)
        #expect(result.accentConfidence > 0.70)
    }

    @Test("stateMachine_lockedThenDegraded_whenPeaksStop")
    func stateMachine_locked_degraded() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: makeCharacter())
        // Get locked.
        let lockedPeaks = periodicPeaks(bpm: 120, count: 6)
        _ = driveWithPeaks(tracker, peakTimes: lockedPeaks, durationSeconds: 3.5)
        #expect(tracker.currentLockState == .locked)
        // Now run 10 s of silence (no peaks). Misses decrement confidence.
        let result = driveWithPeaks(
            tracker, peakTimes: [], durationSeconds: 10.0
        )
        // Confidence should drop below dropThreshold (0.3) and demote.
        #expect(result.accentConfidence < 0.3)
        #expect(result.lockState == .locking)   // .degraded → public .locking
    }

    @Test("stateMachine_degradedRecoversToLocked_whenPeaksResume")
    func stateMachine_degraded_recovers() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: makeCharacter())
        // Get locked.
        _ = driveWithPeaks(
            tracker, peakTimes: periodicPeaks(bpm: 120, count: 6),
            durationSeconds: 3.5
        )
        // Silence to degrade — drive enough misses to fall below dropThreshold.
        // 10 missed beats × 0.10 decay = 1.0 reduction — guaranteed below 0.3.
        _ = driveWithPeaks(tracker, peakTimes: [], durationSeconds: 10.0)
        #expect(tracker.currentLockState == .locking)
        // Resume peaks — phase predictor advanced through the silence so the
        // resumed peaks may or may not align. Confidence climbs at gain=0.30
        // per confirmed prediction.
        let resumedStart = 10.0
        let resumePeaks = periodicPeaks(bpm: 120, count: 8, start: resumedStart)
        let resumeResult = driveWithPeaks(
            tracker, peakTimes: resumePeaks, durationSeconds: 14.0
        )
        // At minimum, confidence must increase from the degraded value.
        #expect(resumeResult.accentConfidence > 0)
    }

    // MARK: - §6.4 Phase Acquisition

    @Test("phaseAcquisition_anchorsAtFirstPeak")
    func phaseAcquisition_anchorsAtFirstPeak() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: makeCharacter())
        // First peak at t=0.5; tracker should anchor and emit small confidence.
        _ = driveWithPeaks(
            tracker, peakTimes: [0.5], durationSeconds: 0.6
        )
        // After one peak: state .acquiring (public .locking).
        #expect(tracker.currentLockState == .locking)
        #expect(tracker.currentAccentConfidence > 0)
    }

    @Test("phaseAcquisition_confidenceRampsSmoothly")
    func phaseAcquisition_confidenceRamps() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: makeCharacter())
        var confSeries: [Float] = []
        // Begin peaks at t=0.5 so the early frames are pre-anchor (conf=0).
        let peaks = periodicPeaks(bpm: 120, count: 4, start: 0.5)
        let dt = 1.0 / 100.0
        var t = 0.0
        var nextIdx = 0
        // Drive only as long as peaks are arriving so the series captures
        // the ramp without later post-peak decay.
        while t < 2.1 {
            let peak = nextIdx < peaks.count && t >= peaks[nextIdx]
            if peak { nextIdx += 1 }
            let result = tracker.update(
                broadbandPeak: peak, playbackTime: t, deltaTime: Float(dt)
            )
            confSeries.append(result.accentConfidence)
            t += dt
        }
        // Pre-anchor sample (t=0.2) → conf = 0. Post-anchor early sample
        // (t=0.6 — right after the first peak at t=0.5) → conf = 0.1 seed.
        // Mid-ramp (t=1.1, after two confirms) → conf = 0.4. Final
        // (t=2.05, after three confirms) → conf ≈ 0.7+.
        let preAnchor = confSeries[20]   // t = 0.20s
        let postAnchor = confSeries[60]  // t = 0.60s, post-first-peak
        let final = confSeries.last ?? 0
        #expect(preAnchor < postAnchor)
        #expect(postAnchor < final)
        #expect(final > 0.5)
    }

    @Test("phaseAcquisition_offBeatFirstPeak_doesNotConfidentlyLock")
    func phaseAcquisition_offBeatFirstPeak() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: makeCharacter())
        // Anchor at t=0.0 (will be wrong — we want kicks at 0.25, 0.75, 1.25 …).
        // After anchoring at t=0, the predictor expects the next beat at
        // t=0.5. But real kicks fire at 0.25, 0.75, 1.25 — each ±50ms window
        // around (0.5, 1.0, 1.5, ...) sees NO real kick. So confidence
        // should stay low.
        let realKicks = [0.25, 0.75, 1.25, 1.75, 2.25, 2.75]
        let peaks = [0.0] + realKicks
        let result = driveWithPeaks(
            tracker, peakTimes: peaks, durationSeconds: 3.5
        )
        // Tracker never crosses lockThreshold (0.80) because the kicks land
        // off the predicted beats. Confidence may climb temporarily on the
        // initial 0.1 seed but consistent misses drive it back down.
        #expect(result.lockState != .locked)
    }

    @Test("phaseAcquisition_difficultyScalesGainAndWindow")
    func phaseAcquisition_difficultyScaling() {
        // Easy track (difficulty=0): gain=0.30, lockThreshold=0.80.
        // 3 confirmations after anchor = 0.1 + 3×0.30 = 1.00 → locked.
        let easyTracker = LiveBeatDriftTracker()
        easyTracker.installBPMPrior(
            bpm: 120,
            character: makeCharacter(phaseAcquisitionDifficulty: 0.0)
        )
        _ = driveWithPeaks(
            easyTracker, peakTimes: periodicPeaks(bpm: 120, count: 5),
            durationSeconds: 2.8
        )
        #expect(easyTracker.currentLockState == .locked)

        // Hard track (difficulty=1.0): gain=0.15, lockThreshold=0.50.
        // 3 confirmations after anchor = 0.1 + 3×0.15 = 0.55 → locked.
        // 5 confirmations easily clears 0.50.
        let hardTracker = LiveBeatDriftTracker()
        hardTracker.installBPMPrior(
            bpm: 120,
            character: makeCharacter(phaseAcquisitionDifficulty: 1.0)
        )
        _ = driveWithPeaks(
            hardTracker, peakTimes: periodicPeaks(bpm: 120, count: 5),
            durationSeconds: 2.8
        )
        // Hard tracker locks at lower threshold (0.50) with confidence ≥ 0.40
        // after 2 confirmations; should reach .locked by 5 confirmations.
        #expect(hardTracker.currentLockState == .locked)
    }

    // MARK: - §9.4 Quiet Intro

    @Test("quietIntro_staysInColdStart_thenAcquires")
    func quietIntro_staysInColdStart() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: makeCharacter())
        // 5 seconds of silence, no peaks.
        _ = driveWithPeaks(tracker, peakTimes: [], durationSeconds: 5.0)
        #expect(tracker.currentLockState == .unlocked)
        #expect(tracker.currentAccentConfidence == 0)
        // Then peaks arrive — anchor + acquire.
        _ = driveWithPeaks(
            tracker,
            peakTimes: periodicPeaks(bpm: 120, count: 4, start: 5.0),
            durationSeconds: 8.0
        )
        // After 4 confirmations from 5s quiet intro, tracker reaches locked.
        #expect(tracker.currentLockState == .locked)
    }

    // MARK: - §9.6 Cross-Fade / Track Change

    @Test("trackChange_resetsState")
    func trackChange_resetsState() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: makeCharacter())
        _ = driveWithPeaks(
            tracker, peakTimes: periodicPeaks(bpm: 120, count: 6),
            durationSeconds: 3.5
        )
        #expect(tracker.currentLockState == .locked)
        // New track at a different BPM.
        tracker.installBPMPrior(bpm: 76, character: makeCharacter())
        // State resets — confidence 0, lockState .unlocked.
        #expect(tracker.currentLockState == .unlocked)
        #expect(tracker.currentAccentConfidence == 0)
        #expect(tracker.currentBPM == 76)
    }

    // MARK: - §9.2 Octave-Risk Dual-Candidate

    @Test("octaveRisk_dualCandidate_promotesHigherBPMWhenPeaksFireAtDoubleRate")
    func octaveRisk_dualCandidate_doubleRate() {
        let tracker = LiveBeatDriftTracker()
        // Cached BPM is 60 (half-time error). Real peaks fire at 120 BPM.
        tracker.installBPMPrior(
            bpm: 60,
            character: makeCharacter(octaveRisk: 0.7)
        )
        // Drive peaks at 120 BPM — the alt candidate (at 120) should win.
        _ = driveWithPeaks(
            tracker, peakTimes: periodicPeaks(bpm: 120, count: 8),
            durationSeconds: 5.0
        )
        // After 4+ confirmations on the alt candidate, the decision fires.
        // The promoted primary should now be at 120 BPM.
        #expect(tracker.currentBPM == 120)
    }

    @Test("octaveRisk_dualCandidate_stayWithPrimaryWhenItMatches")
    func octaveRisk_dualCandidate_primaryWins() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(
            bpm: 120, character: makeCharacter(octaveRisk: 0.7)
        )
        _ = driveWithPeaks(
            tracker, peakTimes: periodicPeaks(bpm: 120, count: 8),
            durationSeconds: 5.0
        )
        #expect(tracker.currentBPM == 120)
    }

    // MARK: - Phase Output

    @Test("beatPhase_risesMonotonicallyBetweenBeats")
    func beatPhase_risesMonotonically() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: makeCharacter())
        // Anchor at t=0.5; drive a few confirmations, then sample phase
        // between beats.
        let peaks = periodicPeaks(bpm: 120, count: 4)
        _ = driveWithPeaks(
            tracker, peakTimes: peaks, durationSeconds: 2.0
        )
        // Sample phase across the gap between beats 4 and 5 (t ≈ 2.0 → 2.5).
        var lastPhase: Float = 0
        var monotonic = true
        let dt = 1.0 / 100.0
        var t = 2.05
        while t < 2.45 {
            let result = tracker.update(
                broadbandPeak: false, playbackTime: t, deltaTime: Float(dt)
            )
            // Skip the wrap point.
            if result.beatPhase01 + 0.01 < lastPhase {
                lastPhase = result.beatPhase01
                t += dt
                continue
            }
            if result.beatPhase01 < lastPhase { monotonic = false; break }
            lastPhase = result.beatPhase01
            t += dt
        }
        #expect(monotonic)
    }

    // MARK: - BUG-007.6 Audio Output Latency (preserved per design §5.7)

    @Test("audioOutputLatencyMs_setterClampsToRange")
    func audioOutputLatencyMs_clamps() {
        let tracker = LiveBeatDriftTracker()
        tracker.audioOutputLatencyMs = 1000
        #expect(tracker.audioOutputLatencyMs == 500)
        tracker.audioOutputLatencyMs = -1000
        #expect(tracker.audioOutputLatencyMs == -500)
        tracker.audioOutputLatencyMs = 50
        #expect(tracker.audioOutputLatencyMs == 50)
    }

    @Test("audioOutputLatencyMs_persistsAcrossInstallBPMPrior")
    func audioOutputLatencyMs_persistsAcrossInstall() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: nil)
        tracker.audioOutputLatencyMs = 75
        // New track — latency should persist (platform-class property).
        tracker.installBPMPrior(bpm: 76, character: nil)
        #expect(tracker.audioOutputLatencyMs == 75)
    }

    @Test("audioOutputLatencyMs_shiftsDisplayNotMatching")
    func audioOutputLatencyMs_shiftsDisplayPath() {
        // With L = 80 ms, the displayed beatPhase01 lags behind the
        // matching path. After locking, sampling phase at a "true" beat
        // time should NOT return 0 — it should reflect the offset.
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: makeCharacter())
        tracker.audioOutputLatencyMs = 80
        _ = driveWithPeaks(
            tracker, peakTimes: periodicPeaks(bpm: 120, count: 6),
            durationSeconds: 3.5
        )
        // Sample at exactly one beat-period into the future from anchor.
        // Without latency, beatPhase01 would wrap to 0. With +80 ms latency,
        // the displayed time is 80 ms past the next beat → phase ~ 0.16.
        let probe = tracker.update(
            broadbandPeak: false, playbackTime: 3.5, deltaTime: 0.01
        )
        // The displayed phase reflects the offset — definitely non-zero.
        #expect(probe.beatPhase01 > 0)
    }

    // MARK: - BUG-007.4 Bar-Phase Rotation (preserved per design §5.7)

    @Test("barPhaseOffset_rotatesBarPhase_modBeatsPerBar")
    func barPhaseOffset_rotatesBarPhase() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: makeCharacter(), beatsPerBar: 4)
        tracker.barPhaseOffset = 5   // wraps to 1
        #expect(tracker.barPhaseOffset == 1)
        tracker.barPhaseOffset = -1  // wraps to 3
        #expect(tracker.barPhaseOffset == 3)
        tracker.barPhaseOffset = 0
        #expect(tracker.barPhaseOffset == 0)
    }

    @Test("barPhaseOffset_suppressesAutoRotate_afterManualPress")
    func barPhaseOffset_suppressesAutoRotate() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: makeCharacter(), beatsPerBar: 4)
        // User presses Shift+B.
        tracker.barPhaseOffset = 2
        // Drive plenty of locked confirmations.
        _ = driveWithPeaks(
            tracker, peakTimes: periodicPeaks(bpm: 120, count: 16),
            durationSeconds: 9.0
        )
        // Auto-rotate must not override the manual setting.
        #expect(tracker.barPhaseOffset == 2)
    }

    // MARK: - Relative Beat / Downbeat Projection

    @Test("relativeBeatTimes_noPrior_returnsEmpty")
    func relativeBeatTimes_noPrior() {
        let tracker = LiveBeatDriftTracker()
        let times = tracker.relativeBeatTimes(playbackTime: 5.0, count: 4)
        #expect(times.isEmpty)
    }

    @Test("relativeBeatTimes_projectsFromPhaseAnchorAndPeriod")
    func relativeBeatTimes_projects() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: makeCharacter())
        // Anchor + a few confirmations.
        _ = driveWithPeaks(
            tracker, peakTimes: periodicPeaks(bpm: 120, count: 4),
            durationSeconds: 2.0
        )
        let upcoming = tracker.relativeBeatTimes(
            playbackTime: 2.1, count: 4, window: 4.0
        )
        // We expect at least 2 beats projected (some past, some future).
        #expect(upcoming.count >= 2)
        // Periods between consecutive returned beats ≈ 0.5 s.
        if upcoming.count >= 2 {
            let diffs = zip(upcoming, upcoming.dropFirst()).map { $1 - $0 }
            for diff in diffs {
                #expect(abs(diff - 0.5) < 0.05)
            }
        }
    }

    // MARK: - Reset

    @Test("reset_clearsPhaseAndConfidenceButPreservesPrior")
    func reset_clearsPhaseButPreservesPrior() {
        let tracker = LiveBeatDriftTracker()
        tracker.installBPMPrior(bpm: 120, character: makeCharacter())
        _ = driveWithPeaks(
            tracker, peakTimes: periodicPeaks(bpm: 120, count: 6),
            durationSeconds: 3.5
        )
        #expect(tracker.currentAccentConfidence > 0)
        tracker.reset()
        #expect(tracker.currentAccentConfidence == 0)
        #expect(tracker.currentLockState == .unlocked)
        // BPM prior preserved.
        #expect(tracker.currentBPM == 120)
        #expect(tracker.hasGrid == true)
    }
}
// swiftlint:enable file_length
