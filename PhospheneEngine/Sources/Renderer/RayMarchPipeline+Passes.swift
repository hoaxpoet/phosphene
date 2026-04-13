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

// MARK: - G-buffer Pass

extension RayMarchPipeline {

    // swiftlint:disable function_parameter_count
    // `runGBufferPass` takes 7 parameters — the minimal set for encoding a preset draw call.

    /// Pass 1: Render the preset's SDF scene into the three G-buffer targets.
    func runGBufferPass(
        commandBuffer: MTLCommandBuffer,
        gbufferPipelineState: MTLRenderPipelineState,
        features: inout FeatureVector,
        fftBuffer: MTLBuffer,
        waveformBuffer: MTLBuffer,
        stemFeatures: StemFeatures,
        noiseTextures: TextureManager?
    ) {
        guard let g0 = gbuffer0, let g1 = gbuffer1, let g2 = gbuffer2 else { return }

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

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(gbufferPipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        encoder.setFragmentBuffer(fftBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
        var stems = stemFeatures
        encoder.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.stride, index: 3)
        encoder.setFragmentBytes(&sceneUniforms, length: MemoryLayout<SceneUniforms>.stride, index: 4)
        noiseTextures?.bindTextures(to: encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // swiftlint:enable function_parameter_count
}

// MARK: - Lighting Pass

extension RayMarchPipeline {

    /// Pass 2: Evaluate PBR lighting from G-buffer data → litTexture (.rgba16Float).
    /// IBL textures (Increment 3.16) are bound at slots 9–11 when `iblManager` is non-nil.
    func runLightingPass(
        commandBuffer: MTLCommandBuffer,
        features: inout FeatureVector,
        noiseTextures: TextureManager?,
        iblManager: IBLManager? = nil
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
