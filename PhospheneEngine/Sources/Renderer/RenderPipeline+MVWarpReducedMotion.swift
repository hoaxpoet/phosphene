// RenderPipeline+MVWarpReducedMotion — U.9 reduced-motion fallback for the mv_warp path.
// Split from RenderPipeline+MVWarp (Skein.5) purely for file length; behaviour unchanged.

import Metal
import MetalKit
import Shared

extension RenderPipeline {

    // MARK: Reduced-Motion Fallback (U.9)

    /// Single-frame render when `frameReduceMotion` is true — skips feedback accumulation.
    @MainActor
    // swiftlint:disable:next function_parameter_count
    func drawMVWarpReducedMotion(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        activePipeline: MTLRenderPipelineState,
        warpState: MVWarpState,
        sceneAlreadyRendered: Bool
    ) {
        guard let drawable = view.currentDrawable else { return }
        // Nacre (BUG-061): its direct pipeline is compiled for the .rgba16Float feedback
        // format, so the `renderSceneToTexture(... target: drawable)` branch below would
        // render a 16-float pipeline to the 8-bit drawable → attachment-format mismatch →
        // crash (every OTHER mv_warp preset's direct pipeline is the drawable format).
        // Reduced motion instead presents Nacre's signature comp of the un-advanced
        // feedback (no warp → no accumulation = no motion; the comp pipeline IS the
        // drawable format). Checked before the shared path; warpState.isNacre is false
        // for every other preset (byte-identical).
        if warpState.isNacre {
            renderNacreReducedMotion(
                commandBuffer: commandBuffer,
                features: features,
                warpState: warpState,
                target: drawable.texture)
            commandBuffer.present(drawable)
            return
        }
        // Glaze (BUG-061, same class as Nacre): its direct pipeline is .rgba16Float, so the
        // shared scene-to-drawable path would format-mismatch-crash. Present the comp of the
        // un-advanced feedback (no warp/swap → no motion; the comp pipeline IS drawable format).
        if warpState.isGlaze {
            renderGlazeReducedMotion(
                commandBuffer: commandBuffer,
                features: features,
                warpState: warpState,
                target: drawable.texture)
            commandBuffer.present(drawable)
            return
        }
        if !sceneAlreadyRendered {
            renderSceneToTexture(
                commandBuffer: commandBuffer,
                features: &features,
                stemFeatures: stemFeatures,
                activePipeline: activePipeline,
                target: drawable.texture
            )
        } else {
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture = drawable.texture
            desc.colorAttachments[0].loadAction = .clear
            desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            desc.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
            encoder.setRenderPipelineState(warpState.blitPipeline)
            encoder.setFragmentTexture(warpState.sceneTexture, index: 0)
            var post = mvWarpLock.withLock {
                SIMD4<Float>(mvWarpInvert, mvWarpEcho, mvWarpGamma, 0)
            }
            encoder.setFragmentBytes(&post, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            bindCompStagePresetBuffer(encoder)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }
        commandBuffer.present(drawable)
    }
}
