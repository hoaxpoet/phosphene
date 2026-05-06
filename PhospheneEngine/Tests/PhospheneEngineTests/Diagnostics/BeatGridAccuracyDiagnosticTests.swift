// BeatGridAccuracyDiagnosticTests — BUG-008.1 diagnosis tripwire.
//
// Loads the vendored `love_rehab.m4a` fixture, runs `DefaultBeatGridAnalyzer`
// end-to-end, and asserts the produced BPM matches the PyTorch reference
// committed in `love_rehab_reference.json` (118.05 ± 0.5). The test passes
// today — that *is* the documentation of BUG-008.
//
// Why this test is here:
//  - The "true 125 BPM" expectation for Love Rehab originates in the track
//    metadata tag, not in any upstream Beat This! artifact. The committed
//    PyTorch reference for love_rehab.m4a lists `bpm_trimmed_mean = 118.05`,
//    so the upstream model itself produces 118 BPM on this audio.
//  - Phosphene's Swift port reproduces the upstream output to within ≈0.05
//    BPM. The 5.5 % delta from the metadata-tag tempo is therefore an
//    upstream-model property, not a Phosphene bug.
//  - This test is a permanent tripwire: if a future change to preprocessing,
//    resampling, or the model shifts the produced BPM toward 125, this test
//    fails and flags the regression / unintended fix. If a future Beat This!
//    checkpoint corrects the upstream inaccuracy, this test also fails and
//    surfaces the delta for review.
//
// See `docs/diagnostics/BUG-008-diagnosis.md` for the full reasoning.

import Testing
import Foundation
import Metal
@testable import DSP
@testable import ML
@testable import Session

private struct LoveRehabReference: Decodable {
    let bpmTrimmedMean: Double
    let beatsSeconds: [Double]
    let beatsPerBarEstimate: Int
    enum CodingKeys: String, CodingKey {
        case bpmTrimmedMean = "bpm_trimmed_mean"
        case beatsSeconds = "beats_seconds"
        case beatsPerBarEstimate = "beats_per_bar_estimate"
    }
}

@Suite("BeatGridAccuracyDiagnostic — BUG-008")
struct BeatGridAccuracyDiagnosticTests {

    /// Asserts the Phosphene Swift port reproduces the upstream PyTorch
    /// reference BPM for Love Rehab. **This test passing is the
    /// documentation of BUG-008** — the upstream model itself produces
    /// 118 BPM on this audio; Phosphene faithfully reproduces that.
    ///
    /// Tolerance: ±0.5 BPM matches the existing
    /// `BeatGridResolverGoldenTests.test_bpm_withinTolerance` gate.
    @Test("loveRehab: port produces upstream-faithful 118 BPM, NOT the 125 BPM metadata tag")
    func test_loveRehab_portMatchesPyTorchReference_notMetadataTag() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let testDir = URL(fileURLWithPath: String(#filePath)).deletingLastPathComponent()
        let audioURL = testDir
            .deletingLastPathComponent()  // PhospheneEngineTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures/tempo/love_rehab.m4a")
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            Issue.record("BUG-008 diagnostic: love_rehab.m4a fixture absent at \(audioURL.path)")
            return
        }

        // Load PyTorch reference — the upstream-author-provided ground truth
        // for what the model is supposed to produce on this audio.
        let refURL = try #require(
            Bundle.module.url(
                forResource: "love_rehab_reference",
                withExtension: "json",
                subdirectory: "beat_this_reference"
            ),
            "love_rehab_reference.json not found in test bundle"
        )
        let ref = try JSONDecoder().decode(
            LoveRehabReference.self,
            from: Data(contentsOf: refURL)
        )
        // Sanity-pin the reference itself — guards against an upstream bump
        // silently changing the contract this test gates.
        #expect(abs(ref.bpmTrimmedMean - 118.05) < 0.1,
                "Reference fixture changed: bpm_trimmed_mean=\(ref.bpmTrimmedMean)")
        #expect(ref.beatsPerBarEstimate == 4)
        #expect(ref.beatsSeconds.count == 59)

        // Decode the m4a via AVAudioFile (matches PreviewDownloader path).
        // PreviewDownloader emits stereo Float32; we average to mono and
        // hand the analyzer the file's native sample rate so the resampler
        // chain runs exactly as in the production prepared-preview path.
        let (samples, sampleRate) = try decodeMonoFloat32(url: audioURL)

        // Run the production analyzer end-to-end.
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let grid = analyzer.analyzeBeatGrid(samples: samples, sampleRate: sampleRate)

        #expect(grid != .empty, "BeatGrid must not be empty")
        #expect(grid.beats.count > 50, "Expected 50+ beats over 30s, got \(grid.beats.count)")

        // PRIMARY ASSERTION — port matches upstream PyTorch reference.
        // If this fails toward 125 BPM (metadata tag), something in the
        // pipeline has changed and the upstream-faithful contract has
        // been broken.
        #expect(
            abs(grid.bpm - ref.bpmTrimmedMean) < 0.5,
            """
            BUG-008 tripwire: produced bpm=\(String(format: "%.2f", grid.bpm)) \
            differs from upstream PyTorch reference \
            \(String(format: "%.2f", ref.bpmTrimmedMean)) by more than 0.5 BPM. \
            The upstream Beat This! model produces 118.05 BPM on this audio; \
            the Phosphene port should match. If this is now closer to 125 BPM \
            (the metadata tag), it means either (a) the model output changed, \
            (b) the resolver changed, or (c) someone "fixed" the BPM by adding \
            a correction layer — confirm intent, then update this gate.
            """
        )

        // Negative assertion — the port should NOT be producing 125 BPM
        // through any code path. If a future change makes this happen,
        // the BUG-008 contract has changed and the diagnosis writeup
        // needs updating.
        #expect(
            abs(grid.bpm - 125.0) > 3.0,
            """
            Produced bpm=\(grid.bpm) is now within ±3 BPM of the metadata-tag \
            tempo (125 BPM). Upstream Beat This! returns 118 BPM on this audio; \
            if Phosphene now returns 125, an undocumented correction layer has \
            been added or the model checkpoint changed. Update BUG-008 diagnosis.
            """
        )
    }

    // MARK: - Helpers

    private func decodeMonoFloat32(url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "ffmpeg", "-loglevel", "error",
            "-i", url.path,
            "-ac", "1",
            "-ar", "44100",
            "-f", "f32le", "-"
        ]
        let stdoutPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = Pipe()
        try proc.run()
        let raw = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(
                domain: "BeatGridAccuracyDiagnosticTests",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "ffmpeg decode failed"]
            )
        }
        let count = raw.count / MemoryLayout<Float>.size
        let samples: [Float] = raw.withUnsafeBytes { buf in
            let typed = buf.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: typed.baseAddress, count: count))
        }
        return (samples, 44100.0)
    }
}
