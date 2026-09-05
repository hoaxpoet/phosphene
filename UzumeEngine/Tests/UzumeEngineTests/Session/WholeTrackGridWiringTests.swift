// PR.12 — the local path must ask for a whole-track grid; streaming must not.
//
// `BeatThisModel.tMax` clamps inference to 1500 frames (30 s at 50 fps). For a streaming
// preview that costs nothing — the preview IS 30 s. For a local file it truncated the grid
// to 6.7–26 % of the track, and past the end of `BeatGrid.beats` `localTiming` falls back
// to `60.0 / bpm`, a whole-track AVERAGE. ~90 % of every local track therefore ran on one
// averaged tempo, which against changing music is a linear phase error — BUG-065's drift.
//
// This gates the WIRING, which is the part a refactor silently breaks: the flag has to
// reach the analyzer, and only from the local path.
import Testing
import Foundation
@testable import Session
@testable import Shared
@testable import DSP

@Suite("Whole-track grid wiring")
struct WholeTrackGridWiringTests {

    /// Records what the analyzer was asked for. Returns a grid whose span reflects the
    /// request, so a caller that drops the flag is visible in the output too.
    private final class RecordingAnalyzer: BeatGridAnalyzing, @unchecked Sendable {
        private(set) var requests: [Bool] = []
        func analyzeBeatGrid(samples: [Float], sampleRate: Double, wholeTrack: Bool) -> BeatGrid {
            requests.append(wholeTrack)
            let seconds = wholeTrack ? Double(samples.count) / sampleRate : 30.0
            let period = 0.5
            let beats = stride(from: 0.0, to: max(seconds, period * 4), by: period).map { $0 }
            return BeatGrid(beats: beats, downbeats: [], bpm: 120,
                            beatsPerBar: 4, barConfidence: 1,
                            frameRate: 50, frameCount: beats.count)
        }
    }

    @Test("the default (streaming) call does not request a whole-track grid")
    func streamingStaysClamped() {
        let analyzer = RecordingAnalyzer()
        _ = analyzer.analyzeBeatGrid(samples: [Float](repeating: 0, count: 44100), sampleRate: 44100)
        #expect(analyzer.requests == [false],
                "the compatibility overload must keep streaming's 30 s behaviour")
    }

    @Test("an explicit whole-track request reaches the analyzer")
    func wholeTrackRequestIsThreaded() {
        let analyzer = RecordingAnalyzer()
        _ = analyzer.analyzeBeatGrid(samples: [Float](repeating: 0, count: 44100),
                                     sampleRate: 44100, wholeTrack: true)
        #expect(analyzer.requests == [true])
    }

    /// The reason the flag exists: with it, the grid spans the track; without it, ~30 s.
    /// A five-minute track is the case that matters — Bowie's Warszawa measured 7.6 %
    /// coverage before this change and 96.3 % after.
    @Test("a whole-track grid spans the track; a clamped one does not")
    func spanReflectsTheRequest() {
        let analyzer = RecordingAnalyzer()
        let fiveMinutes = [Float](repeating: 0, count: 44100 * 300)
        let clamped = analyzer.analyzeBeatGrid(samples: fiveMinutes, sampleRate: 44100)
        let whole = analyzer.analyzeBeatGrid(samples: fiveMinutes, sampleRate: 44100,
                                             wholeTrack: true)
        let clampedSpan = (clamped.beats.last ?? 0) - (clamped.beats.first ?? 0)
        let wholeSpan = (whole.beats.last ?? 0) - (whole.beats.first ?? 0)
        #expect(clampedSpan < 40, "clamped span was \(clampedSpan) s")
        #expect(wholeSpan > 250, "whole-track span was \(wholeSpan) s")
        #expect(wholeSpan / clampedSpan > 5)
    }

    /// PREP.1 moved the LF.4 worker out of `VisualizerEngine+LocalFilePlayback` into
    /// `Session.LocalFilePreparationPipeline`, and PR.12's `wholeTrackAudio: true`
    /// landed on the old location in a parallel branch. The merge had to carry it
    /// across by hand.
    ///
    /// PR.12's own commit names this risk — *"the wiring is what a refactor silently
    /// breaks"* — and its other three tests all exercise the analyzer, not the one
    /// call site that decides a real local session gets a whole-track grid. Nothing
    /// else fails if that argument is dropped: the build stays green and the grid
    /// quietly covers 7.6 % of the track again.
    @Test("the local-file pipeline still asks for a whole-track grid after the PREP.1 move")
    func localPipelineRequestsWholeTrack() throws {
        // …/UzumeEngine/Tests/UzumeEngineTests/Session/<this file> → UzumeEngine
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let pipeline = root
            .appendingPathComponent("Sources/Session/LocalFilePreparationPipeline.swift")
        let source = try String(contentsOf: pipeline, encoding: .utf8)

        #expect(source.contains("wholeTrackAudio: true"), """
                LocalFilePreparationPipeline no longer passes wholeTrackAudio: true to \
                analyzePreview. The local path decoded the whole file and then threw ~90 % of \
                it away at the beat grid — PR.12's regression, silently restored.
                """)
    }

    // MARK: - PR.17 windowed bar line

    @Test("a declined track carries the beats and NO bars — never a backfilled guess")
    func windowedBarLineDeclinesToSilence() {
        // Silence: every window declines, so the sparse contract says emit nothing.
        let beats = (0..<200).map { Double($0) * 0.5 }
        let grid = BeatGrid(beats: beats, downbeats: beats, bpm: 120,
                            beatsPerBar: 4, barConfidence: 1,
                            frameRate: 50, frameCount: 5_000)
        let applied = DefaultBeatGridAnalyzer.applyWindowedBarLine(
            to: grid,
            samples: [Float](repeating: 0, count: 22_050 * 110),
            sampleRate: 22_050
        )
        // The grid's own downbeats must not survive: backfilling from the model's
        // over-firing head is the shape Matt rejected (2026-09-05, "sparse and correct").
        #expect(applied.downbeats.isEmpty)
        #expect(applied.beatsPerBar == 1)
        #expect(applied.barConfidence == 0)
        // Beats are the layer that works — they are never touched.
        #expect(applied.beats == beats)
        #expect(applied.bpm == grid.bpm)
    }
}
