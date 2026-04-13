// RenderPipeline+RayMarch — Deferred ray march draw path (Increment 3.14).
//
// `drawWithRayMarch` is a render path parallel to `drawDirect`, `drawWithFeedback`,
// `drawWithPostProcess`, `drawWithMeshShader`, and `drawWithICB`.  It is invoked from
// `renderFrame` when `rayMarchEnabled == true` and a `RayMarchPipeline` is attached.
//
// The method delegates all G-buffer, lighting, and composite encoding to
// `RayMarchPipeline.render(...)`.  It only acquires the drawable and resolves the
// optional PostProcessChain for the bloom path.
//
// Priority in renderFrame(): mesh → postProcess → ICB → rayMarch → feedback → direct.

import Metal
import MetalKit
import Shared

// MARK: - Ray March Draw Path

extension RenderPipeline {

    // swiftlint:disable function_parameter_count
    // `drawWithRayMarch` takes 6 parameters — the minimal render-pass context,
    // matching the convention used by `drawWithPostProcess`.

    /// Deferred ray march render pass.
    ///
    /// Lazily allocates the pipeline's G-buffer and lit-scene textures if needed,
    /// then delegates all GPU work to `RayMarchPipeline.render(...)`.
    ///
    /// The pipeline runs:
    ///   1. G-buffer pass — preset `sceneSDF` + `sceneMaterial` → 3 G-buffer targets
    ///   2. Lighting pass — Cook-Torrance PBR + screen-space soft shadows → `.rgba16Float`
    ///   3. Composite pass — ACES tone-map to drawable (when no PostProcessChain);
    ///      OR bloom via `PostProcessChain.runBloomAndComposite` when ppChain is provided.
    ///
    /// - Parameters:
    ///   - commandBuffer: Active command buffer to encode all passes into.
    ///   - view: MTKView providing the current drawable.
    ///   - features: Audio feature vector (time/delta pre-filled by `draw(in:)`).
    ///   - stemFeatures: Per-stem features from the background separation pipeline.
    ///   - activePipeline: The preset's compiled G-buffer pipeline state.
    ///   - rayMarchState: Pipeline that owns G-buffer + lit textures and pass encoders.
    func drawWithRayMarch(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        activePipeline: MTLRenderPipelineState,
        rayMarchState: RayMarchPipeline
    ) {
        guard let drawable = view.currentDrawable else { return }

        let size = view.drawableSize
        let width = Int(size.width)
        let height = Int(size.height)
        rayMarchState.ensureAllocated(width: width, height: height)

        // Update per-frame uniforms: accumulated audio time and aspect ratio.
        rayMarchState.sceneUniforms.sceneParamsA.x = features.accumulatedAudioTime
        rayMarchState.sceneUniforms.sceneParamsA.y = width > 0 ? Float(width) / Float(height) : 1.0

        // Resolve optional PostProcessChain: allocate bloom textures if present.
        let (ppEnabled, ppChain) = postProcessLock.withLock { (postProcessEnabled, postProcessChain) }
        let chainForBloom: PostProcessChain? = ppEnabled ? ppChain : nil
        if let chain = chainForBloom {
            chain.ensureAllocated(width: width, height: height)
        }

        let noiseTextures = textureManagerLock.withLock { textureManager }
        rayMarchState.render(
            gbufferPipelineState: activePipeline,
            features: &features,
            fftBuffer: fftMagnitudeBuffer,
            waveformBuffer: waveformBuffer,
            stemFeatures: stemFeatures,
            outputTexture: drawable.texture,
            commandBuffer: commandBuffer,
            noiseTextures: noiseTextures,
            postProcessChain: chainForBloom
        )

        commandBuffer.present(drawable)
    }

    // swiftlint:enable function_parameter_count
}
