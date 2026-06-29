// RenderPipeline+MVWarpEncoders — the standard mv_warp pass encoders + helpers, split out of
// RenderPipeline+MVWarp.swift (FLORET_PLAN §10: a 3rd custom-warp+comp preset — Glaze, GLAZE.8 —
// tipped the parent file past the 400-line cap; extract the standard-path encoders, the prescribed
// remedy). Same `extension RenderPipeline`; behaviour byte-identical (a pure file move).

import Metal
@preconcurrency import MetalKit
import Shared

// MARK: - MVWarp Pass Encoders

extension RenderPipeline {
    /// Pass 3 of the standard/Dragon-Bloom mv_warp path: blit `composeTexture` to
    /// the drawable (with the display-stage post + Dragon Bloom beat pulse), present,
    /// then swap compose ↔ warp for the next frame. (Fata Morgana has its own blit in
    /// `drawWithFataMorgana`.)
    @MainActor
    func encodeMVWarpBlitPresentSwap(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        warpState: MVWarpState,
        features: FeatureVector,
        stemFeatures: StemFeatures
    ) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }
        // .dontCare is correct — the full-screen triangle overwrites every pixel.
        descriptor.colorAttachments[0].loadAction  = .dontCare
        descriptor.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encodeMVWarpBlitContent(
                encoder: encoder,
                warpState: warpState,
                features: features,
                stemFeatures: stemFeatures)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        swapMVWarpTextures()
    }

    // MARK: - Warp Pass Encoder

    /// Encodes the 32×24 vertex-grid warp pass to `warpState.composeTexture`.
    /// `internal` (not private) so the headless seam in `RenderPipeline+MVWarpHeadless`
    /// can run the identical warp pass (FA #66 — one code path for live + harness).
    @MainActor
    func encodeMVWarpPass(
        commandBuffer: MTLCommandBuffer,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        warpState: MVWarpState
    ) {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = warpState.composeTexture
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(warpState.warpPipeline)
        var featuresCopy = features
        encoder.setVertexBytes(&featuresCopy, length: MemoryLayout<FeatureVector>.stride, index: 0)
        var stemsCopy = stemFeatures
        encoder.setVertexBytes(&stemsCopy, length: MemoryLayout<StemFeatures>.stride, index: 1)
        var sceneUni = getSceneUniforms()
        encoder.setVertexBytes(&sceneUni, length: MemoryLayout<SceneUniforms>.stride, index: 2)
        encoder.setFragmentTexture(warpState.warpTexture, index: 0)
        var chromatic = mvWarpLock.withLock { mvWarpChromatic }   // L3: 0 ⇒ identity for non-DB
        encoder.setFragmentBytes(&chromatic, length: MemoryLayout<Float>.stride, index: 0)
        // Skein.ENGINE.2: per-frame wetness-channel decay (ALPHA only) for canvas-hold presets.
        // 1.0 ⇒ A held unchanged. Only Skein's own `skein_warp_fragment` declares buffer 1; the
        // shared `mvWarp_fragment` does not, so binding it here is inert for every other preset
        // (byte-identical — PresetRegression + the DB/FM MVWarp accumulation tests confirm).
        var wetnessDecay = mvWarpLock.withLock { mvWarpWetnessDecay }
        encoder.setFragmentBytes(&wetnessDecay, length: MemoryLayout<Float>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)  // 31×23 quads
        encoder.endEncoding()
    }

    // MARK: Helpers

    /// Skein.5: bind the per-preset comp-stage buffer (the display-only painter locus reads
    /// SkeinUniforms) at fragment buffer 1 of the blit pass. Only Skein's `skein_comp_fragment`
    /// declares buffer 1 — inert for every other preset (the ENGINE.2 wetnessDecay precedent);
    /// nil (e.g. Dragon Bloom) ⇒ nothing bound, exactly as before.
    func bindCompStagePresetBuffer(_ encoder: MTLRenderCommandEncoder) {
        if let presetBuf = directPresetFragmentBufferLock.withLock({ directPresetFragmentBuffer }) {
            encoder.setFragmentBuffer(presetBuf, offset: 0, index: 1)
        }
    }

    /// Extract the current SceneUniforms from the attached ray march pipeline (if any).
    /// Falls back to a zeroed struct for direct-render presets.
    func getSceneUniforms() -> SceneUniforms {
        return rayMarchLock.withLock { rayMarchPipeline?.sceneUniforms } ?? SceneUniforms()
    }
}
