// RenderPipeline+MVWarpScene — mv_warp Pass-0/Pass-2 scene helpers + the Dragon
// Bloom comp beat-pulse (split out of RenderPipeline+MVWarp.swift for file length).
//
// Two scene paths share the mv_warp warp pass:
//   · Default (Starburst etc.): a direct fragment renders the scene to an offscreen
//     texture, then Pass 2 alpha-blends it onto the decay-warped frame.
//   · Dragon Bloom (D-138): NO separate scene texture — the strands are drawn
//     normal-alpha directly ON TOP of the (no-decay) warped frame, exactly as
//     butterchurn draws its waves onto the warped target. That result IS the
//     feedback; the comp (echo/gamma/invert + beat pump) runs only at the blit.

import Metal
import Shared

extension RenderPipeline {

    // MARK: Pass 0 — Scene → Texture (default direct-render presets)

    /// Render the preset's direct fragment shader to an offscreen texture.
    /// Used for non-ray-march presets (e.g. Starburst) with `.mvWarp` in their passes.
    @MainActor
    func renderSceneToTexture(
        commandBuffer: MTLCommandBuffer,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        activePipeline: MTLRenderPipelineState,
        target: MTLTexture
    ) {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = target
        desc.colorAttachments[0].loadAction  = .clear
        desc.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(activePipeline)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        encoder.setFragmentBuffer(fftMagnitudeBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
        var stems = stemFeatures
        encoder.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.stride, index: 3)
        // Optional per-preset fragment buffers (GossamerState wave pool, ArachneSpiderGPU, slot-8).
        if let presetBuf = directPresetFragmentBufferLock.withLock({ directPresetFragmentBuffer }) {
            encoder.setFragmentBuffer(presetBuf, offset: 0, index: 6)
        }
        if let presetBuf2 = directPresetFragmentBuffer2Lock.withLock({ directPresetFragmentBuffer2 }) {
            encoder.setFragmentBuffer(presetBuf2, offset: 0, index: 7)
        }
        if let presetBuf3 = directPresetFragmentBuffer3Lock.withLock({ directPresetFragmentBuffer3 }) {
            encoder.setFragmentBuffer(presetBuf3, offset: 0, index: 8)
        }
        bindNoiseTextures(to: encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        drawSceneGeometryOverlay(encoder: encoder, features: &features, stems: &stems)
        encoder.endEncoding()
    }

    // MARK: Pass 2 — waves-on-top (Dragon Bloom) OR decayed compose

    /// For Dragon Bloom (`strandsOnTop`), draw the strands normal-alpha directly onto
    /// the warped frame (the feedback). Otherwise alpha-blend the scene texture onto
    /// the decay-warped compose texture (the standard mv_warp compose). (D-138)
    @MainActor
    func encodeMVWarpScenePass(
        commandBuffer: MTLCommandBuffer,
        warpState: MVWarpState,
        strandsOnTop: Bool,
        features: inout FeatureVector,
        stemFeatures: StemFeatures
    ) {
        let decay = mvWarpLock.withLock { mvWarpDecay }
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = warpState.composeTexture
        desc.colorAttachments[0].loadAction  = .load   // keep the warped prev
        desc.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        if strandsOnTop {
            // Skein.ENGINE.1.2: the marks-on-top overlay's FRAGMENT may consume a per-preset
            // world-state buffer (SkeinState's SkeinUniforms — painter clock + per-track seed +
            // onset-burst ring + per-stem colour) at fragment slot 6, the same reserved slot the
            // scene-to-texture path binds for Gossamer/Arachne (renderSceneToTexture). The
            // strands-on-top branch did NOT previously bind it, so the overlay fragment could not
            // see slot 6. Bind it here, gated on non-nil: Dragon Bloom sets no
            // directPresetFragmentBuffer (reset to nil at applyPreset top) ⇒ binds nothing ⇒
            // byte-identical. Fata Morgana uses its own draw branch and never reaches this path.
            if let presetBuf = directPresetFragmentBufferLock.withLock({ directPresetFragmentBuffer }) {
                encoder.setFragmentBuffer(presetBuf, offset: 0, index: 6)
            }
            var stems = stemFeatures
            drawSceneGeometryOverlay(encoder: encoder, features: &features, stems: &stems)
        } else {
            // Fullscreen quad. mvWarp_compose_fragment alpha-blends the scene onto the
            // decay-warped texture (sourceAlpha × src + one × dst); steady state =
            // Σ(1−decay)·decay^n = 1.0 × scene.
            var decayCopy = decay
            encoder.setRenderPipelineState(warpState.composePipeline)
            encoder.setFragmentTexture(warpState.sceneTexture, index: 0)
            encoder.setFragmentBytes(&decayCopy, length: MemoryLayout<Float>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
    }

    // MARK: Comp beat pulse (Dragon Bloom)

    /// Beat-pulse ENVELOPE (0…1) for the Dragon Bloom comp pump (D-138). The trigger
    /// is `beatComposite` shaped to its strong peaks only (baseline ≈ 0.6, peaks 1.0 —
    /// smoothstep(0.78,1.0) keeps only real beats; the drums-stem kick transient is
    /// intentionally NOT used — too spiky/noisy on the process-tap path, it made the
    /// bloom jitter at cold-start / busy sections). The trigger drives a sharp-attack /
    /// smooth-decay envelope (`mvWarpBeatEnv`) so each beat is a pump-and-settle, not a
    /// per-frame flash.
    func mvWarpBeatPulse(features: FeatureVector, stems: StemFeatures) -> Float {
        let bu = min(1.0, max(0.0, (features.beatComposite - 0.78) / 0.22))  // smoothstep(0.78,1.0)
        let trigger = bu * bu * (3.0 - 2.0 * bu)
        // Sharp attack, smooth decay (~0.85/frame ≈ a 150–200 ms settle at 60 fps).
        mvWarpBeatEnv = max(trigger, mvWarpBeatEnv * 0.85)
        return mvWarpBeatEnv
    }
}
