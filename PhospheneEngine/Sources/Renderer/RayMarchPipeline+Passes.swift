// RayMarchPipeline+Passes — Internal render-pass encoders for RayMarchPipeline.
//
// Extracted from RayMarchPipeline.swift for file-length compliance.
// All methods are internal to the Renderer module — callers use `render(...)` on the main type.
//
// Pass order when SSGI is enabled:
//   1. runGBufferPass   — preset SDF → 3 G-buffer targets
//   2. runLightingPass  — G-buffer → litTexture (.rgba16Float), PBR + screen-space shadows + IBL
//   3. runSSGIPass      — G-buffers + litTexture → ssgiTexture (half-res indirect diffuse)
//   4. runSSGIBlendPass — additive upsample of ssgiTexture into litTexture
//   5. runCompositePass — litTexture → outputTexture (ACES SDR, used when no PostProcessChain)

import Metal
import Shared
import os.log

private let passLogger = Logger(subsystem: "com.phosphene.renderer", category: "GBufferPass")

// MARK: - G-buffer Pass

extension RayMarchPipeline {

    // swiftlint:disable function_parameter_count
    // `runGBufferPass` takes 9 parameters — the minimal set for encoding a preset draw call.

    /// Pass 1: Render the preset's SDF scene into the three G-buffer targets.
    ///
    /// Slot 8 (LM.2 / D-LM-buffer-slot-8) and slot 9 (V.9 Session 3 / D-125) are
    /// both bound for every ray-march preset. When `presetFragmentBuffer3` /
    /// `presetFragmentBuffer4` is nil (every preset other than Lumen Mosaic /
    /// Ferrofluid Ocean at the time of writing) the corresponding zero-filled
    /// placeholder (`lumenPlaceholderBuffer` / `stageRigPlaceholderBuffer`) is
    /// bound instead — the preamble's `raymarch_gbuffer_fragment` declares
    /// `[[buffer(8)]]` and `[[buffer(9)]]` and Metal validation requires every
    /// declared buffer to be bound at draw time.
    func runGBufferPass(
        commandBuffer: MTLCommandBuffer,
        gbufferPipelineState: MTLRenderPipelineState,
        features: inout FeatureVector,
        fftBuffer: MTLBuffer,
        waveformBuffer: MTLBuffer,
        stemFeatures: StemFeatures,
        noiseTextures: TextureManager?,
        presetFragmentBuffer3: MTLBuffer? = nil,
        presetFragmentBuffer4: MTLBuffer? = nil,
        presetHeightTexture: MTLTexture? = nil
    ) {
        guard let g0 = gbuffer0, let g1 = gbuffer1, let g2 = gbuffer2 else {
            passLogger.error("runGBufferPass: G-buffer textures nil — skipping")
            return
        }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = g0
        desc.colorAttachments[0].loadAction  = .clear
        desc.colorAttachments[0].clearColor  = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 0)
        desc.colorAttachments[0].storeAction = .store

        desc.colorAttachments[1].texture     = g1
        desc.colorAttachments[1].loadAction  = .clear
        desc.colorAttachments[1].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        desc.colorAttachments[1].storeAction = .store

        desc.colorAttachments[2].texture     = g2
        desc.colorAttachments[2].loadAction  = .clear
        desc.colorAttachments[2].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        desc.colorAttachments[2].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else {
            passLogger.error(
                "runGBufferPass: makeRenderCommandEncoder returned nil — pipeline/attachment format mismatch?"
            )
            return
        }
        encoder.setRenderPipelineState(gbufferPipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        encoder.setFragmentBuffer(fftBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
        var stems = stemFeatures
        encoder.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.stride, index: 3)
        encoder.setFragmentBytes(&sceneUniforms, length: MemoryLayout<SceneUniforms>.stride, index: 4)
        // Slot 8: Lumen Mosaic preset state, or the zero-filled placeholder for
        // every other ray-march preset. Always non-nil so the preamble's
        // `[[buffer(8)]]` parameter is defined.
        let slot8Buffer = presetFragmentBuffer3 ?? lumenPlaceholderBuffer
        encoder.setFragmentBuffer(slot8Buffer, offset: 0, index: 8)
        // Slot 9: §5.8 stage-rig state (V.9 Session 3 / D-125), or the
        // zero-filled placeholder for non-stage-rig presets. Always non-nil
        // so the preamble's `[[buffer(9)]]` parameter is defined.
        let slot9Buffer = presetFragmentBuffer4 ?? stageRigPlaceholderBuffer
        encoder.setFragmentBuffer(slot9Buffer, offset: 0, index: 9)
        noiseTextures?.bindTextures(to: encoder)
        // Texture slot 10: Ferrofluid Ocean's V.9 Session 4.5b baked height
        // field, or a 1×1 zero placeholder for every other ray-march preset.
        // Always non-nil so the preamble's `[[texture(10)]]` declaration is
        // satisfied at Metal validation time.
        let slot10Texture = presetHeightTexture ?? ferrofluidHeightPlaceholderTexture
        encoder.setFragmentTexture(slot10Texture, index: 10)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // swiftlint:enable function_parameter_count
}

// MARK: - Lighting Pass

extension RayMarchPipeline {

