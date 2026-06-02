// RenderPipeline+SceneGeometry.swift — additive scene-geometry overlay.
//
// Draws an optional additive geometry pass into the mv_warp scene texture AFTER
// the fullscreen background fragment, within the same render pass. Used by Dragon
// Bloom (D-137, L1) to draw its three spectral STRANDS — each an instanced line
// strip (instance_id = strand, vertex_id = sample) whose vertex shader computes
// the per-point tumbling-strand math from FeatureVector(0) + StemFeatures(1) and
// drives each strand by its stem (drums/bass/vocals). The pipeline's blend is
// additive, so the strands accumulate as glow over the background; the existing
// mv_warp feedback then feathers them into the bloom.
//
// Wired via `setSceneGeometry` (RenderPipeline+PresetSwitching); state stored on
// RenderPipeline. nil state ⇒ no overlay (every other direct/mv_warp preset).

import Metal
import Shared

// MARK: -

extension RenderPipeline {

    /// Draw the optional additive scene-geometry overlay into the active scene
    /// encoder. No-op when no overlay is attached. Binds the per-frame audio so
    /// the geometry's vertex shader can compute its form from time + stems.
    func drawSceneGeometryOverlay(
        encoder: MTLRenderCommandEncoder,
        features: inout FeatureVector,
        stems: inout StemFeatures
    ) {
        let geo = sceneGeometryLock.withLock {
            (sceneGeometryState, sceneGeometryVertexCount,
             sceneGeometryInstanceCount, sceneGeometryPrimitive)
        }
        guard let state = geo.0, geo.1 > 0, geo.2 > 0 else { return }
        encoder.setRenderPipelineState(state)
        encoder.setVertexBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        encoder.setVertexBytes(&stems, length: MemoryLayout<StemFeatures>.stride, index: 1)
        encoder.drawPrimitives(
            type: geo.3, vertexStart: 0, vertexCount: geo.1, instanceCount: geo.2)
    }
}
