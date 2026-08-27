// StemSeriesWiringTests — LFSTEM.1c/1e wiring gate.
//
// The series' arithmetic is tested in the engine suite (`StemFeatureSeriesTests`, alignment) and
// its persistence in `PersistentStemCacheTests`. What cannot be tested there is the WIRING: the
// engine needs Metal, a session and a decoded file to reach `publishStemSeriesFrame`, so the
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

@Suite("Stem series wiring (LFSTEM.1c/1e/2)")
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

    /// Invariant 1 — the live path stands down when a series is installed, and the series is
    /// sampled on the RENDER frame rather than the analysis frame.
    ///
    /// The render-frame call site is the BUG-109 fix: sampling on the analysis frame capped stem
    /// motion at 12.8 Hz (measured) while the renderer drew at 59.9 and the series carries 43 Hz.
    /// Live separation had to publish on the analysis frame because it had nothing new between
    /// them; a pre-analysed series is an array lookup and has no such bound.
    @Test("The live path stands down, and the series is sampled per RENDER frame")
    func test_livePathStandsDownForASeries() {
        guard let audio = source("PhospheneApp/VisualizerEngine+Audio.swift"),
              let draw = source("PhospheneEngine/Sources/Renderer/RenderPipeline+Draw.swift"),
              let initHelpers = source("PhospheneApp/VisualizerEngine+InitHelpers.swift")
        else { return }

        #expect(audio.contains("if stemSeriesLock.withLock({ !currentStemSeries.isEmpty }) { return }"), """
                runPerFrameStemAnalysis must early-return when a series is installed. Without it \
                both it and publishStemSeriesFrame publish StemFeatures and the last writer wins.
                """)
        #expect(audio.contains("func publishStemSeriesFrame()"),
                "The series read path must exist as its own helper.")
        #expect(initHelpers.contains("setPerFrameStemPublish"), """
                publishStemSeriesFrame must be wired to the RENDER frame. Sampling on the \
                analysis frame is BUG-109: it caps stem motion at the analysis rate.
                """)
        #expect(audio.contains("latestRawPlaybackSeconds = mir.elapsedSeconds"), """
                The analysis frame must publish the PLAYBACK clock for the render frame to \
                sample with — the point is reading the second playback is on.
                """)

        // Ordering: the publish must precede the frame's stem snapshot, or it lands a frame late.
        if let publish = draw.range(of: "perFrameStemPublish }?()"),
           let snapshot = draw.range(of: "let stemFeatures   = stemFeaturesLock.withLock") {
            #expect(publish.lowerBound < snapshot.lowerBound, """
                    the per-frame stem publish runs AFTER the frame snapshots stemFeatures, so \
                    this frame draws the previous frame's stems — an off-by-one-frame lag.
                    """)
        }
    }

    /// Invariant 1b (LFSTEM.2) — live separation stops for a track that has a series, and ONLY
    /// for such a track.
    ///
    /// The gate has to sit on the series, not on the source. "This is a local file" would strand
    /// a cache miss, a schema mismatch or a failed analysis with no stems at all: those leave the
    /// series empty and must keep the live path exactly as it was. The suppression is counted so
    /// a session can show the saving rather than assert it — zero `STEM_SEPARATION` lines and a
    /// rising `stem_suppressed` in `GPU_PRESSURE`.
    @Test("Live separation is suppressed by the SERIES, not by the source being a local file")
    func test_separationSuppressedBySeriesOnly() {
        guard let stems = source("PhospheneApp/VisualizerEngine+Stems.swift"),
              let initHelpers = source("PhospheneApp/VisualizerEngine+InitHelpers.swift")
        else { return }

        #expect(stems.contains("if separationSupersededBySeries() { return }"), """
                runStemSeparation must skip the MPSGraph dispatch when a series supersedes it — \
                that 142 ms job every 2 s is LFSTEM.2's whole saving.
                """)
        let seriesGate = "guard stemSeriesLock.withLock({ !currentStemSeries.isEmpty }) "
            + "else { return false }"
        #expect(stems.contains(seriesGate), """
                the suppression must be gated on the SERIES, not on the source. A local file with \
                no series (cache miss, schema mismatch, failed analysis) must keep live \
                separation, or it plays with no stems at all.
                """)
        #expect(!stems.contains("origin == .localFile") || !stems.contains("suppressedSeparations"), """
                the suppression appears to be gated on the playback SOURCE rather than on whether \
                a series exists — that is the fallback policy inverted.
                """)
        #expect(initHelpers.contains("stem_suppressed"), """
                the suppression count must reach the session artifact, or the saving is an \
                assertion rather than a measurement.
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
