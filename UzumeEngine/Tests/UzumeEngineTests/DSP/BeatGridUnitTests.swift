// BeatGridUnitTests — DSP.2 S7 unit tests for the BeatGrid lookup helpers
// added alongside LiveBeatDriftTracker.
//
// Four contracts (DSP.2 S7):
//   1. beatIndex(at:) — boundary sentinels (before first / on a beat / past last).
//   2. localTiming(at:) — beats-since-downbeat correct on an irregular grid.
//   3. medianBeatPeriod — within 1 ms of `60/bpm` on a uniform grid.
//   4. beatIndex(at:) is bisect (large-grid sanity test).
//
// Five contracts (DSP.3.4 — horizon extrapolation):
//   5. offsetBy extrapolates beats to 300-second horizon.
//   6. extrapolated beats preserve correct BPM period.
//   7. extrapolated downbeats are appended and spaced by bar period.
//   8. beatPhase01 stays in [0,1) at t >> lastRecordedBeat (no freeze at 1.0).
//   9. nearestBeat finds a match within ±50 ms well past the original grid end.

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

    // MARK: 5. offsetBy extrapolates to 300-second horizon (DSP.3.4)

    @Test("offsetBy_extrapolatesBeatsToHorizon")
    func test_offsetBy_extrapolatesBeatsToHorizon() {
        // Tiny 10-beat grid at 120 BPM (0.5 s period), covering 0–4.5 s.
        let bpm = 120.0
        let period = 60.0 / bpm
        let beats = (0..<10).map { Double($0) * period }
        let downbeats = [0.0, 2.0]
        let grid = BeatGrid(
            beats: beats, downbeats: downbeats, bpm: bpm, beatsPerBar: 4,
            barConfidence: 1.0, frameRate: 50, frameCount: 500
        )

        // Shift by 5 s (bufferStartTime offset typical in live-trigger path).
        let shifted = grid.offsetBy(5.0)

        // Shifted last recorded beat is at 5 + 4.5 = 9.5 s.
        // Extrapolation extends to 9.5 + 300 = 309.5 s.
        let lastBeat = shifted.beats.last!
        #expect(lastBeat >= 309.0, "last beat should reach ~309 s, got \(lastBeat)")

        // Beat count: 10 original + ⌊300/0.5⌋ = 600 extrapolated = 610 total.
        #expect(shifted.beats.count >= 610)
    }

    // MARK: 6. Extrapolated beats maintain BPM period (DSP.3.4)

    @Test("offsetBy_extrapolatedBeatsPeriod")
    func test_offsetBy_extrapolatedBeatsPeriod() {
        let bpm = 125.0
        let period = 60.0 / bpm
        let beats = (0..<20).map { Double($0) * period }
        let grid = BeatGrid(
            beats: beats, downbeats: [], bpm: bpm, beatsPerBar: 4,
            barConfidence: 1.0, frameRate: 50, frameCount: 1000
        )
        let shifted = grid.offsetBy(0.0)

        // All consecutive IOIs in the extrapolated portion should equal `period`
        // within floating-point rounding (~1 µs).
        let originalCount = beats.count
        guard shifted.beats.count > originalCount + 10 else {
            #expect(Bool(false), "expected extrapolated beats")
            return
        }
        for i in (originalCount)..<min(originalCount + 50, shifted.beats.count - 1) {
            let ioi = shifted.beats[i + 1] - shifted.beats[i]
            #expect(abs(ioi - period) < 1e-6,
                    "IOI at extrapolated index \(i) should be \(period), got \(ioi)")
        }
    }

    // MARK: 7. Extrapolated downbeats are appended at bar period (DSP.3.4)

    @Test("offsetBy_extrapolatesDownbeats")
    func test_offsetBy_extrapolatesDownbeats() {
        let bpm = 120.0
        let period = 60.0 / bpm
        let beats = (0..<8).map { Double($0) * period }
        let downbeats = [0.0, 2.0]  // 4/4 → bar period = 4 × 0.5 = 2.0 s
        let grid = BeatGrid(
            beats: beats, downbeats: downbeats, bpm: bpm, beatsPerBar: 4,
            barConfidence: 1.0, frameRate: 50, frameCount: 400
        )
        let shifted = grid.offsetBy(0.0)

        // Shifted downbeats: at 0, 2, 4, 6, 8 … up to ~302 s.
        // Should have many more than the original 2.
        #expect(shifted.downbeats.count >= 100)

        // Check that extrapolated downbeats are spaced by barPeriod = 2.0 s.
        let dbPeriod = period * 4
        for i in 2..<min(shifted.downbeats.count - 1, 10) {
            let gap = shifted.downbeats[i + 1] - shifted.downbeats[i]
            #expect(abs(gap - dbPeriod) < 1e-6,
                    "downbeat gap at \(i) should be \(dbPeriod), got \(gap)")
        }
    }

    // MARK: 8. beatPhase01 stays valid past original grid end (DSP.3.4)

    @Test("offsetBy_beatPhaseStaysValidPastHorizon")
    func test_offsetBy_beatPhaseStaysValidPastHorizon() {
        // Simulate the live-trigger scenario: 10-beat grid at 125 BPM,
        // shifted by bufferStartTime=0 (simplification). Without extrapolation,
        // any lookup past lastBeat (~4.56 s at 125 BPM) would clamp to 1.0.
        let bpm = 125.0
        let period = 60.0 / bpm
        let beats = (0..<10).map { Double($0) * period }
        let grid = BeatGrid(
            beats: beats, downbeats: [], bpm: bpm, beatsPerBar: 4,
            barConfidence: 1.0, frameRate: 50, frameCount: 500
        )
        let extended = grid.offsetBy(0.0)

        // Query at t = 60 s (well past the 10-beat window).
        let t = 60.0
        guard let idx = extended.beatIndex(at: t) else {
            #expect(Bool(false), "beatIndex at \(t) should not be nil after extrapolation")
            return
        }
        let beatTime = extended.beats[idx]
        let rawPhase = (t - beatTime) / period
        // rawPhase should be in [0, 1) — not clamped to 1.0.
        #expect(rawPhase >= 0 && rawPhase < 1.0,
                "rawPhase at t=\(t) should be in [0,1), got \(rawPhase)")
    }

    // MARK: 9. nearestBeat finds a match within ±50 ms past original end (DSP.3.4)

    @Test("offsetBy_nearestBeatFindsMatchPastOriginalEnd")
    func test_offsetBy_nearestBeatFindsMatchPastOriginalEnd() {
        let bpm = 120.0
        let period = 60.0 / bpm  // 0.5 s
        let beats = (0..<12).map { Double($0) * period }  // covers 0–5.5 s
        let grid = BeatGrid(
            beats: beats, downbeats: [], bpm: bpm, beatsPerBar: 4,
            barConfidence: 1.0, frameRate: 50, frameCount: 600
        )
        let extended = grid.offsetBy(0.0)

        // At t = 30 s the nearest extrapolated beat should be within 0 + ε.
        // 30 s / 0.5 s = 60 beats exactly.
        let t = 30.0
        let nearest = extended.nearestBeat(to: t, within: 0.05)  // ±50 ms window
        #expect(nearest != nil, "nearestBeat at t=\(t) should find an extrapolated beat")
        if let n = nearest {
            #expect(abs(n - t) < 0.05,
                    "nearest beat at \(n) should be within 50 ms of \(t)")
        }
    }

    // MARK: 10. halvingOctaveCorrected — double-time (BPM > 175)

    @Test("halvingOctaveCorrected_doubletimeBPM_halvesBeatsAndBPM")
    func test_halvingOctaveCorrected_doubletimeBPM() {
        // Simulate Love Rehab live-trigger artefact: 245 BPM detected (true 125 BPM).
        let rawBPM = 244.770
        let period = 60.0 / rawBPM   // ~0.245 s
        // 41 beats covering ~10 s at 245 BPM.
        let beats = (0..<41).map { Double($0) * period }
        // Downbeats every 4 beats (4/4 at double-time).
        let downbeats = stride(from: 0, to: 41, by: 4).map { Double($0) * period }
        let grid = BeatGrid(
            beats: beats, downbeats: downbeats, bpm: rawBPM, beatsPerBar: 4,
            barConfidence: 1.0, frameRate: 50, frameCount: 500
        )
        let corrected = grid.halvingOctaveCorrected()

        // BPM must be halved into [80, 175] (BUG-009, threshold raised from 160).
        #expect(corrected.bpm > 80 && corrected.bpm <= 175,
                "corrected BPM \(corrected.bpm) not in [80, 175]")
        #expect(abs(corrected.bpm - rawBPM / 2) < 0.01,
                "expected ~\(rawBPM / 2), got \(corrected.bpm)")

        // Beat count halved (take every other).
        #expect(corrected.beats.count == (beats.count + 1) / 2,
                "expected ~\(beats.count / 2) beats, got \(corrected.beats.count)")

        // First beat unchanged.
        #expect(abs(corrected.beats[0] - beats[0]) < 1e-9)

        // Inter-beat interval is now ~0.49 s (double the original 0.245 s).
        let correctedPeriod = 60.0 / corrected.bpm
        if corrected.beats.count >= 2 {
            let actualIOI = corrected.beats[1] - corrected.beats[0]
            #expect(abs(actualIOI - correctedPeriod) < 0.001,
                    "IOI \(actualIOI) vs period \(correctedPeriod)")
        }
    }

    // MARK: 11. halvingOctaveCorrected — genuinely slow (BPM < 80, no-op)

    @Test("halvingOctaveCorrected_slowBPM_isNoOp")
    func test_halvingOctaveCorrected_slowBPM_isNoOp() {
        // Pyramid Song ~68 BPM — must NOT be doubled.
        let period = 60.0 / 68.18
        let beats = (0..<12).map { Double($0) * period }
        let grid = BeatGrid(
            beats: beats, downbeats: [0.0, beats[3]], bpm: 68.18, beatsPerBar: 3,
            barConfidence: 0.9, frameRate: 50, frameCount: 500
        )
        let corrected = grid.halvingOctaveCorrected()

        // Must be identical — no correction applied.
        #expect(corrected.bpm == grid.bpm)
        #expect(corrected.beats.count == grid.beats.count)
        #expect(corrected.beatsPerBar == grid.beatsPerBar)
    }

    // MARK: 12. halvingOctaveCorrected — in-range (no-op)

    @Test("halvingOctaveCorrected_inRangeBPM_isNoOp")
    func test_halvingOctaveCorrected_inRangeBPM_isNoOp() {
        let period = 60.0 / 120.0
        let beats = (0..<24).map { Double($0) * period }
        let grid = BeatGrid(
            beats: beats, downbeats: [], bpm: 120, beatsPerBar: 4,
            barConfidence: 0.8, frameRate: 50, frameCount: 600
        )
        let corrected = grid.halvingOctaveCorrected()
        #expect(corrected.bpm == 120)
        #expect(corrected.beats.count == beats.count)
    }

    // MARK: 13. halvingOctaveCorrected — extreme (double-halve)

    @Test("halvingOctaveCorrected_extremeBPM_halvesTwice")
    func test_halvingOctaveCorrected_extremeBPM_halvesTwice() {
        // 360 BPM → 180 (still > 175) → 90 (in range). Picks a clean
        // double-halve fixture under the BUG-009 threshold of 175.
        let rawBPM = 360.0
        let period = 60.0 / rawBPM
        let beats = (0..<60).map { Double($0) * period }   // ~10 s
        let grid = BeatGrid(
            beats: beats, downbeats: [], bpm: rawBPM, beatsPerBar: 4,
            barConfidence: 0, frameRate: 50, frameCount: 500
        )
        let corrected = grid.halvingOctaveCorrected()
        // 360 → 180 (still > 175) → 90 (in range).
        #expect(corrected.bpm > 80 && corrected.bpm <= 175,
                "corrected BPM \(corrected.bpm) not in [80, 175]")
        #expect(abs(corrected.bpm - 90) < 0.01,
                "expected 90 BPM after two halvings, got \(corrected.bpm)")
        // Beat count should be quartered (factor 4 thinning).
        #expect(corrected.beats.count <= (beats.count + 3) / 4 + 1)
    }

    // MARK: 13b. halvingOctaveCorrected — fast-rock band [160, 175] is no-op (BUG-009)

    @Test("halvingOctaveCorrected_fastRockBPM_isNoOp")
    func test_halvingOctaveCorrected_fastRockBPM_isNoOp() {
        // BUG-009: tracks in [160, 175] BPM are now preserved un-halved.
        // Pre-BUG-009 (threshold 160) halved Everlong (~158) when the live
        // analyser overshot to 165–180 — visual orb pulsed at half rate.
        // Post-BUG-009 (threshold 175): legitimate fast tempos pass through.
        let fixtures: [(label: String, bpm: Double)] = [
            ("Everlong-class fast rock", 158.0),
            ("live-overshoot Everlong", 168.0),
            ("drum'n'bass", 172.5),
            ("at-threshold", 175.0)
        ]
        for fixture in fixtures {
            let period = 60.0 / fixture.bpm
            let beats = (0..<28).map { Double($0) * period }
            let grid = BeatGrid(
                beats: beats, downbeats: [0.0], bpm: fixture.bpm, beatsPerBar: 4,
                barConfidence: 1.0, frameRate: 50, frameCount: 500
            )
            let corrected = grid.halvingOctaveCorrected()
            #expect(corrected.bpm == fixture.bpm,
                    "\(fixture.label) at \(fixture.bpm) BPM was incorrectly halved to \(corrected.bpm)")
            #expect(corrected.beats.count == grid.beats.count,
                    "\(fixture.label): beat count changed from \(grid.beats.count) to \(corrected.beats.count)")
        }
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
