// RayMarchPathHarnessTemplate — reference multi-frame harness for the `ray_march`
// paradigm (QG.4, Task 3). Copy-adapt this for any new ray-march preset.
//
// Dispatch path exercised (the live `RayMarchPipeline.render` seam, BUG-034 parity —
// the live 128-step budget via `sceneParamsB.z` default 1.0): G-buffer → lighting →
// composite, then the post-process chain when the preset declares `post_process`.
//
//   subject: Lumen Mosaic  —  ray_march + post_process + the 4-light CPU follower
//                             (LumenPatternEngine → slot 8; a real palette is loaded
//                             so cells are non-black, BUG-016)
//
// A plain SDF ray-march preset with no follower drops the `LumenPatternEngine` /
// palette / `presetFragmentBuffer3` lines — the G-buffer→lighting→composite spine is
// identical. The `accumulation window` clause of Task 3 applies only when the subject
// also carries mv_warp (per-vertex feedback); Lumen Mosaic does not, so it is N/A here.
//
// Metric: the composite is non-degenerate at silence (non-constant + a real luma
// floor, not BUG-016 black) and its 64-bit dHash matches a golden. Un-binding slot 8
// (the pattern follower) blacks the cells → the golden trips (A/B validated in QG.4).
//
// GPU test — env-gated `HARNESS_TEMPLATES=1`, NOT in the default parallel run.

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - RayMarchPathHarnessTemplate

@Suite("Ray-march path harness template (env-gated, QG.4)")
@MainActor
struct RayMarchPathHarnessTemplate {

    private static let width = 256
    private static let height = 256
    private static let frameCount = 60
    private static let subjectName = "Lumen Mosaic"

    /// Golden dHash of the composite on the last silence frame. 0 ⇒ bootstrap.
    /// Hardware-specific (D-039): Apple Silicon, macOS 14+.
    private static let goldenCompositeHash: UInt64 = 0xF5F6657349699CC4

    @Test("ray-march dispatch (G-buffer → lighting → composite) non-degenerate + golden")
    func rayMarchPath_nonDegenerate() throws {
        guard HarnessTemplateCore.isEnabled else {
            print("RayMarchPathHarnessTemplate: HARNESS_TEMPLATES not set, skipping")
            return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == Self.subjectName }) else {
            throw HarnessError.presetNotFound(Self.subjectName)
        }
        guard let gbufferState = preset.rayMarchPipelineState else {
            throw HarnessError.setupFailed("\(Self.subjectName) rayMarchPipelineState missing")
        }

        // ── Live ray-march pipeline (BUG-034 production-parity) ──
        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        pipeline.allocateTextures(width: Self.width, height: Self.height)
        var scene = preset.descriptor.makeSceneUniforms()
        scene.sceneParamsA.y = Float(Self.width) / Float(Self.height)
        pipeline.sceneUniforms = scene
        pipeline.ssgiEnabled = preset.descriptor.passes.contains(.ssgi)

        let ibl = try IBLManager(context: ctx, shaderLibrary: lib)
        let noise = try? TextureManager(context: ctx, shaderLibrary: lib)
        let postChain: PostProcessChain?
        if preset.descriptor.passes.contains(.postProcess) {
            let chain = try PostProcessChain(context: ctx, shaderLibrary: lib)
            chain.allocateTextures(width: Self.width, height: Self.height)
            postChain = chain
        } else {
            postChain = nil
        }

        // Lumen's 4-light follower → slot 8. A real palette (else BUG-016 black cells).
        guard let engine = LumenPatternEngine(device: ctx.device) else {
            throw HarnessError.setupFailed("LumenPatternEngine allocation")
        }
        engine.setPalette(LumenMosaicPaletteLibrary.all[0])

        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        let outTex = try HarnessTemplateCore.makeCaptureTexture(ctx, width: Self.width, height: Self.height)

        var lastPixels = [UInt8]()
        for i in 0..<Self.frameCount {
            var features = HarnessTemplateCore.silenceFeature(frame: i)
            engine.tick(features: features, stems: .zero)
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw HarnessError.commandBufferFailed }
            pipeline.render(
                gbufferPipelineState: gbufferState,
                features: &features,
                fftBuffer: buffers.fft, waveformBuffer: buffers.waveform,
                stemFeatures: .zero,
                outputTexture: outTex,
                commandBuffer: cmd,
                noiseTextures: noise,
                iblManager: ibl,
                postProcessChain: postChain,
                presetFragmentBuffer3: engine.patternBuffer)
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw HarnessError.renderFailed }
            if i == Self.frameCount - 1 {
                lastPixels = HarnessTemplateCore.readBGRA(outTex, width: Self.width, height: Self.height)
            }
        }

        #expect(HarnessTemplateCore.isNonConstant(lastPixels), "ray-march composite is constant (degenerate) at silence")
        #expect(HarnessTemplateCore.maxLuma(lastPixels) > 0.02,
                "ray-march composite has no luma floor — cells rendered black (BUG-016 class), harness not reaching the real render")
        let hash = HarnessTemplateCore.dHash(lastPixels, width: Self.width, height: Self.height)

        print(String(format: "[raymarch-template] %@: composite dHash 0x%016llX | meanLuma %.4f maxLuma %.4f",
                     Self.subjectName, hash, HarnessTemplateCore.meanLuma(lastPixels), HarnessTemplateCore.maxLuma(lastPixels)))

        if Self.goldenCompositeHash == 0 {
            print("[raymarch-template] bootstrap — no golden set; paste 0x\(String(hash, radix: 16, uppercase: true))")
            return
        }
        let hd = HarnessTemplateCore.hamming(hash, Self.goldenCompositeHash)
        #expect(hd <= 8, """
            ray-march composite hash drifted \(hd) bits from golden — a mis-bound slot (e.g. the \
            slot-8 follower) or a broken G-buffer→lighting→composite walk. \
            got=0x\(String(hash, radix: 16, uppercase: true)) golden=0x\(String(Self.goldenCompositeHash, radix: 16, uppercase: true))
            """)
    }
}
