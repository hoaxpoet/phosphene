// BeatGridUnitTests — DSP.2 S7 unit tests for the BeatGrid lookup helpers
// added alongside LiveBeatDriftTracker.
//
// Four contracts:
//   1. beatIndex(at:) — boundary sentinels (before first / on a beat / past last).
//   2. localTiming(at:) — beats-since-downbeat correct on an irregular grid.
//   3. medianBeatPeriod — within 1 ms of `60/bpm` on a uniform grid.
//   4. beatIndex(at:) is bisect (large-grid sanity test).

import Foundation
import Testing
@testable import DSP

@Suite("BeatGrid — Lookup helpers")
struct BeatGridUnitTests {

    // MARK: 1. beatIndex(at:) sentinels

    @Test("beatIndex_atTime_sentinels")
    func test_beatIndex_atTime_sentinels() {
        let beats = [0.5, 1.0, 1.5, 2.0]
        let grid = BeatGrid(
            beats: beats, downbeats: [0.5, 2.0], bpm: 120, beatsPerBar: 4,
            barConfidence: 1.0, frameRate: 50, frameCount: 100
        )
        #expect(grid.beatIndex(at: 0.0) == nil, "before first beat → nil")
        #expect(grid.beatIndex(at: 0.5) == 0)
        #expect(grid.beatIndex(at: 0.7) == 0)
        #expect(grid.beatIndex(at: 1.0) == 1)
        #expect(grid.beatIndex(at: 5.0) == 3, "past last beat → last index")

        let empty = BeatGrid.empty
        #expect(empty.beatIndex(at: 1.0) == nil, "empty grid → nil")
    }

    // MARK: 2. localTiming on irregular grid

    @Test("localTiming_irregularGrid")
    func test_localTiming_irregularGrid() {
        // Hand-built 7/4 grid: downbeats at 0 and 7 beats later (period 0.5 s).
        // Beat positions: 0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0
        let beats = stride(from: 0.0, through: 6.0, by: 0.5).map { $0 }
        let downbeats = [0.0, 3.5]  // bar 1 = beats 0–6, bar 2 = beats 7–13
        let grid = BeatGrid(
            beats: beats, downbeats: downbeats, bpm: 120, beatsPerBar: 7,
            barConfidence: 1.0, frameRate: 50, frameCount: 600
        )

        // At t=0 → index 0, beats since downbeat = 0.
        guard let t0 = grid.localTiming(at: 0.0) else {
            #expect(Bool(false), "expected non-nil")
            return
        }
        #expect(t0.beatsSinceDownbeat == 0)

        // At t=2.0 → index 4 (beat at 2.0), 4 beats after downbeat at 0.
        guard let t2 = grid.localTiming(at: 2.0) else {
            #expect(Bool(false), "expected non-nil")
            return
        }
        #expect(t2.beatsSinceDownbeat == 4)

        // At t=4.0 → index 8 (beat at 4.0), downbeat at 3.5 (idx 7) → 1 beat past.
        guard let t4 = grid.localTiming(at: 4.0) else {
            #expect(Bool(false), "expected non-nil")
            return
        }
        #expect(t4.beatsSinceDownbeat == 1)

        // Period: uniform 0.5 s between consecutive beats.
        #expect(abs(t4.period - 0.5) < 1e-6)
    }

    // MARK: 3. medianBeatPeriod matches 60/bpm

    @Test("medianBeatPeriod_matches60OverBPM")
    func test_medianBeatPeriod_matches60OverBPM() {
        let bpm = 137.0
        let period = 60.0 / bpm
        let beats = (0..<32).map { Double($0) * period }
        let grid = BeatGrid(
            beats: beats, downbeats: [], bpm: bpm, beatsPerBar: 4,
            barConfidence: 0, frameRate: 50, frameCount: 1000
        )
        #expect(abs(grid.medianBeatPeriod - period) < 1e-3)

        // Empty grid with bpm=0 → 0.
        let empty = BeatGrid.empty
        #expect(empty.medianBeatPeriod == 0)
    }

    // MARK: 4. Bisect search on a long grid

    @Test("beatIndex_isBisectNotLinear")
    func test_beatIndex_isBisectNotLinear() {
        // 10,000-beat synthetic grid.
        let n = 10_000
        let beats = (0..<n).map { Double($0) * 0.5 }
        let grid = BeatGrid(
            beats: beats, downbeats: [0.0], bpm: 120, beatsPerBar: 4,
            barConfidence: 1.0, frameRate: 50, frameCount: 500_000
        )

        // Spot-check a few queries and ensure correctness.
        #expect(grid.beatIndex(at: 0.0) == 0)
        #expect(grid.beatIndex(at: 1234.5) == 2469)
        #expect(grid.beatIndex(at: Double(n) * 0.5) == n - 1)

        // Sanity: 10 lookups in well under 100 ms (bisect is microseconds).
        let start = Date()
        for i in 0..<10 {
            _ = grid.beatIndex(at: Double(i) * 500.0)
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.1, "bisect should be fast, took \(elapsed)s")
    }
}
