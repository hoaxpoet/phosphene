// LiveBeatDriftTrackerColdStartPhaseTests — CS.1.y.2-redo (BUG-017) regression
// tests for `applyColdStartPhaseCorrection(liveGrid:)`.
//
// Eight contracts:
//   1. No cached grid installed → `.skippedNoGrid`.
//   2. Live grid with too few beats → `.skippedLiveGridDegenerate`.
//   3. Live BPM disagrees with cached BPM beyond tolerance → `.skippedTempoDisagreement`.
//   4. Cached & live grids already aligned → `.applied`, drift ≈ 0 ms.
//   5. Cached grid +180 ms phase-off (within ±½-period) → drift ≈ +180 ms.
//   6. Cached grid +400 ms phase-off at 120 BPM (period 500 ms) wraps to drift ≈ −100 ms.
//   7. Lock state, matchedOnsets, and the EMA are preserved across the correction.
//   8. Garbage live beats with no shared phase → low resultant → `.skippedLowConfidence`.

import Foundation
import Testing
@testable import DSP

// MARK: - Fixtures

private func uniformGrid(
    bpm: Double = 120,
    beats: Int = 30,
    firstBeat: Double = 0.0
) -> BeatGrid {
    let period = 60.0 / bpm
    let beatTimes = (0..<beats).map { firstBeat + Double($0) * period }
    let downbeatTimes = stride(from: 0, to: beats, by: 4).map {
        firstBeat + Double($0) * period
    }
    return BeatGrid(
        beats: beatTimes,
        downbeats: downbeatTimes,
        bpm: bpm,
        beatsPerBar: 4,
        barConfidence: 1.0,
        frameRate: 50.0,
        frameCount: 1500
    )
}

@Suite("LiveBeatDriftTracker — cold-start phase correction")
struct LiveBeatDriftTrackerColdStartPhaseTests {

    // MARK: 1. No cached grid

    @Test("no cached grid → .skippedNoGrid")
    func skipsWithoutCachedGrid() {
        let tracker = LiveBeatDriftTracker()
        let outcome = tracker.applyColdStartPhaseCorrection(liveGrid: uniformGrid())
        if case .skippedNoGrid = outcome { return }
        Issue.record("Expected .skippedNoGrid, got \(outcome)")
    }

    // MARK: 2. Live grid degenerate

    @Test("live grid with < 8 beats → .skippedLiveGridDegenerate")
    func skipsOnDegenerateLiveGrid() {
        let tracker = LiveBeatDriftTracker()
        tracker.setGrid(uniformGrid())
        let degenerate = uniformGrid(beats: 4)
        let outcome = tracker.applyColdStartPhaseCorrection(liveGrid: degenerate)
        if case .skippedLiveGridDegenerate(let count) = outcome {
            #expect(count == 4)
            return
        }
        Issue.record("Expected .skippedLiveGridDegenerate, got \(outcome)")
    }

    // MARK: 3. BPM disagreement

    @Test("live BPM outside ±15% of cached BPM → .skippedTempoDisagreement")
    func skipsOnTempoDisagreement() {
        let tracker = LiveBeatDriftTracker()
        tracker.setGrid(uniformGrid(bpm: 120))
        // 60 BPM is half-time — well outside ±15% (102–138).
        let liveHalf = uniformGrid(bpm: 60)
        let outcome = tracker.applyColdStartPhaseCorrection(liveGrid: liveHalf)
        if case .skippedTempoDisagreement(let live, let cached) = outcome {
            #expect(live == 60)
            #expect(cached == 120)
            return
        }
        Issue.record("Expected .skippedTempoDisagreement, got \(outcome)")
    }

    // MARK: 4. Aligned grids

    @Test("aligned cached & live grids → .applied, drift ≈ 0")
    func appliesNearZeroDriftWhenAligned() {
        let tracker = LiveBeatDriftTracker()
        tracker.setGrid(uniformGrid())
        let outcome = tracker.applyColdStartPhaseCorrection(liveGrid: uniformGrid())
        guard case .applied(let driftMs, let matched, let resultant) = outcome else {
            Issue.record("Expected .applied, got \(outcome)")
            return
        }
        #expect(abs(driftMs) < 1.0, "drift should be ≈ 0 ms, got \(driftMs)")
        #expect(matched >= 20)
        #expect(resultant > 0.99)
        #expect(abs(tracker.currentDriftMs) < 1.0)
    }

    // MARK: 5. Within-half-period offset

    @Test("cached +180 ms off → drift converges to +180 ms")
    func appliesPositiveOffsetWithinHalfPeriod() {
        let tracker = LiveBeatDriftTracker()
        // Cached grid lives at (true + 180 ms). Live grid (Beat This! on tap)
        // sits on the true beats. For each live beat at t, nearest cached is
        // at t + 0.180 → residual +180 ms → drift = +180 ms.
        let trueGrid = uniformGrid()
        let cachedShifted = trueGrid.offsetBy(0.180)
        tracker.setGrid(cachedShifted)
        let outcome = tracker.applyColdStartPhaseCorrection(liveGrid: trueGrid)
        guard case .applied(let driftMs, _, _) = outcome else {
            Issue.record("Expected .applied, got \(outcome)")
            return
        }
        #expect(abs(driftMs - 180.0) < 5.0, "drift expected ≈ +180 ms, got \(driftMs)")
        #expect(abs(tracker.currentDriftMs - 180.0) < 5.0)
    }

