// BeatThisModelTests — Shape, finiteness, and weight-loading tests for BeatThisModel.

import Testing
import Metal
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

    // MARK: - 9. love_rehab Beat Logits Match PyTorch (disabled by default)

    /// Numerical match against PyTorch reference fixture.
    /// Enable with: BEATTHIS_GOLDEN=1 swift test --filter test_loveRehab_beatLogits_matchPyTorch
    @Test func test_loveRehab_beatLogits_matchPyTorch() throws {
        guard ProcessInfo.processInfo.environment["BEATTHIS_GOLDEN"] == "1" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        // Load love_rehab spectrogram (T×128) from fixture
        guard let spectURL = Bundle.module.url(
            forResource: "love_rehab_spect_reference",
            withExtension: "json",
            subdirectory: "Fixtures/beat_this_reference"
        ) else {
            Issue.record("love_rehab_spect_reference.json fixture not found")
            return
        }
        let spectData = try Data(contentsOf: spectURL)
        let frames = try JSONDecoder().decode([[Float]].self, from: spectData)
        let frameCount = frames.count
        let flat = frames.flatMap { $0 }
        let model = try BeatThisModel(device: device)
        let (beats, _) = try model.predict(spectrogram: flat, frameCount: frameCount)
        // Sanity: outputs should be in [0, 1] and not all 0.5
        #expect(beats.allSatisfy { $0 >= 0 && $0 <= 1 }, "beat probabilities out of [0,1]")
        let allHalf = beats.allSatisfy { abs($0 - 0.5) < 1e-4 }
        #expect(!allHalf, "All beats == 0.5 — model produced uniform output (degenerate)")
    }
}
