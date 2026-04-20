// RenderPipeline+Draw — Generic render-graph executor (Increment 3.6).
//
// `renderFrame` replaces the old hardcoded priority-chain with a data-driven loop over
// `activePasses`.  The preset declares its passes in JSON; the executor dispatches to
// the first pass whose required subsystem is available, falling back to direct rendering.
//
// Adding a new capability requires only: a new `RenderPass` case in Shared, a
// `drawWithX` method, and one `case` in the switch below.

import Metal
@preconcurrency import MetalKit
import Shared

// MARK: - Feedback Draw Context

/// Groups the parameters of a feedback draw call into a single value type,
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
        guard currentFeedbackParams != nil && feedbackTextures.isEmpty && size.width > 0 else {
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

    // MARK: Render-Graph Executor

    // swiftlint:disable cyclomatic_complexity function_body_length
    // renderFrame iterates the passes array with one case per capability type.
    // The switch is the whole point — extracting cases would obscure the dispatch logic.
    /// Snapshot per-frame state and dispatch to the appropriate rendering path.
    ///
    /// Iterates `activePasses` in declared order and executes the first pass whose
    /// required subsystem is available.  Falls back to `drawDirect` if no pass matches.
    /// Called from `draw(in:)` after timing and features are prepared.
    ///
    /// **MV-2 multi-pass flow:** When `.mvWarp` is in the passes array, the preceding
    /// `.rayMarch` pass renders to an offscreen scene texture (not the drawable) and
    /// does NOT return — the loop continues to `.mvWarp` which applies the warp and blits.
    /// For direct-render presets (`["mv_warp"]`), the `.mvWarp` case renders the preset
    /// fragment to sceneTexture itself before warping.
    @MainActor
    func renderFrame(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector
    ) {
        // Snapshot the active passes for this frame.
        let passes = passesLock.withLock { activePasses }

        // Snapshot all subsystem state atomically before branching.
        let particles      = particleLock.withLock { particleGeometry }
        let activePipeline = pipelineLock.withLock { pipelineState }
        let stemFeatures   = stemFeaturesLock.withLock { latestStemFeatures }
        let meshGen        = meshLock.withLock { meshGenerator }
        let ppChain        = postProcessLock.withLock { postProcessChain }
        let icbSnap        = icbLock.withLock { icbState }
        let rmPipeline     = rayMarchLock.withLock { rayMarchPipeline }
        let mvWarpSnap     = mvWarpLock.withLock { mvWarpState }

        // Is the mv_warp pass active this frame?
        let mvWarpActive = passes.contains(.mvWarp) && mvWarpSnap != nil

        // Lazy-allocate feedback textures if needed (drawableSizeWillChange may not fire).
        let drawableSize = view.drawableSize
        feedbackLock.withLock {
            ensureFeedbackTexturesAllocated(size: drawableSize)
        }
        let (fbParams, fbCompose, fbTextures, fbIndex) = feedbackLock.withLock {
            (currentFeedbackParams, feedbackComposePipelineState, feedbackTextures, feedbackIndex)
        }

        // Compute pass: update particles before any render pass.
        particles?.update(features: features, stemFeatures: stemFeatures, commandBuffer: commandBuffer)

        // Track whether the scene has been rendered to sceneTexture by a preceding pass.
        var sceneRenderedToWarpTarget = false

        // Walk the passes array — execute the first pass with available resources.
        for pass in passes {
            switch pass {

            case .meshShader:
                guard let gen = meshGen else { continue }
                drawWithMeshShader(
                    commandBuffer: commandBuffer,
                    view: view,
                    features: &features,
                    stemFeatures: stemFeatures,
                    meshGenerator: gen
                )
                return

            case .rayMarch:
                guard let rm = rmPipeline else { continue }
                if mvWarpActive, let warpState = mvWarpSnap {
                    // MV-2: render scene to offscreen texture so mv_warp can warp it.
                    drawWithRayMarch(
                        commandBuffer: commandBuffer,
                        view: view,
                        features: &features,
                        stemFeatures: stemFeatures,
                        activePipeline: activePipeline,
                        rayMarchState: rm,
                        sceneOutputTexture: warpState.sceneTexture
                    )
                    sceneRenderedToWarpTarget = true
                    // Continue the loop — .mvWarp will present the result.
                } else {
                    drawWithRayMarch(
                        commandBuffer: commandBuffer,
                        view: view,
                        features: &features,
                        stemFeatures: stemFeatures,
                        activePipeline: activePipeline,
                        rayMarchState: rm,
                        sceneOutputTexture: nil
                    )
                    return
                }

            case .postProcess:
                // Stand-alone post-process path.  When combined with .rayMarch, the ray
                // march pipeline uses the PostProcessChain internally for bloom — the
                // .postProcess pass itself is only executed if .rayMarch is absent.
                guard !passes.contains(.rayMarch), let chain = ppChain else { continue }
                drawWithPostProcess(
                    commandBuffer: commandBuffer,
                    view: view,
                    features: &features,
                    stemFeatures: stemFeatures,
                    activePipeline: activePipeline,
                    chain: chain
                )
                return

            case .icb:
                guard let icb = icbSnap else { continue }
                drawWithICB(
                    commandBuffer: commandBuffer,
                    view: view,
                    features: &features,
                    stemFeatures: stemFeatures,
                    activePipeline: activePipeline,
                    icbState: icb
                )
                return

            case .feedback:
                guard let params  = fbParams,
                      let compose = fbCompose,
                      fbTextures.count == 2 else { continue }
                var ctx = FeedbackDrawContext(
                    commandBuffer: commandBuffer,
                    view: view,
                    features: features,
                    params: params,
                    stemFeatures: stemFeatures,
                    activePipeline: activePipeline,
                    composePipeline: compose,
                    particles: particles,
                    textures: fbTextures,
                    texIndex: fbIndex
                )
                drawWithFeedback(&ctx)
                feedbackLock.withLock { feedbackIndex = 1 - feedbackIndex }
                return

            case .mvWarp:
                // MV-2: per-vertex feedback warp pass.
                // `sceneRenderedToWarpTarget` is true when .rayMarch rendered offscreen.
                // For direct-render presets (no preceding rayMarch), the warp draws
                // the preset fragment to sceneTexture itself.
                guard let warpState = mvWarpSnap else { continue }
                drawWithMVWarp(
                    commandBuffer: commandBuffer,
                    view: view,
                    features: &features,
                    stemFeatures: stemFeatures,
                    activePipeline: activePipeline,
                    warpState: warpState,
                    sceneAlreadyRendered: sceneRenderedToWarpTarget
                )
                return

            case .direct, .particles, .ssgi:
                // .direct: fallback below. .particles: handled in drawWithFeedback.
                // .ssgi: companion to .rayMarch, wired in drawWithRayMarch.
                break
            }
        }

        // Fallback: direct rendering (no capability-specific pass matched).
        drawDirect(
            commandBuffer: commandBuffer,
            view: view,
            features: &features,
            stemFeatures: stemFeatures,
            activePipeline: activePipeline,
            particles: particles
        )
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    // MARK: Direct Rendering (Non-Feedback)

    // swiftlint:disable function_parameter_count
    // drawDirect/drawParticleMode/drawSurfaceMode each take 6 parameters —
    // the full render-pass context they coordinate. Refactor tracked separately.

    /// Original single-pass render directly to drawable.
    @MainActor
    func drawDirect(
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
        encoder.setFragmentBuffer(spectralHistory.gpuBuffer, offset: 0, index: 5)
        bindNoiseTextures(to: encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        // Draw particles on top.
        particles?.render(encoder: encoder, features: features)

        encoder.endEncoding()

        commandBuffer.present(drawable)
    }

    // swiftlint:enable function_parameter_count
}