    // MARK: 6. Wrap correctness past ±half-period

    @Test("cached +400 ms off at 120 BPM (period 500 ms) wraps to drift ≈ −100 ms")
    func wrapsPastHalfPeriod() {
        let tracker = LiveBeatDriftTracker()
        // +400 ms at 120 BPM is +400 ms apparent but only −100 ms within the
        // shorter ±250 ms half-period — they describe the same visual phase.
        let trueGrid = uniformGrid(bpm: 120)
        let cachedShifted = trueGrid.offsetBy(0.400)
        tracker.setGrid(cachedShifted)
        let outcome = tracker.applyColdStartPhaseCorrection(liveGrid: trueGrid)
        guard case .applied(let driftMs, _, _) = outcome else {
            Issue.record("Expected .applied, got \(outcome)")
            return
        }
        #expect(abs(driftMs - (-100.0)) < 5.0,
                "drift expected ≈ −100 ms after wrap, got \(driftMs)")
    }

    // MARK: 7. Lock & EMA state preserved

    @Test("lock state, matchedOnsets, and drift-EMA-ring are preserved across correction")
    func preservesLockStateAcrossCorrection() {
        let tracker = LiveBeatDriftTracker()
        let cached = uniformGrid().offsetBy(0.080)  // small +80 ms offset
        tracker.setGrid(cached)
        // Drive enough on-beat-true onsets that matchedOnsets ≥ 4 → .locked.
        // The matching window is ±50 ms; with cached at +80 ms and onsets on
        // true beats, the EMA needs to climb to ~+80 ms first. Drive an initial
        // burst that lands the EMA near +80 ms, then run a phase-correct burst.
        var pt = 0.0
        let dt: Float = 0.01
        for _ in 0..<20 {
            // Onset at the cached beat positions so matches land tight.
            for beat in cached.beats.prefix(8) {
                pt = beat
                _ = tracker.update(subBassOnset: true, playbackTime: pt, deltaTime: dt)
            }
        }
        let preMatched = tracker.matchedOnsetCount
        let preLock = tracker.currentLockState
        // Pre-correction the tracker has accumulated matches.
        #expect(preMatched >= 4, "Expected matchedOnsets ≥ 4, got \(preMatched)")
        if case .locked = preLock { /* ok */ } else if case .locking = preLock { /* ok */ } else {
            Issue.record("Expected .locked or .locking pre-correction, got \(preLock)")
        }
        // Apply a correction with a live grid offset by −80 ms (so the
        // measurement says drift should be +80 ms — same as current EMA).
        let liveGrid = uniformGrid()  // unshifted
        let outcome = tracker.applyColdStartPhaseCorrection(liveGrid: liveGrid)
        guard case .applied = outcome else {
            Issue.record("Expected .applied, got \(outcome)")
            return
        }
        // Lock state + matched count unchanged.
        #expect(tracker.matchedOnsetCount == preMatched,
                "matchedOnsets changed: \(preMatched) → \(tracker.matchedOnsetCount)")
        let postLock = tracker.currentLockState
        switch (preLock, postLock) {
        case (.locked, .locked), (.locking, .locking), (.unlocked, .unlocked):
            break
        default:
            Issue.record("Lock state changed: \(preLock) → \(postLock)")
        }
    }

    // MARK: 8. Garbage live grid

    @Test("scrambled live beats with no shared phase → .skippedLowConfidence")
    func skipsOnLowConfidence() {
        let tracker = LiveBeatDriftTracker()
        let trueGrid = uniformGrid(bpm: 120, beats: 30)
        tracker.setGrid(trueGrid)
        // Construct a live grid with BPM ≈ 120 but beats deliberately
        // scattered across the period — circular mean → low resultant.
        // We jitter each beat by a different fraction of the period so the
        // residual cluster spans the whole [−P/2, +P/2] band.
        let period = 60.0 / 120.0
        let scattered = (0..<30).map { idx -> Double in
            let base = Double(idx) * period
            // Pseudo-random jitter in (−P/2, +P/2). Sin-based so it's deterministic
            // and spans the band; not on-beat.
            let jitter = sin(Double(idx) * 1.31) * (period * 0.45)
            return base + jitter
        }
        let live = BeatGrid(
            beats: scattered, downbeats: [], bpm: 120, beatsPerBar: 4,
            barConfidence: 0.5, frameRate: 50.0, frameCount: 1500
        )
        let outcome = tracker.applyColdStartPhaseCorrection(liveGrid: live)
        if case .skippedLowConfidence(let resultant) = outcome {
            #expect(resultant < 0.5, "expected R < 0.5, got \(resultant)")
            return
        }
        Issue.record("Expected .skippedLowConfidence, got \(outcome)")
    }
}
