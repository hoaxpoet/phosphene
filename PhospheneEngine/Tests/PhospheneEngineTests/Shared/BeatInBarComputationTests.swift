// BeatInBarComputationTests — beat-in-bar index from barPhase01 + beatsPerBar.
//
// Validates the formula: beatInBar = floor(barPhase01 * beatsPerBar) + 1, clamped [1, bpb].
// Used in both SpectralCartographText.drawBeatInBar() and VisualizerEngine+Audio.swift.

import Testing
import Shared

// MARK: - BeatInBarComputationTests

@Suite("BeatInBar computation")
struct BeatInBarComputationTests {

    // Formula under test — mirrors VisualizerEngine+Audio and SpectralCartographText.
    private func beatInBar(barPhase01: Float, beatsPerBar: Int) -> Int {
        let bpb = max(1, beatsPerBar)
        let raw = Int(barPhase01 * Float(bpb)) + 1
        return max(1, min(raw, bpb))
    }

    // MARK: - 4/4 time

    @Test func fourFour_phaseZero_isDownbeat() {
        #expect(beatInBar(barPhase01: 0.0, beatsPerBar: 4) == 1)
    }

    @Test func fourFour_phaseOneTenth_isBeat1() {
        #expect(beatInBar(barPhase01: 0.1, beatsPerBar: 4) == 1)
    }

    @Test func fourFour_phaseQuarter_isBeat2() {
        // 0.25 * 4 = 1 → index 2
        #expect(beatInBar(barPhase01: 0.25, beatsPerBar: 4) == 2)
    }

    @Test func fourFour_phaseHalf_isBeat3() {
        // 0.5 * 4 = 2 → index 3
        #expect(beatInBar(barPhase01: 0.50, beatsPerBar: 4) == 3)
    }

    @Test func fourFour_phaseThreeQuarters_isBeat4() {
        // 0.75 * 4 = 3 → index 4
        #expect(beatInBar(barPhase01: 0.75, beatsPerBar: 4) == 4)
    }

    @Test func fourFour_phaseAlmostOne_isBeat4() {
        #expect(beatInBar(barPhase01: 0.99, beatsPerBar: 4) == 4)
    }

    @Test func fourFour_phaseExactlyOne_clampedToBeat4() {
        // phase = 1.0 would give raw index 5, clamped to 4.
        #expect(beatInBar(barPhase01: 1.0, beatsPerBar: 4) == 4)
    }

    // MARK: - 7/4 time (irregular meter)

    @Test func sevenFour_phaseZero_isDownbeat() {
        #expect(beatInBar(barPhase01: 0.0, beatsPerBar: 7) == 1)
    }

    @Test func sevenFour_phaseOneOverSeven_isBeat2() {
        // 1/7 ≈ 0.1429 * 7 = 1.0 → floor = 1 → index 2
        #expect(beatInBar(barPhase01: Float(1) / 7.0, beatsPerBar: 7) == 2)
    }

    @Test func sevenFour_phaseAlmostOne_isBeat7() {
        #expect(beatInBar(barPhase01: 0.995, beatsPerBar: 7) == 7)
    }

    // MARK: - 16/8 time (Pyramid Song style)

    @Test func sixteenEight_phaseZero_isDownbeat() {
        #expect(beatInBar(barPhase01: 0.0, beatsPerBar: 16) == 1)
    }

    @Test func sixteenEight_phaseOneSixteenth_isBeat2() {
        #expect(beatInBar(barPhase01: 1.0 / 16.0, beatsPerBar: 16) == 2)
    }

    @Test func sixteenEight_phaseHalf_isBeat9() {
        // 0.5 * 16 = 8 → index 9
        #expect(beatInBar(barPhase01: 0.5, beatsPerBar: 16) == 9)
    }

    // MARK: - Edge cases

    @Test func zeroBeatsPerBar_clampsToOne() {
        #expect(beatInBar(barPhase01: 0.5, beatsPerBar: 0) == 1)
    }

    @Test func negativePhase_clampsToOne() {
        #expect(beatInBar(barPhase01: -0.1, beatsPerBar: 4) == 1)
    }

    // MARK: - BeatSyncSnapshot isDownbeat

    @Test func snapshot_isDownbeat_whenBeatInBarIsOne() {
        let snap = BeatSyncSnapshot(
            barPhase01: 0.0, beatsPerBar: 4, beatInBar: 1, isDownbeat: true,
            sessionMode: 2, lockState: 2, gridBPM: 120, playbackTimeS: 0, driftMs: 0
        )
        #expect(snap.isDownbeat == true)
    }

    @Test func snapshot_notDownbeat_whenBeatInBarIsTwo() {
        let snap = BeatSyncSnapshot(
            barPhase01: 0.26, beatsPerBar: 4, beatInBar: 2, isDownbeat: false,
            sessionMode: 2, lockState: 2, gridBPM: 120, playbackTimeS: 0, driftMs: 0
        )
        #expect(snap.isDownbeat == false)
    }

    @Test func snapshot_zero_isInitialized() {
        let snap = BeatSyncSnapshot.zero
        #expect(snap.barPhase01 == 0)
        #expect(snap.beatsPerBar == 4)
        #expect(snap.beatInBar == 1)
        #expect(snap.sessionMode == 0)
        #expect(snap.lockState == 0)
        #expect(snap.gridBPM == 0)
        #expect(snap.driftMs == 0)
    }
}
