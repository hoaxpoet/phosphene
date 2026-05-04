// BeatThisModelTests — Shape and finiteness tests for BeatThisModel (DSP.2 S3).

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
}
