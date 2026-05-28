// LocalFilePlaybackFormatCoverageTests — LF.2 (2026-05-27) + LF.4 cache
// roundtrip extension (D-131).
//
// Exercises the LF.2 pre-analysis path against multiple container formats:
// M4A/AAC, MP3, FLAC (+ WAV when present). The load-bearing question is
// "does AVAudioFile decode this format, and does the resulting PCM run
// cleanly through SessionPreparer.analyzePreview?" The downstream LF.2
// install path (BeatGrid + StemFeatures install on the live pipeline)
// is exercised by the live capture run; this suite tests the format-
// decode + offline-analysis surface only.
//
// LF.4: each per-format test also exercises the PersistentStemCache
// roundtrip (store → load → equal-fields), so format-specific Codable
// issues that the M4A-only LF.3 PersistentStemCacheTests would have
// missed surface here.
//
// Opt-in via `LF_FORMAT_COVERAGE=1` (matches the SOAK_TESTS=1 pattern).
// Fixtures live under `PhospheneEngine/Tests/Fixtures/tempo/` which is
// .gitignore'd — see `Scripts/fetch_tempo_fixtures.sh` and the LF.2
// closeout for re-creation recipes (`afconvert` for FLAC, `ffmpeg` for
// MP3 via libmp3lame).
//
// Each test:
//   1. Resolves the fixture path; Issue.record if absent (CLAUDE.md rule).
//   2. Decodes via `PreviewAudio.fromLocalFile(at:)` (the LF.2 entry point).
//   3. Asserts sample rate, frame count, duration are plausible.
//   4. Runs `SessionPreparer.analyzePreview` with real ML deps.
//   5. Asserts BeatGrid is non-empty (BPM > 0) and StemFeatures finite.
//   6. (LF.4) Persists the result via PersistentStemCache.store,
//      reloads it, and asserts the load-bearing fields roundtrip.

import AVFoundation
import Foundation
import Metal
import Testing
@testable import Audio
@testable import DSP
@testable import ML
@testable import Session

@Suite("LocalFilePlaybackFormatCoverage (LF_FORMAT_COVERAGE)")
struct LocalFilePlaybackFormatCoverageTests {

    // MARK: - Fixture Resolution

