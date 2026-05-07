// RenderPipeline+PostProcess — HDR post-process draw path for Increment 3.4.
//
// `drawWithPostProcess` is a private render path parallel to `drawDirect`,
// `drawWithFeedback`, and `drawWithMeshShader`.  It is invoked from `renderFrame`
// when `postProcessEnabled == true` and a `PostProcessChain` is attached.
//
// The method delegates all render encoding to `PostProcessChain.render(...)`, which
// owns the pipeline states and intermediate textures.  `RenderPipeline` only acquires
// the drawable and forwards the audio buffer bindings.

import Metal
@preconcurrency import MetalKit
import Shared

// MARK: - Post-Process Draw Path

extension RenderPipeline {

    // swiftlint:disable function_parameter_count
    // `drawWithPostProcess` takes 6 parameters — the minimal render-pass context,
    // matching the convention used by `drawDirect` and `drawSurfaceMode`.

    /// HDR post-process render pass.
    ///
    /// Lazily allocates the chain's textures if needed, then delegates all GPU work to
    /// `PostProcessChain.render(...)`.  The chain runs:
    ///   1. Scene preset → `.rgba16Float` HDR texture
    ///   2. Bright pass (luminance > 0.9) → half-res bloom
    ///   3. Horizontal Gaussian blur
    ///   4. Vertical Gaussian blur
    ///   5. ACES composite → drawable (`.bgra8Unorm_srgb`)
    ///
    /// - Parameters:
    ///   - commandBuffer: Active command buffer to encode all passes into.
    ///   - view: MTKView providing the current drawable.
    ///   - features: Audio feature vector (time/delta pre-filled by `draw(in:)`).
    ///   - stemFeatures: Per-stem features from the background separation pipeline.
    ///   - activePipeline: The compiled scene preset pipeline state.
    ///   - chain: Post-process chain that owns the intermediate textures and passes.
    @MainActor
    func drawWithPostProcess(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        activePipeline: MTLRenderPipelineState,
        chain: PostProcessChain
    ) {
        guard let drawable = view.currentDrawable else { return }

        // Lazy-allocate the chain's textures if drawableSizeWillChange hasn't fired.
        let size = view.drawableSize
        chain.ensureAllocated(width: Int(size.width), height: Int(size.height))

        let noiseTextures = textureManagerLock.withLock { textureManager }
        chain.render(
            scenePipelineState: activePipeline,
            features: &features,
            fftBuffer: fftMagnitudeBuffer,
            waveformBuffer: waveformBuffer,
            stemFeatures: stemFeatures,
            outputTexture: drawable.texture,
            commandBuffer: commandBuffer,
            noiseTextures: noiseTextures
        )

        commandBuffer.present(drawable)
    }
    // swiftlint:enable function_parameter_count
}
