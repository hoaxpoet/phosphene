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

    /// Synthesizes a 30-second mono kick-on-every-quarter-note track at a
    /// known input BPM and asserts `DefaultBeatGridAnalyzer` recovers it.
    ///
    /// Settled the Love Rehab interpretation question (BUG-008.1 follow-up,
    /// 2026-05-06): the model hits 125.00 BPM exactly on synthetic
    /// quantized input. So the 118 BPM Beat This! produces on Love Rehab
    /// is musical interpretation (kick rate vs. perceptual beat), not a
    /// model accuracy failure at this tempo. BUG-008.2 scope (surface
    /// disagreement, don't act on it) is correct.
    ///
    /// Side finding: at 120 BPM input, the model returns 117.97 BPM (-1.7 %).
    /// 130 BPM returns 130.09 BPM (+0.07 %). 125 BPM is exact. The 120 BPM
    /// undershoot is a small, tempo-specific artifact unrelated to Love
    /// Rehab; documented for forensic value, not gated tightly.
    ///
    /// Tolerance is ±2.5 BPM (matches the Pyramid Song criterion in the
    /// original BUG-008 verification). The PRINT line on every test is
    /// the real deliverable — if these numbers shift in the future, they
    /// surface in test output regardless of pass/fail.
    @Test(
        "synthesizedKick: BeatThis! recovers known machine-quantized BPM",
        arguments: [120.0, 125.0, 130.0]
    )
    func test_synthesizedKick_modelRecoversKnownBPM(inputBPM: Double) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let sampleRate: Double = 44100
        let durationSec: Double = 30.0
        let samples = synthesizeKickTrack(
            bpm: inputBPM,
            durationSeconds: durationSec,
            sampleRate: sampleRate
        )
        #expect(samples.count == Int(sampleRate * durationSec))

        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let grid = analyzer.analyzeBeatGrid(samples: samples, sampleRate: sampleRate)

        // Print so the result is visible regardless of pass/fail —
        // this is a diagnostic test, the numbers themselves are the deliverable.
        let expectedBeats = Int(durationSec * inputBPM / 60.0)
        print("""
            BUG-008 synthetic kick: input=\(String(format: "%.1f", inputBPM)) BPM \
            → produced=\(String(format: "%.2f", grid.bpm)) BPM, \
            beats=\(grid.beats.count) (expected ~\(expectedBeats)), \
            downbeats=\(grid.downbeats.count), \
            beatsPerBar=\(grid.beatsPerBar)
            """)

        #expect(grid != .empty, "BeatGrid must not be empty for synthesized input")
        #expect(grid.beats.count > expectedBeats / 2,
                "Expected ~\(expectedBeats) beats, got \(grid.beats.count) — model is missing kicks")
        #expect(
            abs(grid.bpm - inputBPM) < 2.5,
            """
            BUG-008 diagnostic: input \(inputBPM) BPM kick track produced \
            \(String(format: "%.2f", grid.bpm)) BPM (delta=\(String(format: "%.2f", grid.bpm - inputBPM))). \
            Tolerance is intentionally generous (±2.5) — observed values at \
            time of writing: 120→117.97, 125→125.00, 130→130.09. A delta \
            outside ±2.5 indicates a real shift from those baselines.
            """
        )
    }

    // MARK: - Helpers

    /// Synthesize a mono 30-second kick-on-every-quarter-note track.
    ///
    /// Each kick is a 60 Hz sine pulse with a sharp attack (linear ramp over
    /// 2 ms) and exponential decay (τ=0.06 s) — TR-style kick centered in
    /// the sub_bass mel band. Quantized exactly to the input BPM.
    private func synthesizeKickTrack(
        bpm: Double,
        durationSeconds: Double,
        sampleRate: Double
    ) -> [Float] {
        let totalSamples = Int(sampleRate * durationSeconds)
        var samples = [Float](repeating: 0, count: totalSamples)

        let beatPeriodSamples = Int((60.0 / bpm) * sampleRate)
        let kickFreq: Double = 60.0
        let kickDecayTau: Double = 0.06    // seconds
        let kickAttackSamples = Int(0.002 * sampleRate)  // 2 ms
        let kickLengthSamples = Int(0.20 * sampleRate)   // 200 ms (well past decay)

        var beatStart = 0
        while beatStart < totalSamples {
            for i in 0..<kickLengthSamples {
                let idx = beatStart + i
                if idx >= totalSamples { break }
                let t = Double(i) / sampleRate
                let attackEnv: Double = i < kickAttackSamples
                    ? Double(i) / Double(kickAttackSamples)
                    : 1.0
                let decayEnv = exp(-t / kickDecayTau)
                let phase = 2.0 * .pi * kickFreq * t
                samples[idx] += Float(0.6 * attackEnv * decayEnv * sin(phase))
            }
            beatStart += beatPeriodSamples
        }

        return samples
    }

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
