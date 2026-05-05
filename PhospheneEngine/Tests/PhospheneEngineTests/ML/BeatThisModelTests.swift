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

    // MARK: - 9. End-to-End: Real Audio → Real Beats

    /// End-to-end gate: feed `love_rehab.m4a` through preprocessor + model and
    /// assert the output is a usable BeatGrid signal — peaks above 0.5
    /// threshold at roughly the rate of musical beats.
    ///
    /// Python Beat This! reference: max(sigmoid)=0.9999, 124 frames > 0.5.
    /// Swift output after DSP.2 S8 fixes (norm-after-conv with correct out_dim
    /// shape, transpose-before-reshape on stem input, BN1d-aware padding,
    /// paired-adjacent RoPE in both 4D frontend attention and 3D transformer
    /// attention): max=0.9999, 126 frames > 0.5. Passes unconditionally.
    ///
    /// Tight thresholds (> 0.99, ≥ 100) catch any regression back toward the
    /// pre-fix values (max ≈ 0.29, 0 frames > 0.5). A 1% margin on max and
    /// 20% margin on count accommodate float32 jitter without hiding real bugs.
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

        // Python reference: max=0.9999, 124 frames > 0.5.
        // Swift post-S8: max=0.9999, 126 frames > 0.5.
        // Tight bounds catch any regression toward the pre-S8 values (max≈0.29, 0 frames>0.5).
        #expect(maxProb > 0.99,
                "max sigmoid should be ≥0.99 (Python ref 0.9999); got \(maxProb). Pre-S8 was ≈0.29.")
        #expect(aboveHalf >= 100,
                "expected ≥100 frames >0.5 in 30s 4/4 music (Python ref 124); got \(aboveHalf).")
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