    /// Pass 2: Evaluate PBR lighting from G-buffer data → litTexture (.rgba16Float).
    /// IBL textures (Increment 3.16) are bound at slots 9–11 when `iblManager` is non-nil.
    /// `presetFragmentBuffer3` (when non-nil) is bound at fragment slot 8 for presets that
    /// declare per-frame CPU-driven state needed in the lighting fragment (D-LM-buffer-slot-8).
    /// G-buffer pass intentionally does NOT bind slot 8 — only lighting consumes it today.
    ///
    /// Slot 9 (`presetFragmentBuffer4`) is bound on the lighting pass for the §5.8
    /// stage-rig dispatch (V.9 Session 3 / D-125): `raymarch_lighting_fragment`
    /// declares `[[buffer(9)]] constant StageRigState&` and the `matID == 2`
    /// branch loops `for (uint i = 0; i < stageRig.activeLightCount; i++)` to
    /// accumulate Cook-Torrance contributions per active beam. Non-stage-rig
    /// presets pass `nil` and the zero-filled `stageRigPlaceholderBuffer` is
    /// bound (`activeLightCount == 0` ⇒ matID == 2 loop body never executes).
    func runLightingPass(
        commandBuffer: MTLCommandBuffer,
        features: inout FeatureVector,
        noiseTextures: TextureManager?,
        iblManager: IBLManager? = nil,
        presetFragmentBuffer3: MTLBuffer? = nil,
        presetFragmentBuffer4: MTLBuffer? = nil
    ) {
        guard let g0 = gbuffer0, let g1 = gbuffer1, let g2 = gbuffer2,
              let lit = litTexture else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = lit
        desc.colorAttachments[0].loadAction  = .clear
        desc.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(lightingPipeline)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        encoder.setFragmentBytes(&sceneUniforms, length: MemoryLayout<SceneUniforms>.stride, index: 4)
        // Slot 8: Lumen Mosaic preset state, or the zero-filled placeholder for
        // any non-Lumen ray-march preset. Always bound for symmetry with the
        // G-buffer pass — the lighting fragment doesn't currently declare
        // `[[buffer(8)]]`, but binding eagerly keeps slot semantics uniform
        // across both passes (matID == 1 path may grow to read slot 8 in
        // a future LM increment without adding pass-specific binding logic).
        let slot8Buffer = presetFragmentBuffer3 ?? lumenPlaceholderBuffer
        encoder.setFragmentBuffer(slot8Buffer, offset: 0, index: 8)
        // Slot 9: §5.8 stage-rig state (V.9 Session 3 / D-125). Always non-nil
        // because `raymarch_lighting_fragment` declares `[[buffer(9)]]`.
        let slot9Buffer = presetFragmentBuffer4 ?? stageRigPlaceholderBuffer
        encoder.setFragmentBuffer(slot9Buffer, offset: 0, index: 9)
        encoder.setFragmentTexture(g0, index: 0)
        encoder.setFragmentTexture(g1, index: 1)
        encoder.setFragmentTexture(g2, index: 2)
        encoder.setFragmentSamplerState(sampler, index: 0)
        noiseTextures?.bindTextures(to: encoder)
        iblManager?.bindTextures(to: encoder)       // texture(9–11)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

// MARK: - SSGI Passes (Increment 3.17)

extension RayMarchPipeline {

    /// Pass 3 (optional): SSGI accumulation — G-buffers + litTexture → ssgiTexture (half-res).
    ///
    /// Reads depth (gbuffer0 at texture 0), normals (gbuffer1 at texture 1), and direct
    /// lighting (litTexture at texture 2).  Writes half-res indirect diffuse to `ssgiTexture`.
    /// Blue noise (texture 8) is forwarded for sample-pattern dithering when `noiseTextures`
    /// is non-nil.
    func runSSGIPass(
        commandBuffer: MTLCommandBuffer,
        features: inout FeatureVector,
        noiseTextures: TextureManager?
    ) {
        guard let g0 = gbuffer0, let g1 = gbuffer1, let lit = litTexture,
              let ssgi = ssgiTexture else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = ssgi
        desc.colorAttachments[0].loadAction  = .clear
        desc.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        desc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(ssgiPipeline)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        encoder.setFragmentBytes(&sceneUniforms, length: MemoryLayout<SceneUniforms>.stride, index: 4)
        encoder.setFragmentTexture(g0, index: 0)    // depth
        encoder.setFragmentTexture(g1, index: 1)    // normals + AO
        encoder.setFragmentTexture(lit, index: 2)   // direct lighting
        encoder.setFragmentSamplerState(sampler, index: 0)
        // Blue noise at texture(8) for sample-rotation dithering — forwarded from TextureManager.
        noiseTextures?.bindTextures(to: encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Pass 4 (optional): SSGI blend — additive upsample of ssgiTexture into litTexture.
    ///
    /// Uses additive blending (src=one, dst=one) with loadAction=.load so the
    /// existing direct-lighting content in `litTexture` is preserved and the
    /// upsampled indirect diffuse is layered on top.
    func runSSGIBlendPass(commandBuffer: MTLCommandBuffer) {
        guard let ssgi = ssgiTexture, let lit = litTexture else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = lit
        desc.colorAttachments[0].loadAction  = .load   // preserve direct lighting
        desc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(ssgiBlendPipeline)
        encoder.setFragmentTexture(ssgi, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

// MARK: - Depth Debug Pass

extension RayMarchPipeline {

    /// DEBUG: Split-screen depth/albedo bypass — no lighting, SSGI, or ACES.
    /// Left half:  depth map (white=near, dark=far, RED=sky/miss).
    /// Right half: raw unlit albedo from gbuf2.
    func runDepthDebugPass(commandBuffer: MTLCommandBuffer, outputTexture: MTLTexture) {
        guard let g0 = gbuffer0, let g2 = gbuffer2 else {
            passLogger.error("runDepthDebugPass: G-buffer textures nil — skipping")
            return
        }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = outputTexture
        desc.colorAttachments[0].loadAction  = .clear
        desc.colorAttachments[0].clearColor  = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(depthDebugPipeline)
        encoder.setFragmentTexture(g0, index: 0)
        encoder.setFragmentTexture(g2, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

// MARK: - G-buffer Debug Pass

extension RayMarchPipeline {

    /// Debug pass: copy gbuf2 directly to outputTexture without any lighting, SSGI, or ACES.
    ///
    /// Used when `debugGBufferMode == true` (toggled with 'G' key).
    /// Because this bypasses the PBR lighting pass and all post-processing, the raw colours
    /// written by the `#ifdef GBUFFER_DEBUG` quadrant block are preserved:
    ///   TL = green (hit) / red (miss)   — albedo (0,1,0) / (1,0,0)
    ///   TR = SDF sign as green or red
    ///   BL = step count as greyscale
    ///   BR = hit depth as greyscale / red on miss
    func runGBufferDebugPass(commandBuffer: MTLCommandBuffer, outputTexture: MTLTexture) {
        guard let g2 = gbuffer2 else {
            passLogger.error("runGBufferDebugPass: gbuffer2 nil — skipping")
            return
        }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = outputTexture
        desc.colorAttachments[0].loadAction  = .clear
        desc.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(gbufferDebugPipeline)
        encoder.setFragmentTexture(g2, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

// MARK: - Composite Pass

extension RayMarchPipeline {

    /// Pass 5 (fallback, no PostProcessChain): ACES composite litTexture → outputTexture.
    func runCompositePass(commandBuffer: MTLCommandBuffer, outputTexture: MTLTexture) {
        guard let lit = litTexture else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = outputTexture
        desc.colorAttachments[0].loadAction  = .clear
        desc.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(compositePipeline)
        encoder.setFragmentTexture(lit, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
