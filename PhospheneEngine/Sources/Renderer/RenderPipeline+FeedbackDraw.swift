import Metal
@preconcurrency import MetalKit
import Shared

extension RenderPipeline {

    // MARK: Feedback Rendering (Milkdrop-Style)

    /// Feedback render path. Two modes depending on whether particles are attached:
    ///
    /// - **Particle mode** (Murmuration): warp (unused) → preset + particles drawn
    ///   directly to the drawable. The feedback texture is maintained but not shown.
    ///
    /// - **Surface mode** (Membrane): warp → composite (additive) → blit to drawable.
    ///   The preset's contribution accumulates into the feedback texture each frame.
    @MainActor
    func drawWithFeedback(_ ctx: inout FeedbackDrawContext) {
        let currentTex = ctx.textures[ctx.texIndex]
        let previousTex = ctx.textures[1 - ctx.texIndex]
        ctx.params.beatValue = ctx.params.beatValue
        runWarpPass(
            commandBuffer: ctx.commandBuffer,
            features: &ctx.features,
            params: &ctx.params,
            target: currentTex,
            source: previousTex
        )
        if ctx.particles != nil {
            drawParticleMode(
                commandBuffer: ctx.commandBuffer,
                view: ctx.view,
                features: &ctx.features,
                stemFeatures: ctx.stemFeatures,
                activePipeline: ctx.activePipeline,
                particles: ctx.particles
            )
        } else {
            drawSurfaceMode(
                commandBuffer: ctx.commandBuffer,
                view: ctx.view,
                features: &ctx.features,
                stemFeatures: ctx.stemFeatures,
                composePipeline: ctx.composePipeline,
                feedbackTexture: currentTex
            )
        }
    }

    /// Pass 1 of the feedback loop: read the previous texture, apply decay and
    /// any subtle warp, write the result into the current texture.
    func runWarpPass(
        commandBuffer: MTLCommandBuffer,
        features: inout FeatureVector,
        params: inout FeedbackParams,
        target: MTLTexture,
        source: MTLTexture
    ) {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(feedbackWarpPipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<FeedbackParams>.stride, index: 1)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(feedbackSamplerState, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // swiftlint:disable function_parameter_count

    /// Particle mode drawable pass: render the preset + particles directly to the
    /// drawable without blending through the feedback texture.
    @MainActor
    func drawParticleMode(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        activePipeline: MTLRenderPipelineState,
        particles: ProceduralGeometry?
    ) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else { return }
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encoder.setRenderPipelineState(activePipeline)
            encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
            encoder.setFragmentBuffer(fftMagnitudeBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
            var stems = stemFeatures
            encoder.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.size, index: 3)
            encoder.setFragmentBuffer(spectralHistory.gpuBuffer, offset: 0, index: 5)
            bindNoiseTextures(to: encoder)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            particles?.render(encoder: encoder, features: features)
            encoder.endEncoding()
        }
        compositeDashboard(commandBuffer: commandBuffer, view: view)
        commandBuffer.present(drawable)
    }

    /// Surface mode: composite the preset additively into the (already warped)
    /// feedback texture, then blit the result to the drawable.
    @MainActor
    func drawSurfaceMode(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        composePipeline: MTLRenderPipelineState,
        feedbackTexture: MTLTexture
    ) {
        let composeDesc = MTLRenderPassDescriptor()
        composeDesc.colorAttachments[0].texture = feedbackTexture
        composeDesc.colorAttachments[0].loadAction = .load
        composeDesc.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: composeDesc) {
            encoder.setRenderPipelineState(composePipeline)
            encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
            encoder.setFragmentBuffer(fftMagnitudeBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
            var stems = stemFeatures
            encoder.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.size, index: 3)
            encoder.setFragmentBuffer(spectralHistory.gpuBuffer, offset: 0, index: 5)
            bindNoiseTextures(to: encoder)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else { return }
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encoder.setRenderPipelineState(feedbackBlitPipelineState)
            encoder.setFragmentTexture(feedbackTexture, index: 0)
            encoder.setFragmentSamplerState(feedbackSamplerState, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        compositeDashboard(commandBuffer: commandBuffer, view: view)
        commandBuffer.present(drawable)
    }

    // swiftlint:enable function_parameter_count
}
