// RenderLoopPerformanceTests — XCTest.measure benchmark for a single render frame.
// Uses XCTest for measure {} blocks (Swift Testing lacks built-in benchmarking).

import XCTest
import Metal
@testable import Audio
@testable import Shared
@testable import Renderer

final class RenderLoopPerformanceTests: XCTestCase {

    private var device: MTLDevice!

    override func setUpWithError() throws {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        device = dev
    }

    /// Benchmark: One full render frame (encode + commit + waitUntilCompleted).
    /// Expected < 8ms on M-series Apple Silicon for 120fps budget.
    func test_renderOneFrame_performance() throws {
        let context = try MetalContext()
        let shaderLibrary = try ShaderLibrary(context: context)

        // Create stub audio buffers with test data.
        let fftProcessor = try FFTProcessor(device: device)
        let audioBuffer = try AudioBuffer(device: device)

        let mono = AudioFixtures.sineWave(frequency: 440, sampleRate: 48000, duration: 0.1)
        let stereo = AudioFixtures.mixStereo(left: mono, right: mono)
        stereo.withUnsafeBufferPointer { ptr in
            _ = audioBuffer.write(from: ptr.baseAddress!, count: ptr.count)
        }
        let latest = audioBuffer.latestSamples(count: FFTProcessor.fftSize * 2)
        fftProcessor.processStereo(interleavedSamples: latest, sampleRate: 48000)

        let pipelineState = try shaderLibrary.renderPipelineState(
            named: "waveform",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "waveform_fragment",
            pixelFormat: context.pixelFormat,
            device: device
        )

        // Create offscreen render target (1080p).
        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat, width: 1920, height: 1080, mipmapped: false)
        textureDesc.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: textureDesc) else {
            throw RenderPerfError.metalSetupFailed
        }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store

        var features = FeatureVector(bass: 0.5, mid: 0.3, treble: 0.2, time: 1.0, deltaTime: 0.016)

        measure {
            guard let cmdBuf = context.commandQueue.makeCommandBuffer(),
                  let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return }

            encoder.setRenderPipelineState(pipelineState)
            encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
            encoder.setFragmentBuffer(fftProcessor.magnitudeBuffer.buffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(audioBuffer.metalBuffer, offset: 0, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()

            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()

            features.time += 0.016
        }
    }
}

private enum RenderPerfError: Error {
    case metalSetupFailed
}