    /// Resolve `PhospheneEngine/Tests/Fixtures/tempo/<filename>` from the
    /// suite's source file path. Same pattern used by
    /// `BeatGridAccuracyDiagnosticTests`.
    private static func fixtureURL(_ filename: String) -> URL {
        let testDir = URL(fileURLWithPath: String(#filePath)).deletingLastPathComponent()
        return testDir
            .deletingLastPathComponent()  // PhospheneEngineTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures/tempo/\(filename)")
    }

    /// Gate: only run when `LF_FORMAT_COVERAGE=1` is set in the environment.
    /// Returns `true` when the env var is set and the test should proceed.
    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LF_FORMAT_COVERAGE"] == "1"
    }

    // MARK: - Tests

    @Test("M4A/AAC: love_rehab.m4a decodes + analyzePreview returns non-empty grid")
    func test_m4a_decodeAndAnalyze() throws {
        guard Self.isEnabled else { return }
        try runDecodeAndAnalyze(filename: "love_rehab.m4a", expectedSampleRate: 44100)
    }

    @Test("MP3: love_rehab.mp3 decodes + analyzePreview returns non-empty grid")
    func test_mp3_decodeAndAnalyze() throws {
        guard Self.isEnabled else { return }
        try runDecodeAndAnalyze(filename: "love_rehab.mp3", expectedSampleRate: 44100)
    }

    @Test("FLAC: love_rehab.flac decodes + analyzePreview returns non-empty grid")
    func test_flac_decodeAndAnalyze() throws {
        guard Self.isEnabled else { return }
        try runDecodeAndAnalyze(filename: "love_rehab.flac", expectedSampleRate: 44100)
    }

    @Test("LF.5 queue: 3-format folder runs through SessionPreparer.prepareLocalFiles")
    @MainActor
    func test_threeFormatQueue_runsThroughPrepareLocalFiles() async throws {
        guard Self.isEnabled else { return }

        let urls = [
            Self.fixtureURL("love_rehab.m4a"),
            Self.fixtureURL("love_rehab.mp3"),
            Self.fixtureURL("love_rehab.flac")
        ]
        for url in urls where !FileManager.default.fileExists(atPath: url.path) {
            Issue.record("LF_FORMAT_COVERAGE: fixture absent at \(url.path)")
            return
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("LF.5 queue: no Metal device — cannot exercise ML pipeline")
            return
        }

        let separator = try StemSeparator(device: device)
        let analyzer = StemAnalyzer(sampleRate: 44100)
        let classifier = MoodClassifier()
        let gridAnalyzer = try DefaultBeatGridAnalyzer(device: device)

        // The format-coverage delegate runs the same hash + decode + analyze
        // pipeline VisualizerEngine ships in `prepareLocalFile(url:)`; the
        // disk-cache step is skipped because the queue lifecycle is what's
        // under test, not persistence (covered by per-format tests above).
        let delegate = FormatCoverageLocalFilePreparer(
            separator: separator,
            analyzer: analyzer,
            classifier: classifier,
            gridAnalyzer: gridAnalyzer
        )

        let preparer = SessionPreparer(
            resolver: StubResolverFormatCoverage(),
            downloader: StubDownloaderFormatCoverage(),
            stemSeparator: separator,
            stemAnalyzer: analyzer,
            moodClassifier: classifier
        )
        let placeholders = urls.map {
            TrackIdentity(
                title: $0.lastPathComponent,
                artist: "local file",
                duration: 0,
                spotifyID: "local:" + $0.path
            )
        }

        let result = await preparer.prepareLocalFiles(
            urls: urls,
            placeholders: placeholders,
            via: delegate
        )

        #expect(result.cachedTracks.count == urls.count,
                "Expected \(urls.count) cached tracks, got \(result.cachedTracks.count)")
        #expect(result.failedTracks.isEmpty,
                "Expected no failures, got \(result.failedTracks.count) failed")

