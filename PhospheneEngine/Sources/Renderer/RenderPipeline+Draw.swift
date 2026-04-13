// RenderPipeline+Draw — Draw method extraction for the render pipeline.
// Splits out the feedback and direct rendering passes to keep the main
// type body within SwiftLint's length limits.

import Metal
import MetalKit
import Shared

// MARK: - Feedback Draw Context

/// Groups the nine parameters of a feedback draw call into a single value type,
/// reducing the function signature to a manageable size.
struct FeedbackDrawContext {
    let commandBuffer: MTLCommandBuffer
    let view: MTKView
    var features: FeatureVector
    var params: FeedbackParams
    var stemFeatures: StemFeatures
    let activePipeline: MTLRenderPipelineState
    let composePipeline: MTLRenderPipelineState
    let particles: ProceduralGeometry?
    let textures: [MTLTexture]
    let texIndex: Int
}

// MARK: - Draw Methods

extension RenderPipeline {

    // MARK: Noise Texture Binding

    /// Bind the TextureManager's noise textures to fragment slots 4–8, if attached.
    /// No-op when no TextureManager is set (backwards-compatible).
    func bindNoiseTextures(to encoder: MTLRenderCommandEncoder) {
        textureManagerLock.withLock { textureManager }?.bindTextures(to: encoder)
    }

    // MARK: Feedback Texture Allocation

    /// Lazily allocate feedback textures when drawableSizeWillChange has not fired.
    /// Must be called while holding feedbackLock externally (or within a withLock block).
    func ensureFeedbackTexturesAllocated(size: CGSize) {
        guard feedbackEnabled && feedbackTextures.isEmpty && size.width > 0 else {
            return
        }
        let texWidth = max(Int(size.width), 1)
        let texHeight = max(Int(size.height), 1)
        var textures: [MTLTexture] = []
        for _ in 0..<2 {
            if let tex = context.makeSharedTexture(
                width: texWidth,
                height: texHeight,
                usage: [.renderTarget, .shaderRead]
            ) {
                textures.append(tex)
            }
        }
        if textures.count == 2 {
            feedbackTextures = textures
            feedbackIndex = 0
        }
    }

    // MARK: Frame Dispatch

    // swiftlint:disable function_body_length
    // renderFrame snapshots five independent capability flags (particles, feedback,
    // post-process, ICB, mesh) before branching.  The snapshot + branch pattern is
    // intentionally flat — extracting sub-branches would obscure the priority order.

    /// Snapshot per-frame state and dispatch to the appropriate rendering path.
    /// Called from `draw(in:)` after timing and features are prepared.
    func renderFrame(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector
    ) {
        // Snapshot state for this frame.
        let particles = particleLock.withLock { particleGeometry }
        let activePipeline = pipelineLock.withLock { pipelineState }
        let stemFeatures = stemFeaturesLock.withLock { latestStemFeatures }

        // Lazy-allocate feedback textures if needed (drawableSizeWillChange may not fire).
        let drawableSize = view.drawableSize
        feedbackLock.withLock {
            ensureFeedbackTexturesAllocated(size: drawableSize)
        }

        let (fbEnabled, fbParams, fbCompose, fbTextures, fbIndex) = feedbackLock.withLock {
            (feedbackEnabled, currentFeedbackParams, feedbackComposePipelineState,
             feedbackTextures, feedbackIndex)
        }

        // Snapshot post-process state for this frame.
        let (ppEnabled, ppChain) = postProcessLock.withLock { (postProcessEnabled, postProcessChain) }

        // Snapshot ICB state for this frame.
        let (icbIsEnabled, icbSnapshotState) = icbLock.withLock { (icbEnabled, icbState) }

        // ── Compute pass: update particles before rendering ─────────
        particles?.update(features: features, commandBuffer: commandBuffer)

        // Snapshot mesh shader state for this frame.
        let (meshEnabled, meshGen) = meshLock.withLock { (meshShaderEnabled, meshGenerator) }

        // Branch: mesh shader → post-process → ICB → feedback → direct.
        if meshEnabled, let generator = meshGen {
            drawWithMeshShader(
                commandBuffer: commandBuffer,
                view: view,
                features: &features,
                stemFeatures: stemFeatures,
                meshGenerator: generator
            )
        } else if ppEnabled, let chain = ppChain {
            drawWithPostProcess(
                commandBuffer: commandBuffer,
                view: view,
                features: &features,
                stemFeatures: stemFeatures,
                activePipeline: activePipeline,
                chain: chain
            )
        } else if icbIsEnabled, let icb = icbSnapshotState {
            drawWithICB(
                commandBuffer: commandBuffer,
                view: view,
                features: &features,
                stemFeatures: stemFeatures,
                activePipeline: activePipeline,
                icbState: icb
            )
        } else if fbEnabled, let params = fbParams, let composePipeline = fbCompose,
           fbTextures.count == 2 {
            var ctx = FeedbackDrawContext(
                commandBuffer: commandBuffer,
                view: view,
                features: features,
                params: params,
                stemFeatures: stemFeatures,
                activePipeline: activePipeline,
                composePipeline: composePipeline,
                particles: particles,
                textures: fbTextures,
                texIndex: fbIndex
            )
            drawWithFeedback(&ctx)
            feedbackLock.withLock { feedbackIndex = 1 - feedbackIndex }
        } else {
            drawDirect(
                commandBuffer: commandBuffer,
                view: view,
                features: &features,
                stemFeatures: stemFeatures,
                activePipeline: activePipeline,
                particles: particles
            )
        }
    }
    // swiftlint:enable function_body_length

