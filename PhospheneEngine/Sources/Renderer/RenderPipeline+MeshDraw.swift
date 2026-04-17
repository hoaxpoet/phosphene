// RenderPipeline+MeshDraw — Mesh shader draw path for Increment 3.2.
//
// `drawWithMeshShader` is a private render pass parallel to `drawDirect` and
// `drawWithFeedback`.  It is invoked from `renderFrame` when
// `meshShaderEnabled == true` and a `MeshGenerator` is attached.
//
// The method does not use the preset's `activePipeline` directly — the
// `MeshGenerator` owns its own compiled pipeline state (either native mesh or
// vertex fallback) and handles the draw dispatch internally.  This lets
// Increment 3.2b and later presets swap their own `MeshGenerator` instance in
// without requiring RenderPipeline to understand mesh topology.

import Metal
import MetalKit
import Shared

// MARK: - Mesh Draw Pass

extension RenderPipeline {

    /// Mesh shader render pass.
    ///
    /// Acquires the current drawable, clears to black, and encodes one draw via
    /// `meshGenerator.draw(encoder:features:)`.  The generator selects between
    /// `drawMeshThreadgroups` (M3+) and `drawPrimitives` (M1/M2 fallback)
    /// based on `MeshGenerator.usesMeshShaderPath`.
    ///
    /// Stem features are bound at fragment buffer(3) to maintain the same
    /// buffer-index protocol used by `drawDirect` and `drawSurfaceMode`.
    ///
    /// - Parameters:
    ///   - commandBuffer: Active command buffer to encode into.
    ///   - view: MTKView providing the current drawable and render pass descriptor.
    ///   - features: Audio feature vector (time/delta pre-filled by `draw(in:)`).
    ///   - stemFeatures: Per-stem features from the background separation pipeline.
    ///   - meshGenerator: Generator that owns the pipeline state and dispatches geometry.
    func drawWithMeshShader(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        meshGenerator: MeshGenerator
    ) {
        let (descriptor, drawable) = MainActor.assumeIsolated {
            (view.currentRenderPassDescriptor, view.currentDrawable)
        }
        guard let descriptor, let drawable else { return }

        descriptor.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].loadAction  = .clear
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        // Bind stem features at buffer(3) — consistent with all other render paths.
        var stems = stemFeatures
        encoder.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.size, index: 3)

        // Bind noise textures at fragment slots 4–8.
        bindNoiseTextures(to: encoder)

        // Delegate pipeline state selection and draw dispatch to the generator.
        meshGenerator.draw(encoder: encoder, features: features)

        encoder.endEncoding()
        commandBuffer.present(drawable)
    }
}
