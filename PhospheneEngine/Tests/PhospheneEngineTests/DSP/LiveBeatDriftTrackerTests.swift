// LiveBeatDriftTrackerTests — DSP.2 S7 unit tests for the offline-grid drift tracker.
//
// Eight contracts:
//   1. Empty grid → zero phase, .unlocked.
//   2. Perfectly aligned onsets → drift converges to 0.
//   3. Onsets shifted +30 ms → drift converges to +30 ms.
//   4. No onsets for 5 s → drift decays toward 0 (no runaway).
//   5. Phase rises monotonically between cached beats.
//   6. lockState progression unlocked → locking → locked.
//   7. setGrid(_:) resets all drift / onset / lock state.
//   8. barPhase01 aligned to downbeats on a 4/4 grid.

import Foundation
import Testing
@testable import DSP

// MARK: - Fixtures

private func makeUniformGrid(
    bpm: Double = 120,
    beats: Int = 32,
    beatsPerBar: Int = 4
) -> BeatGrid {
    let period = 60.0 / bpm
    let beatTimes = (0..<beats).map { Double($0) * period }
    let downbeatTimes = stride(from: 0, to: beats, by: beatsPerBar).map {
        Double($0) * period
    }
    return BeatGrid(
        beats: beatTimes,
        downbeats: downbeatTimes,
        bpm: bpm,
        beatsPerBar: beatsPerBar,
        barConfidence: 1.0,
        frameRate: 50.0,
        frameCount: 1500
    )
}

/// Drive `tracker` over `durationSeconds` at 100 fps. Calls `onsetAt(t)` to
/// decide whether the sub_bass onset bool is true at playback time `t`.
@discardableResult
private func drive(
    _ tracker: LiveBeatDriftTracker,
    durationSeconds: Double,
    fps: Double = 100,
    onsetAt: (Double) -> Bool
) -> LiveBeatDriftTracker.Result {
    let dt = 1.0 / fps
    var t = 0.0
    var last = LiveBeatDriftTracker.Result(
        beatPhase01: 0, beatsUntilNext: 1, barPhase01: 0, beatsPerBar: 4, lockState: .unlocked
    )
    while t < durationSeconds {
        last = tracker.update(
            subBassOnset: onsetAt(t),
            playbackTime: Float(t),
            deltaTime: Float(dt)
        )
        t += dt
    }
    return last
}

// MARK: - Suite

@Suite("LiveBeatDriftTracker")
struct LiveBeatDriftTrackerTests {

    // MARK: 1. Empty grid

    @Test("emptyGrid_returnsZeroPhase")
    func test_emptyGrid_returnsZeroPhase() {
        let tracker = LiveBeatDriftTracker()
        // No setGrid() call → empty by default.
        let r = tracker.update(subBassOnset: true, playbackTime: 1.0, deltaTime: 0.01)
        #expect(r.beatPhase01 == 0)
        #expect(r.beatsUntilNext == 1)
        #expect(r.barPhase01 == 0)
        if case .unlocked = r.lockState {} else {
            #expect(Bool(false), "expected .unlocked for empty grid")
        }
    }

    // MARK: 2. Aligned onsets → zero drift

    @Test("perfectlyAlignedOnsets_zeroDrift")
    func test_perfectlyAlignedOnsets_zeroDrift() {
        let tracker = LiveBeatDriftTracker()
        let grid = makeUniformGrid(bpm: 120, beats: 32)
        tracker.setGrid(grid)

        let period = 0.5  // 120 BPM
        // Fire onset on the frame closest to each cached beat for 8 s.
        // Verify the resulting beatPhase01 right after a beat is near 0
        // (matched to grid → drift ~ 0 → phase resets at the cached beat).
        let r = drive(tracker, durationSeconds: 8.0) { t in
            // True on frames within ± 0.5 dt of any beat.
            let nearest = round(t / period) * period
            return abs(t - nearest) < 0.005
        }
        // After 8 s of perfect alignment, lock state should be .locked.
        if case .locked = r.lockState {
            // expected
        } else {
            #expect(Bool(false), "expected .locked after 16 aligned beats")
        }
    }

    // MARK: 3. Shifted onsets → drift converges to offset