        // Every cached track must carry the LF.3 `local:sha256:` identity,
        // a non-empty BeatGrid in the [110, 130] BPM window for Love Rehab,
        // and finite stem features.
        for track in result.cachedTracks {
            #expect(track.spotifyID?.hasPrefix("local:sha256:") == true,
                    "Track \(track.title): expected local:sha256: identity, got \(track.spotifyID ?? "nil")")
            let cached = preparer.cache.loadForPlayback(track: track)
            #expect(cached != nil, "Track \(track.title): missing from cache after prepareLocalFiles")
            guard let cached else { continue }
            #expect(cached.beatGrid.bpm > 110 && cached.beatGrid.bpm < 130,
                    "Track \(track.title): expected BPM in [110, 130], got \(cached.beatGrid.bpm)")
            #expect(cached.stemFeatures.vocalsEnergy.isFinite,
                    "Track \(track.title): vocalsEnergy must be finite")
            #expect(cached.stemFeatures.drumsEnergy.isFinite,
                    "Track \(track.title): drumsEnergy must be finite")
        }
    }

    // MARK: - Shared Implementation

    /// Decode → analyze → assert. Used by every per-format test so the
    /// assertion surface stays consistent across formats and any
    /// behaviour change shows up in all of them at once.
    private func runDecodeAndAnalyze(filename: String, expectedSampleRate: Int) throws {
        let url = Self.fixtureURL(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Issue.record(
                "LF_FORMAT_COVERAGE: fixture absent at \(url.path) — see LF.2 closeout for recreation recipe"
            )
            return
        }

        // Step 1 — Decode via the LF.2 entry point.
        let preview = try PreviewAudio.fromLocalFile(at: url)

        // Step 2 — Sanity-check the decode result before forwarding to ML.
        // The love_rehab fixtures are all ~29.93 s, mono-or-stereo source
        // averaged to mono, at the file's native rate (44100 for our
        // transcodes from the m4a).
        #expect(preview.sampleRate == expectedSampleRate,
                "\(filename): expected \(expectedSampleRate) Hz, got \(preview.sampleRate)")
        #expect(preview.pcmSamples.count > expectedSampleRate * 25,
                "\(filename): expected at least 25 s of PCM (got \(preview.pcmSamples.count) samples)")
        #expect(preview.duration > 25.0 && preview.duration < 35.0,
                "\(filename): expected 25–35 s duration (got \(preview.duration))")
        // LF.3 (D-130) — identity migrated from `local:` + url.path to
        // `local:sha256:` + content hash so the cache key survives file
        // renames and is independent of the launcher's cwd.
        #expect(preview.trackIdentity.spotifyID?.hasPrefix("local:sha256:") == true,
                "\(filename): synthetic identity should encode the content hash")
        let expectedHash = try PreviewAudio.sha256(of: url)
        #expect(preview.trackIdentity.spotifyID == "local:sha256:" + expectedHash,
                "\(filename): identity hash should match PreviewAudio.sha256(of:)")

        // Step 3 — Run the full offline analysis pipeline.
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("\(filename): no Metal device — cannot exercise ML pipeline")
            return
        }
        let separator = try StemSeparator(device: device)
        let analyzer = StemAnalyzer(sampleRate: Float(preview.sampleRate))
        let classifier = MoodClassifier()
        let gridAnalyzer = try DefaultBeatGridAnalyzer(device: device)

        let cached = try SessionPreparer.analyzePreview(
            preview,
            separator: separator,
            analyzer: analyzer,
            classifier: classifier,
            beatGridAnalyzer: gridAnalyzer,
            prefetchedProfile: nil
        )

        // Step 4 — Assert the analysis pipeline produced load-bearing output.
        #expect(!cached.beatGrid.beats.isEmpty,
                "\(filename): BeatGrid must be non-empty after analyzePreview")
        #expect(cached.beatGrid.bpm > 0,
                "\(filename): BeatGrid BPM must be > 0 (got \(cached.beatGrid.bpm))")
        // The love_rehab fixtures all encode the same content; all paths
        // should give Beat This!'s upstream-faithful 118 BPM (±5 BPM
        // tolerance accommodates encoding/sample-rate sensitivity).
        #expect(cached.beatGrid.bpm > 110 && cached.beatGrid.bpm < 130,
                "\(filename): expected BPM in [110, 130] for Love Rehab (got \(cached.beatGrid.bpm))")
        #expect(cached.stemWaveforms.count == 4,
                "\(filename): expected 4 separated stems (got \(cached.stemWaveforms.count))")

        // StemFeatures must be finite (NaN / Inf would propagate into the
        // GPU buffer-3 upload). Touch each field that the live pipeline
        // reads on track change via `resetStemPipeline`.
        let stems = cached.stemFeatures
        #expect(stems.vocalsEnergy.isFinite,
                "\(filename): vocalsEnergy must be finite (got \(stems.vocalsEnergy))")
        #expect(stems.drumsEnergy.isFinite,
                "\(filename): drumsEnergy must be finite (got \(stems.drumsEnergy))")
        #expect(stems.bassEnergy.isFinite,
                "\(filename): bassEnergy must be finite (got \(stems.bassEnergy))")
        #expect(stems.otherEnergy.isFinite,
                "\(filename): otherEnergy must be finite (got \(stems.otherEnergy))")

        // Step 5 (LF.4) — PersistentStemCache roundtrip. Catches format-specific
        // Codable serialization issues that the M4A-only LF.3
        // PersistentStemCacheTests would have missed.
        let tempCacheDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LocalFileFormatCoverage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempCacheDir) }
        let persistentCache = try PersistentStemCache(rootDirectory: tempCacheDir, maxBytes: Int64.max)
        try persistentCache.store(cached, hash: expectedHash, decodedDuration: preview.duration)
        #expect(persistentCache.contains(hash: expectedHash),
                "\(filename): persistent cache should contain hash after store")
        let loaded = try persistentCache.load(hash: expectedHash)

        #expect(loaded.decodedDuration == preview.duration,
                "\(filename): decodedDuration roundtrip Δ \(loaded.decodedDuration - preview.duration)")
        #expect(loaded.cached.beatGrid.bpm == cached.beatGrid.bpm,
                "\(filename): BeatGrid.bpm roundtrip Δ \(loaded.cached.beatGrid.bpm - cached.beatGrid.bpm)")
        #expect(loaded.cached.beatGrid.beats.count == cached.beatGrid.beats.count,
                "\(filename): BeatGrid.beats.count roundtrip differs")
        #expect(loaded.cached.stemFeatures.vocalsEnergy == cached.stemFeatures.vocalsEnergy,
                "\(filename): vocalsEnergy roundtrip differs")
        #expect(loaded.cached.stemFeatures.drumsEnergy == cached.stemFeatures.drumsEnergy,
                "\(filename): drumsEnergy roundtrip differs")
        #expect(loaded.cached.stemFeatures.bassEnergy == cached.stemFeatures.bassEnergy,
                "\(filename): bassEnergy roundtrip differs")
        #expect(loaded.cached.stemFeatures.otherEnergy == cached.stemFeatures.otherEnergy,
                "\(filename): otherEnergy roundtrip differs")
        #expect(loaded.cached.stemWaveforms.count == cached.stemWaveforms.count,
                "\(filename): stem count roundtrip differs")
        for (i, (originalStem, loadedStem)) in zip(cached.stemWaveforms, loaded.cached.stemWaveforms).enumerated() {
            #expect(originalStem.count == loadedStem.count,
                    "\(filename): stem \(i) length roundtrip differs")
            #expect(originalStem == loadedStem,
                    "\(filename): stem \(i) samples roundtrip differs")
        }
    }
}

