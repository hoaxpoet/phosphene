// StemSeriesWiringTests — LFSTEM.1c wiring gate.
//
// The series' arithmetic is tested in the engine suite (`StemFeatureSeriesTests`, alignment) and
// its persistence in `PersistentStemCacheTests`. What cannot be tested there is the WIRING: the
// engine needs Metal, a session and a decoded file to reach `applyStemSeriesFrame`, so the
// invariants below are asserted against the source shape — the same discriminator
// `TrackChangePresetResetRegressionTests` uses for the BUG-044 complementary-path rule.
//
// Three invariants, each with a specific failure it exists to catch:
//
//   1. Exactly one writer per frame. If the live path kept publishing StemFeatures while the
//      series did too, the last writer per frame would win — a race dressed as a feature.
//   2. The per-track surface is cleared on EVERY track change, not just the one that installs
//      it. That is the BUG-024 shape, where a publisher written on the LF path and never
//      cleared on the streaming path leaked one session's album art into every later track.
//   3. Streaming never gets a series. It cannot have one — a tap has no future to analyse — and
//      `analyzePreview` is shared, so the sweep must stay on the local-file path.

import Foundation
import Testing

@testable import PhospheneApp

@Suite("Stem series wiring (LFSTEM.1c)")
struct StemSeriesWiringTests {

    private func source(_ relativePath: String) -> String? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()           // PhospheneAppTests
            .deletingLastPathComponent()           // repo root
            .appendingPathComponent(relativePath)
        guard let src = try? String(contentsOf: url, encoding: .utf8) else {
            Issue.record("\(relativePath) not found at \(url.path)")
            return nil
        }
        return src
    }

    /// Invariant 1 — the live path stands down when a series is installed.
    @Test("Live per-frame stem analysis returns early when a series is installed")
    func test_livePathStandsDownForASeries() {
        guard let audio = source("PhospheneApp/VisualizerEngine+Audio.swift") else { return }
        #expect(audio.contains("if !currentStemSeries.isEmpty { return }"), """
                runPerFrameStemAnalysis must early-return when currentStemSeries is non-empty. \
                Without it both it and applyStemSeriesFrame publish StemFeatures every frame and \
                the last writer wins.
                """)
        #expect(audio.contains("func applyStemSeriesFrame(atPlaybackSeconds"),
                "The series read path must exist as its own helper on the analysis frame.")
        #expect(audio.contains("applyStemSeriesFrame(atPlaybackSeconds: mir.elapsedSeconds)"), """
                The series must be sampled by PLAYBACK position (mir.elapsedSeconds) — the whole \
                point is reading the second playback is on, not the one analysis reached.
                """)
    }

    /// Invariant 2 — cleared on every track change, installed on the one path that has data.
    @Test("The per-track series is cleared unconditionally and installed only on a cache hit")
    func test_clearedOnEveryTrackChange() {
        guard let stems = source("PhospheneApp/VisualizerEngine+Stems.swift") else { return }
        #expect(stems.contains("currentStemSeries = .empty"), """
                currentStemSeries must be cleared unconditionally on track change, beside the \
                instrument-family clear. A per-track surface cleared on only one path leaks the \
                previous track's data into every other path (BUG-024).
                """)
        #expect(stems.contains("currentStemSeries = cached.stemFeatureSeries"),
                "The cache-hit branch must install the track's series.")
        // Ordering: the clear must come BEFORE the install, or the install is undone.
        if let clear = stems.range(of: "currentStemSeries = .empty"),
           let install = stems.range(of: "currentStemSeries = cached.stemFeatureSeries") {
            #expect(clear.lowerBound < install.lowerBound, """
                    The unconditional clear must precede the cache-hit install, or every track \
                    starts with an empty series and the feature silently does nothing.
                    """)
        }
    }

    /// Invariant 3 — the sweep is local-file-only.
    @Test("Only the local-file path builds a series; the shared preview analysis does not")
    func test_streamingNeverGetsASeries() {
        guard let localFile = source("PhospheneApp/VisualizerEngine+LocalFilePlayback.swift"),
              let sharedAnalysis =
                source("PhospheneEngine/Sources/Session/SessionPreparer+Analysis.swift")
        else { return }

        #expect(localFile.contains("analyzeStemSeriesForLocalFile"), """
                The local-file path must build the series — it is the only path that decodes the \
                whole track.
                """)
        #expect(!sharedAnalysis.contains("analyzeStemSeries("), """
                analyzePreview is shared with streaming and must NOT build a series: a tap only \
                ever carries audio that has already played, so there is no future to analyse and \
                no reliable position to sample by. Keep the sweep at the local-file call site, \
                where LoudnessProfile already lives for the same reason.
                """)
    }
}