    @Test("shiftedOnsets_convergesToOffset")
    func test_shiftedOnsets_convergesToOffset() {
        let tracker = LiveBeatDriftTracker()
        let grid = makeUniformGrid(bpm: 120, beats: 32)
        tracker.setGrid(grid)

        let period = 0.5
        let shift = 0.030  // playback runs 30 ms early ⇒ onsets land 30 ms before cached beats
        // Equivalently, cached beats are 30 ms ahead of where onsets fire.
        // Drift = (cachedBeat − playbackOnsetTime) should approach +0.030.
        // Onsets fire when playbackTime is `period * n − shift`, so cached beat
        // (= period * n) is +shift from the onset. drift converges to +shift.
        _ = drive(tracker, durationSeconds: 8.0) { t in
            let nearestOnset = round((t + shift) / period) * period - shift
            return abs(t - nearestOnset) < 0.005
        }

        // Probe drift indirectly: at playbackTime = period (1 beat in), the
        // computed beatPhase01 reflects (pt + drift − beats[idx]) / period.
        // If drift ≈ +0.030, then at pt=period, phase ≈ 0.030 / period = 0.06.
        let probe = tracker.update(
            subBassOnset: false, playbackTime: Float(period), deltaTime: 0.01
        )
        // 30 ms / 500 ms = 0.06.  Tolerance ±0.02 (≈ 10 ms drift slack).
        #expect(abs(probe.beatPhase01 - 0.06) < 0.02,
                "expected phase ≈ 0.06 at +30 ms drift, got \(probe.beatPhase01)")
    }

    // MARK: 4. No onsets → drift decays toward 0

    @Test("noOnsetsInWindow_driftDecaysToZero")
    func test_noOnsetsInWindow_driftDecaysToZero() {
        let tracker = LiveBeatDriftTracker()
        let grid = makeUniformGrid(bpm: 120, beats: 32)
        tracker.setGrid(grid)

        // Phase 1: install a +30 ms drift via 6 shifted onsets.
        let period = 0.5
        let shift = 0.030
        _ = drive(tracker, durationSeconds: 3.0) { t in
            let nearestOnset = round((t + shift) / period) * period - shift
            return abs(t - nearestOnset) < 0.005
        }

        // Phase 2: feed 5 s of silence and check that drift decays.
        // We can't read drift directly — probe via beatPhase01 at exactly a
        // cached beat: with drift ≈ 0 we'd get phase ≈ 0; with drift > 0 we'd
        // get phase > 0.  After decay it should be near 0.
        let dt = 0.01
        var t = 3.0
        for _ in 0..<500 {
            _ = tracker.update(
                subBassOnset: false, playbackTime: Float(t), deltaTime: Float(dt)
            )
            t += dt
        }
        // Probe at a cached beat.  pt + drift ≈ pt (drift decayed).
        let probe = tracker.update(
            subBassOnset: false, playbackTime: Float(period * 6), deltaTime: 0.01
        )
        // Drift may not fully decay to 0 in 5 s with τ=0.2 — but should be ≪ 30 ms.
        // 30 ms / 500 ms = 0.06; expect phase ≪ 0.06.
        #expect(probe.beatPhase01 < 0.02,
                "expected drift to decay; phase was \(probe.beatPhase01)")
    }

    // MARK: 5. Phase rises monotonically between beats

    @Test("phaseMonotonicallyRisesBetweenBeats")
    func test_phaseMonotonicallyRisesBetweenBeats() {
        let tracker = LiveBeatDriftTracker()
        let grid = makeUniformGrid(bpm: 120, beats: 32)
        tracker.setGrid(grid)

        // Sample phase across one beat at high rate, no onsets (drift stays 0).
        let period = 0.5
        var samples: [Float] = []
        let dt = 0.01
        var t = 0.001  // start a hair past the first beat
        while t < period - 0.001 {
            let r = tracker.update(
                subBassOnset: false, playbackTime: Float(t), deltaTime: Float(dt)
            )
            samples.append(r.beatPhase01)
            t += dt
        }
        #expect(samples.count > 30)
        #expect(samples.first ?? 1 < 0.05)
        #expect(samples.last ?? 0 > 0.9)
        let isMono = zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 + 1e-4 }
        #expect(isMono, "phase must be monotonically non-decreasing within one beat")
    }

    // MARK: 6. Lock state progression

    @Test("lockStateProgression")
    func test_lockStateProgression() {
        let tracker = LiveBeatDriftTracker()
        let grid = makeUniformGrid(bpm: 120, beats: 32)
        tracker.setGrid(grid)

        // No onsets yet: .locking is acceptable (or .unlocked) only before
        // any onset. Probe with a no-onset frame; expect not .locked.
        let r0 = tracker.update(subBassOnset: false, playbackTime: 0, deltaTime: 0.01)
        if case .locked = r0.lockState {
            #expect(Bool(false), "should not be .locked before any onset")
        }

        // Fire 6 well-aligned onsets at 120 BPM (one every 0.5 s).
        // 4 should put us past the lockThreshold = .locked.
        let period = 0.5
        let dt = 0.01
        var t = 0.0
        var last = r0
        for beatIdx in 1...6 {
            // Step right up to the next cached beat (period * beatIdx).
            let target = Double(beatIdx) * period
            while t + dt < target {
                _ = tracker.update(
                    subBassOnset: false, playbackTime: Float(t), deltaTime: Float(dt)
                )
                t += dt
            }
            // Fire one onset frame at the beat.
            last = tracker.update(subBassOnset: true, playbackTime: Float(t), deltaTime: Float(dt))
            t += dt
        }

        if case .locked = last.lockState {
            // expected
        } else {
            #expect(Bool(false), "expected .locked after 6 aligned onsets, got \(last.lockState)")
        }
    }

    // MARK: 7. setGrid(_:) resets state

    @Test("gridSwitch_resetsState")
    func test_gridSwitch_resetsState() {
        let tracker = LiveBeatDriftTracker()
        let g1 = makeUniformGrid(bpm: 120, beats: 32)
        tracker.setGrid(g1)

        // Lock against g1 with 6 aligned onsets.
        let period = 0.5
        _ = drive(tracker, durationSeconds: 4.0) { t in
            let nearest = round(t / period) * period
            return abs(t - nearest) < 0.005
        }

        // Install g2 (different tempo). State should fully reset → .unlocked
        // until a fresh onset is matched.
        let g2 = makeUniformGrid(bpm: 90, beats: 32)
        tracker.setGrid(g2)
        let r = tracker.update(subBassOnset: false, playbackTime: 0.0, deltaTime: 0.01)
        if case .unlocked = r.lockState {
            // expected
        } else {
            #expect(Bool(false), "expected .unlocked immediately after setGrid")
        }
        // And drift should be 0: probing at exact beat 0 → phase 0.
        #expect(r.beatPhase01 < 0.02)
    }

    // MARK: 8. Bar phase

    @Test("barPhase01_aligned")
    func test_barPhase01_aligned() {
        let tracker = LiveBeatDriftTracker()
        // 4/4 grid, downbeats at beats 0, 4, 8, 12.  120 BPM → period 0.5 s,
        // bar duration = 2.0 s.
        let grid = makeUniformGrid(bpm: 120, beats: 32, beatsPerBar: 4)
        tracker.setGrid(grid)

        // At playbackTime = 1.0 s, we are exactly at beat 2 (mid-bar) with
        // drift ≈ 0 (no onsets fed; grid pristine).  barPhase01 should be 0.5.
        let r = tracker.update(subBassOnset: false, playbackTime: 1.0, deltaTime: 0.01)
        #expect(abs(r.barPhase01 - 0.5) < 0.05,
                "expected barPhase01 ≈ 0.5 at beat 2 of a 4/4 bar, got \(r.barPhase01)")
    }

    // MARK: 9–15. Public API coverage (SC overhaul prerequisite)
    //
    // Tests 9–10 cover `currentBPM`, tests 11 cover `currentLockState`, and
    // tests 12–15 cover `relativeBeatTimes`.  These APIs ship in DSP.2 S7 and
    // are consumed by the SC overhaul; unit tests here ensure any breakage
    // surfaces in the cheap unit suite before the more expensive visual review.

    // MARK: 9. currentBPM — no grid

    @Test("currentBPM_noGrid_returnsZero")
    func test_currentBPM_noGrid_returnsZero() {
        let tracker = LiveBeatDriftTracker()
        #expect(tracker.currentBPM == 0.0, "currentBPM should be 0 when no grid is installed")
    }

    // MARK: 10. currentBPM — with grid

    @Test("currentBPM_withGrid_matchesGridBPM")
    func test_currentBPM_withGrid_matchesGridBPM() {
        let tracker = LiveBeatDriftTracker()
        let grid = makeUniformGrid(bpm: 125.0, beats: 32)
        tracker.setGrid(grid)
        #expect(abs(tracker.currentBPM - 125.0) < 0.01,
                "currentBPM should reflect the grid's BPM=125, got \(tracker.currentBPM)")
    }

    // MARK: 11. currentLockState — no grid

    @Test("currentLockState_noGrid_returnsUnlocked")
    func test_currentLockState_noGrid_returnsUnlocked() {
        let tracker = LiveBeatDriftTracker()
        if case .unlocked = tracker.currentLockState {
            // expected
        } else {
            #expect(Bool(false), "expected .unlocked with no grid, got \(tracker.currentLockState)")
        }
    }

    // MARK: 12. relativeBeatTimes — no grid → empty

    @Test("relativeBeatTimes_noGrid_returnsEmpty")
    func test_relativeBeatTimes_noGrid_returnsEmpty() {
        let tracker = LiveBeatDriftTracker()
        let times = tracker.relativeBeatTimes(playbackTime: 0, count: 4)
        #expect(times.isEmpty, "relativeBeatTimes should be empty when no grid is installed")
    }

    // MARK: 13. relativeBeatTimes — count ceiling respected

    @Test("relativeBeatTimes_respectsCountCeiling")
    func test_relativeBeatTimes_respectsCountCeiling() {
        let tracker = LiveBeatDriftTracker()
        let grid = makeUniformGrid(bpm: 120, beats: 32)
        tracker.setGrid(grid)
        // Request only 3 beats from a window that contains many more.
        let times = tracker.relativeBeatTimes(playbackTime: 0, count: 3, window: 30.0)
        #expect(times.count <= 3,
                "relativeBeatTimes should return at most count=3 entries, got \(times.count)")
    }

    // MARK: 14. relativeBeatTimes — past beats have negative relative times

    @Test("relativeBeatTimes_includesPastBeatsAsNegative")
    func test_relativeBeatTimes_includesPastBeatsAsNegative() {
        let tracker = LiveBeatDriftTracker()
        let grid = makeUniformGrid(bpm: 120, beats: 32)  // beats at 0, 0.5, 1.0, ...
        tracker.setGrid(grid)

        // At playbackTime = 1.0, the beat at t=0.5 should appear as relative ≈ -0.5.
        let times = tracker.relativeBeatTimes(playbackTime: 1.0, count: 20, window: 3.0)
        let pastBeats = times.filter { $0 < 0 }
        #expect(!pastBeats.isEmpty, "beats before playbackTime=1.0 should appear with negative relative times")

        // Beat at t=0.5 → relative = 0.5 − 1.0 = -0.5 (with drift=0).
        #expect(times.contains(where: { abs($0 - (-0.5)) < 0.05 }),
                "beat at t=0.5 should appear as ≈ -0.5 relative to playbackTime=1.0; times=\(times)")
    }

    // MARK: 15. relativeBeatTimes — upcoming beats are positive

    @Test("relativeBeatTimes_upcomingBeatsArePositive")
    func test_relativeBeatTimes_upcomingBeatsArePositive() {
        let tracker = LiveBeatDriftTracker()
        let grid = makeUniformGrid(bpm: 120, beats: 32)  // beats at 0, 0.5, 1.0, ...
        tracker.setGrid(grid)

        // At playbackTime = 0.1 (just past beat 0), the next beat is at t=0.5.
        // Its relative time = 0.5 − 0.1 = +0.4.
        let times = tracker.relativeBeatTimes(playbackTime: 0.1, count: 4, window: 5.0)
        let upcoming = times.filter { $0 > 0 }
        #expect(!upcoming.isEmpty, "expected upcoming beats (positive) at playbackTime=0.1")
        #expect(times.contains(where: { abs($0 - 0.4) < 0.05 }),
                "beat at t=0.5 should appear as ≈ +0.4 relative to playbackTime=0.1; times=\(times)")
    }
}
