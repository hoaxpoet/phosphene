// FeedbackPathHarnessTemplate — reference multi-frame harness for the `feedback`
// paradigm (QG.4, Task 4). Copy-adapt this for any new surface-mode feedback preset.
//
// Dispatch path exercised (the surface-mode half of `RenderPipeline.drawWithFeedback`,
// minus the drawable blit): warp the previous accumulator into the current texture with
// decay (the PRODUCTION `runWarpPass`), composite the preset additively onto it, then
// swap the ping-pong. Real swap-chain semantics — each frame's accumulator becomes the
// next frame's source; no per-frame clear. 60 frames covers the decay window.
//
//   subject: Membrane  —  passes: [feedback]; decay 0.90; the only pure surface-mode
//                         feedback preset (particle-mode feedback presets never sample
//                         the accumulator — CLEAN.4.4 — so they are not the paradigm here)
//
// Metric: the accumulator neither saturates nor decays to zero at silence — the D-037
// non-black floor is the lower bound. Breaking the swap (source == target) saturates the
// loop and trips the upper bound; killing the compose decays it to the floor and trips
// the lower bound (A/B validated in QG.4). A golden dHash pins the steady state.
//
// GPU test — env-gated `HARNESS_TEMPLATES=1`, NOT in the default parallel run.

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - FeedbackPathHarnessTemplate

@Suite("Feedback path harness template (env-gated, QG.4)")
@MainActor
struct FeedbackPathHarnessTemplate {

    private static let width = 256
    private static let height = 256
    private static let frameCount = 60
    private static let subjectName = "Membrane"

    /// Golden dHash of the steady-state accumulator on the last silence frame. 0 ⇒
    /// bootstrap. Hardware-specific (D-039): Apple Silicon, macOS 14+.
    private static let goldenAccumulatorHash: UInt64 = 0x32E3A918C1646939

    @Test("feedback dispatch (warp → composite → swap) holds a bounded non-black accumulator")
    func feedbackPath_boundedAccumulator() throws {
        guard HarnessTemplateCore.isEnabled else {
            print("FeedbackPathHarnessTemplate: HARNESS_TEMPLATES not set, skipping")
            return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == Self.subjectName }) else {
            throw HarnessError.presetNotFound(Self.subjectName)
        }
        guard let composePipeline = preset.feedbackPipelineState else {
            throw HarnessError.setupFailed("\(Self.subjectName) feedbackPipelineState (compose) missing")
        }
        let desc = preset.descriptor

        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib,
                                          fftBuffer: buffers.fft, waveformBuffer: buffers.waveform)
        var params = FeedbackParams(
            decay: desc.decay, baseZoom: desc.baseZoom, baseRot: desc.baseRot,
            beatZoom: desc.beatZoom, beatRot: desc.beatRot, beatSensitivity: desc.beatSensitivity)

        // Two-texture ping-pong (the production feedback accumulator). Cleared to black.
        let texA = try HarnessTemplateCore.makeCaptureTexture(ctx, width: Self.width, height: Self.height)
        let texB = try HarnessTemplateCore.makeCaptureTexture(ctx, width: Self.width, height: Self.height)
        try HarnessTemplateCore.clear([texA, texB], ctx)
        let textures = [texA, texB]
        var idx = 0

        var finalPixels = [UInt8]()
        for i in 0..<Self.frameCount {
            var features = HarnessTemplateCore.silenceFeature(frame: i)
            let cur = textures[idx]
            let prev = textures[1 - idx]
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw HarnessError.commandBufferFailed }
            // Pass 1: warp previous → current (decay). Production seam.
            pipeline.runWarpPass(commandBuffer: cmd, features: &features, params: &params,
                                 target: cur, source: prev)
            // Pass 2: composite the preset additively onto the warped accumulator.
            try encodeCompose(cmd: cmd, composePipeline: composePipeline, target: cur,
                              features: &features, buffers: buffers)
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw HarnessError.renderFailed }
            if i == Self.frameCount - 1 {
                finalPixels = HarnessTemplateCore.readBGRA(cur, width: Self.width, height: Self.height)
            }
            idx = 1 - idx   // swap
        }

        let mean = HarnessTemplateCore.meanLuma(finalPixels)
        let peak = HarnessTemplateCore.maxLuma(finalPixels)
        print(String(format: "[feedback-template] %@: accumulator meanLuma %.4f maxLuma %.4f (decay %.2f)",
                     Self.subjectName, mean, peak, desc.decay))

        #expect(mean > 0.004,
                "feedback accumulator decayed to black (mean \(String(format: "%.4f", mean))) — below the D-037 non-black floor")
        #expect(mean < 0.90,
                "feedback accumulator saturated (mean \(String(format: "%.4f", mean))) — the decay/swap is broken")
        #expect(HarnessTemplateCore.isNonConstant(finalPixels),
                "feedback accumulator is a constant field (degenerate) at silence")

        let hash = HarnessTemplateCore.dHash(finalPixels, width: Self.width, height: Self.height)
        if Self.goldenAccumulatorHash == 0 {
            print("[feedback-template] bootstrap — no golden set; paste 0x\(String(hash, radix: 16, uppercase: true))")
            return
        }
        let hd = HarnessTemplateCore.hamming(hash, Self.goldenAccumulatorHash)
        #expect(hd <= 8, """
            feedback accumulator hash drifted \(hd) bits from golden — a broken warp/compose/swap. \
            got=0x\(String(hash, radix: 16, uppercase: true)) golden=0x\(String(Self.goldenAccumulatorHash, radix: 16, uppercase: true))
            """)
    }

    /// Surface-mode composite: the preset fragment blended additively onto the warped
    /// accumulator (mirrors `drawSurfaceMode`'s compose encoder; the additive blend is
    /// baked into `composePipeline`). Silence buffers stand in for the live audio bindings.
    private func encodeCompose(
        cmd: MTLCommandBuffer,
        composePipeline: MTLRenderPipelineState,
        target: MTLTexture,
        features: inout FeatureVector,
        buffers: HarnessTemplateCore.SilenceBuffers
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .load    // composite onto the warped accumulator
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else {
            throw HarnessError.encoderCreationFailed
        }
        enc.setRenderPipelineState(composePipeline)
        enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        enc.setFragmentBuffer(buffers.fft, offset: 0, index: 1)
        enc.setFragmentBuffer(buffers.waveform, offset: 0, index: 2)
        var stems = StemFeatures.zero
        enc.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.size, index: 3)
        enc.setFragmentBuffer(buffers.history, offset: 0, index: 5)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }
}
