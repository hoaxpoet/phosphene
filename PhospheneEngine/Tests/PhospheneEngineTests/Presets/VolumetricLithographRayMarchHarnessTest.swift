// VolumetricLithographRayMarchHarnessTest — VL's multi-frame ray-march harness
// (VL rebuild increment arc step 1; PRESET_SESSION_CHECKLIST Part 2 obligation 1:
// "write or extend the multi-frame harness FIRST"). VL has never had one.
//
// Copy-adapted from `RayMarchPathHarnessTemplate` (D-182) with the Lumen-specific
// slot-8 pattern follower dropped — VL is a plain SDF ray-march + post_process with
// no CPU follower, which is the template's documented degenerate case.
//
// Dispatch path exercised (the live `RayMarchPipeline.render` seam, BUG-034 parity):
// G-buffer → lighting → composite → post-process chain.
//
// Metric: the composite is non-degenerate at silence (non-constant + a real luma
// floor — D-037 "silence never renders black") and its 64-bit dHash matches a golden,
// so a macro-warp / camera / palette change that silently breaks the render trips here
// before it reaches a tuning commit.
//
// GPU test — env-gated `HARNESS_TEMPLATES=1`, NOT in the default parallel run.

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - VolumetricLithographRayMarchHarnessTest

@Suite("Volumetric Lithograph ray-march path harness (env-gated)")
@MainActor
struct VolumetricLithographRayMarchHarnessTest {

    private static let width = 256
    private static let height = 256
    private static let frameCount = 60
    private static let subjectName = "Volumetric Lithograph"

    /// Golden dHash of the composite on the last silence frame. 0 ⇒ bootstrap.
    /// Hardware-specific (D-039): Apple Silicon, macOS 14+.
    private static let goldenCompositeHash: UInt64 = 0x13CFC77D5EB3A349

    @Test("VL ray-march dispatch (G-buffer → lighting → composite → post) non-degenerate + golden")
    func rayMarchPath_nonDegenerate() throws {
        guard HarnessTemplateCore.isEnabled else {
            print("VolumetricLithographRayMarchHarnessTest: HARNESS_TEMPLATES not set, skipping")
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

        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        let outTex = try HarnessTemplateCore.makeCaptureTexture(ctx, width: Self.width, height: Self.height)

        var firstPixels = [UInt8]()
        var lastPixels = [UInt8]()
        for i in 0..<Self.frameCount {
            var features = HarnessTemplateCore.silenceFeature(frame: i)
            // Live parity: `RenderPipeline+RayMarch.swift:114` rewrites the terrain/camera
            // phase axis every frame. VL's whole world is driven off it, so a harness that
            // sets sceneUniforms once renders 60 identical frames.
            pipeline.sceneUniforms.sceneParamsA.x = features.accumulatedAudioTime
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
                postProcessChain: postChain)
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw HarnessError.renderFailed }
            if i == 0 {
                firstPixels = HarnessTemplateCore.readBGRA(outTex, width: Self.width, height: Self.height)
            }
            if i == Self.frameCount - 1 {
                lastPixels = HarnessTemplateCore.readBGRA(outTex, width: Self.width, height: Self.height)
            }
        }

        #expect(HarnessTemplateCore.isNonConstant(lastPixels), "VL composite is constant (degenerate) at silence")
        #expect(HarnessTemplateCore.maxLuma(lastPixels) > 0.02,
                "VL composite has no luma floor — rendered black (D-037 violation / BUG-016 class), harness not reaching the real render")
        let hash = HarnessTemplateCore.dHash(lastPixels, width: Self.width, height: Self.height)

        // Diagnostic, not an assertion: frame-0 → frame-59 Hamming distance is the
        // "does the world move over the window" signal the macro-warp increment needs.
        // 0 at silence today because `accumulatedAudioTime` is energy-gated
        // (`RenderPipeline.swift:514`) — see the design doc §4 silence state.
        let firstHash = HarnessTemplateCore.dHash(firstPixels, width: Self.width, height: Self.height)
        print(String(format: "[vl-harness] %@: composite dHash 0x%016llX | meanLuma %.4f maxLuma %.4f | frame0→%d drift %d bits",
                     Self.subjectName, hash, HarnessTemplateCore.meanLuma(lastPixels), HarnessTemplateCore.maxLuma(lastPixels),
                     Self.frameCount - 1, HarnessTemplateCore.hamming(firstHash, hash)))

        if Self.goldenCompositeHash == 0 {
            print("[vl-harness] bootstrap — no golden set; paste 0x\(String(hash, radix: 16, uppercase: true))")
            return
        }
        let hd = HarnessTemplateCore.hamming(hash, Self.goldenCompositeHash)
        #expect(hd <= 8, """
            VL composite hash drifted \(hd) bits from golden — a broken \
            G-buffer→lighting→composite walk or an unintended scene/camera change. \
            got=0x\(String(hash, radix: 16, uppercase: true)) golden=0x\(String(Self.goldenCompositeHash, radix: 16, uppercase: true))
            """)
    }
}
