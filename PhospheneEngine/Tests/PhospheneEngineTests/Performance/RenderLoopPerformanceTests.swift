// RenderLoopPerformanceTests — XCTest.measure benchmark for a single render frame.
// Uses XCTest for measure {} blocks (Swift Testing lacks built-in benchmarking).

import XCTest
import Metal
@testable import Audio
@testable import Shared
@testable import Renderer
@testable import Presets

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

    // MARK: - Truchet Loom (PG.4.1) — per-frame percentiles at 1080p

    /// Renders the Truchet Loom direct fragment at 1080p across silence / steady /
    /// beat-heavy inputs and records p50/p95/p99 per-frame ms. The bounded
    /// subdivision recursion (depth cap 3) should keep the cost flat across inputs
    /// — a busy frame subdivides but does not deepen the loop. Tier-2 direct budget
    /// is well under the 8 ms 120 fps line.
    func test_truchetLoom_percentiles() throws {
        let context = try MetalContext()
        let loader = PresetLoader(device: context.device, pixelFormat: context.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Truchet Loom" }) else {
            XCTFail("Truchet Loom preset not loaded"); return
        }

        let width = 1920, height = 1080
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat, width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: texDesc) else { throw RenderPerfError.metalSetupFailed }

        let fs = MemoryLayout<Float>.stride
        guard let fft = context.makeSharedBuffer(length: 512 * fs),
              let wav = context.makeSharedBuffer(length: 2048 * fs) else { throw RenderPerfError.metalSetupFailed }
        _ = fft.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 512 * fs)
        _ = wav.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 2048 * fs)

        // Populate SpectralHistory to three flux levels so the recursion actually
        // exercises depth 0 (silence) through depth ~3 (beat-heavy busy).
        func history(flux: Float) -> SpectralHistoryBuffer {
            let h = SpectralHistoryBuffer(device: context.device)
            var fv = FeatureVector.zero; fv.spectralFlux = flux; fv.deltaTime = 1.0 / 60.0
            for _ in 0..<180 { h.append(features: fv, stems: .zero) }
            return h
        }
        let cases: [(name: String, flux: Float, arousal: Float)] = [
            ("silence",    0.0,  0.0),
            ("steady",     0.35, 0.2),
            ("beat-heavy", 0.85, 0.7),
        ]

        for c in cases {
            let hist = history(flux: c.flux)
            var fv = FeatureVector.zero
            fv.arousal = c.arousal
            fv.aspectRatio = Float(width) / Float(height)
            var samples: [Double] = []
            for i in 0..<120 {
                fv.time = Float(i) * (1.0 / 60.0)
                let rpd = MTLRenderPassDescriptor()
                rpd.colorAttachments[0].texture = texture
                rpd.colorAttachments[0].loadAction = .clear
                rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                rpd.colorAttachments[0].storeAction = .store
                let t0 = DispatchTime.now().uptimeNanoseconds
                guard let cmd = context.commandQueue.makeCommandBuffer(),
                      let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { continue }
                enc.setRenderPipelineState(preset.pipelineState)
                enc.setFragmentBytes(&fv, length: MemoryLayout<FeatureVector>.size, index: 0)
                enc.setFragmentBuffer(fft, offset: 0, index: 1)
                enc.setFragmentBuffer(wav, offset: 0, index: 2)
                enc.setFragmentBuffer(hist.gpuBuffer, offset: 0, index: 5)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
                cmd.commit()
                cmd.waitUntilCompleted()
                let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000.0
                if i >= 20 { samples.append(ms) }   // drop warmup
            }
            samples.sort()
            func pct(_ p: Double) -> Double { samples[min(samples.count - 1, Int(p * Double(samples.count)))] }
            let p50 = pct(0.50), p95 = pct(0.95), p99 = pct(0.99)
            print(String(format: "[TruchetLoom perf] %-10@ p50=%.3f ms  p95=%.3f ms  p99=%.3f ms",
                         c.name as NSString, p50, p95, p99))
            XCTAssertLessThan(p95, 8.0, "Truchet Loom \(c.name) p95 \(p95) ms exceeds the 8 ms (120 fps) budget")
        }
    }
}

private enum RenderPerfError: Error {
    case metalSetupFailed
}