    // MARK: Direct Rendering (Non-Feedback)

    // swiftlint:disable function_parameter_count
    // drawDirect / drawParticleMode / drawSurfaceMode each take 6 parameters —
    // the full render-pass context they coordinate. Refactor tracked separately.

    /// Original single-pass render directly to drawable.
    func drawDirect(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        activePipeline: MTLRenderPipelineState,
        particles: ProceduralGeometry?
    ) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }

        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        // Draw preset visualization.
        encoder.setRenderPipelineState(activePipeline)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        encoder.setFragmentBuffer(fftMagnitudeBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
        var stems = stemFeatures
        encoder.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.size, index: 3)
        bindNoiseTextures(to: encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        // Draw particles on top.
        particles?.render(encoder: encoder, features: features)

        encoder.endEncoding()

        commandBuffer.present(drawable)
    }

    // MARK: Feedback Rendering (Milkdrop-Style)

    /// Feedback render path. Two modes depending on whether particles are attached:
    ///
    /// - **Particle mode** (Murmuration): warp (unused) → preset + particles drawn
    ///   directly to the drawable. The feedback texture is maintained but not shown,
    ///   to prevent additive washout over a vivid sky backdrop.
    ///
    /// - **Surface mode** (Membrane): warp → composite (additive) → blit to drawable.
    ///   The preset's contribution accumulates into the feedback texture each frame
    ///   and the warped/decayed previous state provides visual memory. This is the
    ///   true Milkdrop-style feedback loop.
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

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else {
            return
        }
        encoder.setRenderPipelineState(feedbackWarpPipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<FeedbackParams>.stride, index: 1)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(feedbackSamplerState, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Particle mode drawable pass: render the preset + particles directly to the
    /// drawable without blending through the feedback texture.
    func drawParticleMode(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        activePipeline: MTLRenderPipelineState,
        particles: ProceduralGeometry?
    ) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }
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
            bindNoiseTextures(to: encoder)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            particles?.render(encoder: encoder, features: features)
            encoder.endEncoding()
        }
        commandBuffer.present(drawable)
    }

    /// Surface mode: composite the preset additively into the (already warped)
    /// feedback texture, then blit the result to the drawable.
    func drawSurfaceMode(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        composePipeline: MTLRenderPipelineState,
        feedbackTexture: MTLTexture
    ) {
        // Pass 2: additive composite into the warped feedback texture.
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
            bindNoiseTextures(to: encoder)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        // Drawable pass: blit feedback texture to screen.
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }
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
        commandBuffer.present(drawable)
    }
    // swiftlint:enable function_parameter_count
}
