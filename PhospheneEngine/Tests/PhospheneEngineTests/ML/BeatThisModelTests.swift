// BeatThisModelTests — Shape, finiteness, and weight-loading tests for BeatThisModel.

import Testing
import Metal
import Foundation
@testable import DSP
@testable import ML

@Suite struct BeatThisModelTests {

    // MARK: - 1. Graph Build

    @Test func test_graphBuilds() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        _ = try BeatThisModel(device: device)
    }

    // MARK: - 2. Input Projection Shape

    @Test func test_inputProjectionShape() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let model = try BeatThisModel(device: device)
        let frameCount = 10
        let input = [Float](repeating: 0, count: frameCount * BeatThisModel.inputMels)
        let result = try model.predictIncludingFrontendOutput(
            spectrogram: input,
            frameCount: frameCount
        )
        #expect(result.frontendShape == [10, BeatThisModel.embedDim])
    }

    // MARK: - 3. Output Shape T=10

    @Test func test_outputShape_T10() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let model = try BeatThisModel(device: device)
        let frameCount = 10
        let input = [Float](repeating: 0, count: frameCount * BeatThisModel.inputMels)
        let (beats, downbeats) = try model.predict(spectrogram: input, frameCount: frameCount)
        #expect(beats.count == frameCount)
        #expect(downbeats.count == frameCount)
    }

    // MARK: - 4. Output Shape T=1497

    @Test func test_outputShape_T1497() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let model = try BeatThisModel(device: device)
        let frameCount = 1497
        let input = [Float](repeating: 0, count: frameCount * BeatThisModel.inputMels)
        let (beats, downbeats) = try model.predict(spectrogram: input, frameCount: frameCount)
        #expect(beats.count == frameCount)
        #expect(downbeats.count == frameCount)
    }

    // MARK: - 5. Output Range Is Finite

    @Test func test_outputRangeIsFinite() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let model = try BeatThisModel(device: device)
        let frameCount = 100
        var input = [Float](repeating: 0, count: frameCount * BeatThisModel.inputMels)
        for i in 0..<input.count { input[i] = Float(i % 13) * 0.03 }
        let (beats, downbeats) = try model.predict(spectrogram: input, frameCount: frameCount)
        #expect(beats.allSatisfy { $0.isFinite }, "beats contain NaN/Inf")
        #expect(downbeats.allSatisfy { $0.isFinite }, "downbeats contain NaN/Inf")
    }

    // MARK: - 6. Weight Loading Succeeds

    @Test func test_weightsLoad_noThrow() throws {
        #expect(throws: Never.self) {
            _ = try BeatThisModel.loadWeights()
        }
    }

    // MARK: - 7. Output Differs From Zero-Init

    /// With real weights, a non-trivial spectrogram should produce non-uniform beat activations.
    @Test func test_outputNonUniform_withRealWeights() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let model = try BeatThisModel(device: device)
        let frameCount = 50
        var input = [Float](repeating: 0, count: frameCount * BeatThisModel.inputMels)
        for i in 0..<input.count { input[i] = Float(i % 17) * 0.05 }
        let (beats, _) = try model.predict(spectrogram: input, frameCount: frameCount)
        let allSame = beats.dropFirst().allSatisfy { abs($0 - beats[0]) < 1e-6 }
        #expect(!allSame, "beats are all identical — model may be zero-init or degenerate")
    }

    // MARK: - 8. Inference Time Under 300ms

    @Test func test_inferenceTime_under300ms() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let model = try BeatThisModel(device: device)
        let frameCount = BeatThisModel.tMax
        let input = [Float](repeating: 0.1, count: frameCount * BeatThisModel.inputMels)
        // Warm-up call (JIT compilation)
        _ = try model.predict(spectrogram: input, frameCount: frameCount)
        // Measured call
        let start = Date()
        _ = try model.predict(spectrogram: input, frameCount: frameCount)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.3, "Inference took \(String(format: "%.1f", elapsed * 1000))ms — expected < 300ms")
    }

    // MARK: - 9. End-to-End: Real Audio → Real Beats (KNOWN-FAILING)

    /// End-to-end gate: feed `love_rehab.m4a` through preprocessor + model and
    /// assert the output is a usable BeatGrid signal — peaks above 0.5
    /// threshold at roughly the rate of musical beats. The Python Beat This!
    /// reference produces max(sigmoid)=1.0 with ~120 frames > 0.5 over 30s of
    /// 4/4 music. Our Swift port currently produces max ≈ 0.29 with 0 frames
    /// > 0.5 — visibly compressed and sub-threshold. This is a real model bug
    /// (likely in the frontend partial-FT block weight load, RoPE indexing,
    /// or BN fusion) that surfaced when QualityReelAnalyzer first exercised
    /// the full pipeline against ground-truth fixtures (2026-05-04).
    ///
    /// Wrapped in `withKnownIssue` so it stays in CI without breaking the
    /// suite, while ensuring the failure is visible. Remove the wrapper once
    /// the model bug is fixed — that's the "S7 actually engaged in
    /// production" milestone.
    @Test func test_loveRehab_endToEnd_producesBeats() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let testDir = URL(fileURLWithPath: String(#filePath)).deletingLastPathComponent()
        let audioURL = testDir
            .deletingLastPathComponent()  // PhospheneEngineTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures/tempo/love_rehab.m4a")
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("BeatThisModelTests: skipping endToEnd_producesBeats (audio fixture absent)")
            return
        }
        let samples = try decodeMono22050(url: audioURL)

        let pre = BeatThisPreprocessor()
        let (spect, frameCount) = pre.process(samples: samples, inputSampleRate: 22050)
        let model = try BeatThisModel(device: device)
        let (beats, _) = try model.predict(spectrogram: spect, frameCount: frameCount)
        let maxProb = beats.max() ?? 0
        let aboveHalf = beats.filter { $0 > 0.5 }.count

        // What we WANT (Python reference: max ≈ 1.0, ~120 frames > 0.5).
        // What we GET today: max ≈ 0.29, 0 frames > 0.5 → BeatGridResolver
        // produces an empty grid → S7's drift tracker stays dormant.
        withKnownIssue("BeatThisModel produces sub-threshold output on real audio (DSP.2 followup)") {
            #expect(maxProb > 0.9,
                    "max sigmoid should be near 1.0 at strong beats; got \(maxProb)")
            #expect(aboveHalf >= 50,
                    "expected ≥50 frames above 0.5 in 30s of 4/4 music; got \(aboveHalf)")
        }
    }

    // MARK: - Helpers

    private func decodeMono22050(url: URL) throws -> [Float] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "ffmpeg", "-loglevel", "error",
            "-i", url.path,
            "-ac", "1", "-ar", "22050",
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
                domain: "BeatThisModelTests",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "ffmpeg decode failed"]
            )
        }
        let count = raw.count / MemoryLayout<Float>.size
        return raw.withUnsafeBytes { buf in
            let typed = buf.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: typed.baseAddress, count: count))
        }
    }
}
