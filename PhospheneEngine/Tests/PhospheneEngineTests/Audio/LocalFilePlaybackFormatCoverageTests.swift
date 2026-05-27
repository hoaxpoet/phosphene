// LocalFilePlaybackFormatCoverageTests — LF.2 (2026-05-27).
//
// Exercises the LF.2 pre-analysis path against multiple container formats:
// M4A/AAC, MP3, FLAC (+ WAV when present). The load-bearing question is
// "does AVAudioFile decode this format, and does the resulting PCM run
// cleanly through SessionPreparer.analyzePreview?" The downstream LF.2
// install path (BeatGrid + StemFeatures install on the live pipeline)
// is exercised by the live capture run; this suite tests the format-
// decode + offline-analysis surface only.
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
    }
}