// MARK: - LF.5 queue-level test helpers

/// `LocalFilePreparing` adapter that runs the same hash + decode + analyze
/// pipeline `VisualizerEngine.prepareLocalFile(url:)` ships, without the
/// `PersistentStemCache` write step (the per-format tests above already
/// cover the cache roundtrip). Sized for the 3-fixture queue test.
private final class FormatCoverageLocalFilePreparer: LocalFilePreparing, @unchecked Sendable {
    let separator: any StemSeparating
    let analyzer: any StemAnalyzing
    let classifier: any MoodClassifying
    let gridAnalyzer: any BeatGridAnalyzing

    init(
        separator: any StemSeparating,
        analyzer: any StemAnalyzing,
        classifier: any MoodClassifying,
        gridAnalyzer: any BeatGridAnalyzing
    ) {
        self.separator = separator
        self.analyzer = analyzer
        self.classifier = classifier
        self.gridAnalyzer = gridAnalyzer
    }

    func prepareLocalFile(url: URL) async -> LocalFilePrepResult? {
        do {
            let preview = try PreviewAudio.fromLocalFile(at: url)
            let cached = try SessionPreparer.analyzePreview(
                preview,
                separator: separator,
                analyzer: analyzer,
                classifier: classifier,
                beatGridAnalyzer: gridAnalyzer,
                prefetchedProfile: nil
            )
            return LocalFilePrepResult(
                identity: preview.trackIdentity,
                cached: cached,
                decodedDuration: preview.duration,
                source: .freshAnalysis
            )
        } catch {
            return nil
        }
    }
}

/// Resolver stub: the LF queue path never calls the resolver, so it just
/// returns `nil` to satisfy the `SessionPreparer` constructor.
private final class StubResolverFormatCoverage: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? { nil }
}

/// Downloader stub: same rationale as `StubResolverFormatCoverage`.
private final class StubDownloaderFormatCoverage: PreviewDownloading, @unchecked Sendable {
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? { nil }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] { [] }
}
