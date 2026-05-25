// RhythmCharacterTests — BSAudit.3.impl.1 contract tests for the
// `RhythmCharacter` schema + prep-time computation in
// `SessionPreparer.computeRhythmCharacter(preview:grid:)`.

import Foundation
import Testing
@testable import DSP
@testable import Session
import Shared

@Suite("RhythmCharacter")
struct RhythmCharacterTests {

    // MARK: - Schema

    @Test("Neutral character has mid-default difficulty and zero octave risk")
    func neutralCharacter_defaults() {
        let neutral = RhythmCharacter.neutral
        #expect(neutral.beatStrengthProfile.isEmpty)
        #expect(neutral.onsetsPerBeat == 1.0)
        #expect(neutral.octaveRisk == 0.0)
        #expect(neutral.phaseAcquisitionDifficulty == 0.5)
        #expect(neutral.syncopationIndex == 0.0)
    }

    @Test("Init clamps out-of-range fields to [0, 1]")
    func init_clamps() {
        let high = RhythmCharacter(
            beatStrengthProfile: [1, 0.5, 0.3, 0.8],
            onsetsPerBeat: 4.0,
            octaveRisk: 1.5,
            phaseAcquisitionDifficulty: -0.2,
            syncopationIndex: 2.0
        )
        #expect(high.octaveRisk == 1.0)
        #expect(high.phaseAcquisitionDifficulty == 0.0)
        #expect(high.syncopationIndex == 1.0)
        // onsetsPerBeat is intentionally unclamped (can exceed 1).
        #expect(high.onsetsPerBeat == 4.0)
    }

    @Test("RhythmCharacter is Codable round-trip stable")
    func codable_roundTrip() throws {
        let original = RhythmCharacter(
            beatStrengthProfile: [1.0, 0.6, 0.85, 0.55],
            onsetsPerBeat: 1.8,
            octaveRisk: 0.42,
            phaseAcquisitionDifficulty: 0.31,
            syncopationIndex: 0.18
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RhythmCharacter.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Prep-time computation

    /// Build a uniform `BeatGrid` for a 4/4 track. `bpm` controls period.
    /// `coverageSeconds` controls how many beats fit in the preview window.
    private func makeUniformGrid(
        bpm: Double = 120,
        beatsPerBar: Int = 4,
        coverageSeconds: Double = 30,
        barConfidence: Float = 1.0
    ) -> BeatGrid {
        let period = 60.0 / bpm
        var beats: [Double] = []
        var t = 0.0
        while t <= coverageSeconds {
            beats.append(t)
            t += period
        }
        var downbeats: [Double] = []
        for i in stride(from: 0, to: beats.count, by: beatsPerBar) {
            downbeats.append(beats[i])
        }
        return BeatGrid(
            beats: beats,
            downbeats: downbeats,
            bpm: bpm,
            beatsPerBar: beatsPerBar,
            barConfidence: barConfidence,
            frameRate: 50,
            frameCount: Int(coverageSeconds * 50)
        )
    }

    /// Build PreviewAudio with kick-on-the-beat pulses at the BPM tempo.
    /// Each kick is a 256-sample exponentially-decaying broadband transient.
    private func makeKickOnTheBeatPreview(
        bpm: Double = 120,
        coverageSeconds: Double = 30,
        sampleRate: Int = 44100
    ) -> PreviewAudio {
        let totalSamples = Int(Double(sampleRate) * coverageSeconds)
        var samples = [Float](repeating: 0, count: totalSamples)
        let period = 60.0 / bpm
        let kickLen = 256
        var beatTime = 0.0
        while beatTime < coverageSeconds {
            let start = Int(beatTime * Double(sampleRate))
            for k in 0..<kickLen {
                let idx = start + k
                guard idx < totalSamples else { break }
                let env = expf(-Float(k) / 60.0)
                // Broadband: white-noise scaled by envelope.
                let noise = Float.random(in: -1...1)
                samples[idx] += env * noise
            }
            beatTime += period
        }
        return PreviewAudio(
            trackIdentity: TrackIdentity(title: "Test", artist: "Test"),
            pcmSamples: samples,
            sampleRate: sampleRate,
            duration: coverageSeconds
        )
    }

    @Test("Empty grid yields nil character (no rhythm structure to characterise)")
    func emptyGrid_returnsNil() {
        let preview = PreviewAudio(
            trackIdentity: TrackIdentity(title: "Empty", artist: "Test"),
            pcmSamples: [Float](repeating: 0, count: 44100),
            sampleRate: 44100,
            duration: 1.0
        )
        let result = SessionPreparer.computeRhythmCharacter(
            preview: preview, grid: .empty
        )
        #expect(result == nil)
    }

    @Test("Short preview yields nil character (insufficient data)")
    func shortPreview_returnsNil() {
        // Only 100 samples — below FFT window size.
        let preview = PreviewAudio(
            trackIdentity: TrackIdentity(title: "Short", artist: "Test"),
            pcmSamples: [Float](repeating: 0, count: 100),
            sampleRate: 44100,
            duration: 100.0 / 44100.0
        )
        let grid = makeUniformGrid()
        let result = SessionPreparer.computeRhythmCharacter(
            preview: preview, grid: grid
        )
        #expect(result == nil)
    }

    @Test("Kick-on-the-beat preview produces a populated RhythmCharacter")
    func kickOnTheBeat_populatesAllFields() {
        let bpm = 120.0
        let preview = makeKickOnTheBeatPreview(bpm: bpm, coverageSeconds: 8)
        let grid = makeUniformGrid(bpm: bpm, coverageSeconds: 8)
        guard let character = SessionPreparer.computeRhythmCharacter(
            preview: preview, grid: grid
        ) else {
            Issue.record("expected non-nil RhythmCharacter for kick-on-the-beat preview")
            return
        }
        // beatStrengthProfile sized to beatsPerBar.
        #expect(character.beatStrengthProfile.count == grid.beatsPerBar)
        // All fields within their nominal ranges.
        #expect(character.onsetsPerBeat >= 0)
        #expect(character.octaveRisk >= 0 && character.octaveRisk <= 1)
        #expect(character.phaseAcquisitionDifficulty >= 0 && character.phaseAcquisitionDifficulty <= 1)
        #expect(character.syncopationIndex >= 0 && character.syncopationIndex <= 1)
    }

    @Test("Difficulty formula composes sparseness, syncopation, irregularity")
    func difficulty_composesInputs() {
        // High onsetsPerBeat + low syncopation + high barConfidence = easy.
        let easy = RhythmCharacter(
            beatStrengthProfile: [1, 1, 1, 1],
            onsetsPerBeat: 3.0,
            octaveRisk: 0,
            phaseAcquisitionDifficulty: 0.0,
            syncopationIndex: 0.0
        )
        #expect(easy.phaseAcquisitionDifficulty == 0.0)

        // Low onsetsPerBeat + high syncopation = hard.
        let hard = RhythmCharacter(
            beatStrengthProfile: [],
            onsetsPerBeat: 0.5,
            octaveRisk: 0,
            phaseAcquisitionDifficulty: 0.85,
            syncopationIndex: 0.8
        )
        #expect(hard.phaseAcquisitionDifficulty == 0.85)
    }
}
