// RenderPipeline+MVWarpHeadless — the headless mv_warp render seam, plus the two blit
// helpers it shares with the live present path.
//
// `renderMVWarpToTexture` runs the standard / Dragon-Bloom / Skein mv_warp pass chain
// (warp → scene|strands-on-top → blit → swap) to an arbitrary target texture WITHOUT
// presenting a drawable. It exists so the CLEAN.7.6c photosensitivity flash-safety
// harness can drive the REAL pass chain — feedback history and all — instead of
// reimplementing it (FA #66). The live path (`drawWithMVWarp` → `encodeMVWarpBlitPresentSwap`
// in RenderPipeline+MVWarp) and this headless path call the SAME private encoders, so
// the measured render is the rendered render.
//
// `encodeMVWarpBlitContent` (the blit fragment encode) and `swapMVWarpTextures` (the
// feedback compose↔warp swap) live here because they are shared verbatim by both paths;
// keeping them with the headless entry keeps RenderPipeline+MVWarp under file_length.

import Metal
import Shared

// MARK: - Headless mv_warp render

extension RenderPipeline {

    /// The mv_warp blit fragment encode: `composeTexture` → the encoder's bound target
    /// via the blit pipeline, with the display-stage post (invert/echo/gamma) + the
    /// Dragon Bloom per-beat pulse (0 / identity for every other preset). Shared VERBATIM
    /// by the live present path (`encodeMVWarpBlitPresentSwap`, blitting to the drawable)
    /// and the headless target path (`renderMVWarpToTexture`, blitting to an offscreen
    /// texture) so the two cannot drift. The caller owns the encoder lifecycle (render-pass
    /// descriptor + `endEncoding`).
    @MainActor
    func encodeMVWarpBlitContent(
        encoder: MTLRenderCommandEncoder,
        warpState: MVWarpState,
        features: FeatureVector,
        stemFeatures: StemFeatures
    ) {
        encoder.setRenderPipelineState(warpState.blitPipeline)
        encoder.setFragmentTexture(warpState.composeTexture, index: 0)
        // Beat pulse (Dragon Bloom only): a crisp per-beat pump+brighten at the
        // comp/display stage (not fed back). Per-preset since D-143 — other presets
        // (incl. marks-on-top canvas-hold presets like Skein) get 0 (identity).
        let beatEnabled = mvWarpLock.withLock { mvWarpBeatPulseEnabled }
        let beat = beatEnabled ? mvWarpBeatPulse(features: features, stems: stemFeatures) : 0
        var post = mvWarpLock.withLock {
            SIMD4<Float>(mvWarpInvert, mvWarpEcho, mvWarpGamma, beat)
        }
        encoder.setFragmentBytes(&post, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        bindCompStagePresetBuffer(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    /// Swap compose↔warp so this frame's composite becomes next frame's history texture.
    /// The persistence that makes mv_warp a feedback chain.
    func swapMVWarpTextures() {
        mvWarpLock.withLock {
            guard var state = mvWarpState else { return }
            swap(&state.warpTexture, &state.composeTexture)
            mvWarpState = state
        }
    }

    // swiftlint:disable function_parameter_count
    /// Headless twin of `drawWithMVWarp`'s standard / Dragon-Bloom tail: runs the SAME
    /// warp → (scene | strands-on-top compose) → blit(+display-post +beat-pulse) → swap
    /// sequence to an arbitrary `target` texture, WITHOUT presenting a drawable. Drives
    /// the real mv_warp pass chain headless for the flash-safety harness (CLEAN.7.6c).
    /// Fata Morgana (`renderFataMorgana(target:)`) and reduced-motion keep their own
    /// target-agnostic entries; this covers the standard + Dragon Bloom + Skein path.
    @MainActor
    func renderMVWarpToTexture(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        activePipeline: MTLRenderPipelineState,
        warpState: MVWarpState,
        sceneAlreadyRendered: Bool
    ) {
        let strandsOnTop = sceneGeometryLock.withLock { sceneGeometryState != nil }

        // Pass 0 — scene render (non-strands presets only; strands compose on top of the
        // warped frame directly, so they need no separate scene texture).
        if !sceneAlreadyRendered && !strandsOnTop {
            renderSceneToTexture(
                commandBuffer: commandBuffer,
                features: &features,
                stemFeatures: stemFeatures,
                activePipeline: activePipeline,
                target: warpState.sceneTexture)
        }
        // Pass 1 — warp the previous frame into composeTexture.
        encodeMVWarpPass(
            commandBuffer: commandBuffer,
            features: &features,
            stemFeatures: stemFeatures,
            warpState: warpState)
        // Pass 2 — waves/marks on top (Dragon Bloom / Skein) OR decayed compose.
        encodeMVWarpScenePass(
            commandBuffer: commandBuffer,
            warpState: warpState,
            strandsOnTop: strandsOnTop,
            features: &features,
            stemFeatures: stemFeatures)

        // Pass 3 — blit composeTexture → target (display-stage post + beat pulse), then
        // swap. No present (the caller reads `target` back instead).
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture     = target
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
        swapMVWarpTextures()
    }
    // swiftlint:enable function_parameter_count
}
