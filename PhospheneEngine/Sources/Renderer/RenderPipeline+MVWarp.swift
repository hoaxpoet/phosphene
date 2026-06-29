// RenderPipeline+MVWarp — Milkdrop-style per-vertex feedback warp pass (MV-2, D-027).
//
// `drawWithMVWarp` is called from `renderFrame` after the scene has been rendered
// to `mvWarpState.sceneTexture` by a preceding pass (`.rayMarch` + optional
// `.postProcess`), or — for direct-render presets like Starburst — it renders
// the preset fragment to `sceneTexture` itself before applying the warp.
// Three-pass per frame: (1) warp — 32×24 vertex grid warps `warpTexture` (prev) at
// per-vertex displaced UVs × decay → `composeTexture`; (2) compose — scene alpha-blended
// onto `composeTexture`; (3) blit — `composeTexture` → drawable; swap warp ↔ compose.

import Metal
@preconcurrency import MetalKit
import Shared

// MVWarpPipelineBundle + MVWarpState now live in MVWarpTypes.swift.
// Texture allocation + lifecycle (setup / reallocate / clear / decay) live in RenderPipeline+MVWarpSetup.

// MARK: - MVWarp Draw Path

extension RenderPipeline {

    // MARK: Draw

    // swiftlint:disable function_parameter_count
    // drawWithMVWarp takes 7 parameters: the full context needed to coordinate
    // a 3-pass render. Pattern mirrors drawWithPostProcess.

    /// Milkdrop-style per-vertex feedback warp render path.
    ///
    /// - Parameters:
    ///   - commandBuffer: Active command buffer.
    ///   - view: MTKView providing the current drawable.
    ///   - features: Current frame's audio features.
    ///   - stemFeatures: Current frame's per-stem features.
    ///   - activePipeline: Preset's direct-render pipeline (used when scene not pre-rendered).
    ///   - warpState: Allocated mv_warp textures + pipeline states.
    ///   - sceneAlreadyRendered: `true` when a preceding `.rayMarch` pass has already written
    ///     to `warpState.sceneTexture`.  `false` for direct-render presets (Starburst etc.) —
    ///     in that case the preset's fragment is rendered to `sceneTexture` first.
    @MainActor
    func drawWithMVWarp(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        activePipeline: MTLRenderPipelineState,
        warpState: MVWarpState,
        sceneAlreadyRendered: Bool
    ) {
        // Reduced-motion gate (U.9, D-054): suppress temporal feedback accumulation.
        if frameReduceMotion {
            drawMVWarpReducedMotion(
                commandBuffer: commandBuffer,
                view: view,
                features: &features,
                stemFeatures: stemFeatures,
                activePipeline: activePipeline,
                warpState: warpState,
                sceneAlreadyRendered: sceneAlreadyRendered
            )
            return
        }

        // Dedicated branches (see RenderPipeline+Nacre / +Glaze / +Floret / +FataMorgana).
        // Nacre/Glaze/Floret are checked before the blur heuristic so they aren't taken for
        // Fata Morgana (Glaze gains a blur pyramid in 2b; the name flag disambiguates).
        if warpState.isNacre {
            drawWithNacre(
                commandBuffer: commandBuffer,
                view: view,
                features: &features,
                stemFeatures: stemFeatures,
                warpState: warpState)
            return
        }
        if warpState.isGlaze {
            drawWithGlaze(
                commandBuffer: commandBuffer,
                view: view,
                features: &features,
                stemFeatures: stemFeatures,
                warpState: warpState)
            return
        }

        // Floret (FLORET.2a): the Sunflower Passion radial-bloom branch — same shape as Nacre
        // (custom warp → signature comp → swap; no blur target on the 2a stub).
        if warpState.isFloret {
            drawWithFloret(
                commandBuffer: commandBuffer,
                view: view,
                features: &features,
                stemFeatures: stemFeatures,
                warpState: warpState
            )
            return
        }

        // Fata Morgana (D-139): a blur pipeline ⇒ the fata branch — blur(prev) → custom warp
        // → [shapes on top, L2] → procedural mirage comp (display-only) → swap.
        if warpState.blurPipeline != nil {
            drawWithFataMorgana(
                commandBuffer: commandBuffer,
                view: view,
                features: &features,
                stemFeatures: stemFeatures,
                warpState: warpState
            )
            return
        }

        drawWithMVWarpStandard(
            commandBuffer: commandBuffer,
            view: view,
            features: &features,
            stemFeatures: stemFeatures,
            activePipeline: activePipeline,
            warpState: warpState,
            sceneAlreadyRendered: sceneAlreadyRendered)
    }

    /// The standard / Dragon-Bloom / Skein mv_warp pass chain (after the reduced-motion /
    /// Nacre / Floret / Fata Morgana branch dispatch in `drawWithMVWarp`).
    @MainActor
    private func drawWithMVWarpStandard(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        activePipeline: MTLRenderPipelineState,
        warpState: MVWarpState,
        sceneAlreadyRendered: Bool
    ) {
        // Dragon Bloom (D-137): with a scene-geometry overlay (strands) attached, replicate
        // butterchurn's custom-warp loop — warp prev (NO decay; the custom warp self-regulates),
        // draw the waves NORMAL-ALPHA ON TOP (that IS the feedback; comp/echo/invert is
        // display-only at blit). Other presets keep the scene + decayed-compose.
        let strandsOnTop = sceneGeometryLock.withLock { sceneGeometryState != nil }

        // ── Pass 0: Scene render (non-strands presets) ───────────────────────
        // For ray-march presets the scene is already in warpState.sceneTexture;
        // drawWithRayMarch renders to that texture when mv_warp is active.
        if !sceneAlreadyRendered && !strandsOnTop {
            renderSceneToTexture(
                commandBuffer: commandBuffer,
                features: &features,
                stemFeatures: stemFeatures,
                activePipeline: activePipeline,
                target: warpState.sceneTexture
            )
        }

        // ── Pass 1: Warp pass ────────────────────────────────────────────────
        encodeMVWarpPass(
            commandBuffer: commandBuffer,
            features: &features,
            stemFeatures: stemFeatures,
            warpState: warpState
        )

        // ── Pass 2: Waves-on-top (Dragon Bloom) OR decayed compose ───────────
        encodeMVWarpScenePass(
            commandBuffer: commandBuffer,
            warpState: warpState,
            strandsOnTop: strandsOnTop,
            features: &features,
            stemFeatures: stemFeatures
        )

        // ── Pass 3: Blit to drawable + present + swap ────────────────────────
        encodeMVWarpBlitPresentSwap(
            commandBuffer: commandBuffer,
            view: view,
            warpState: warpState,
            features: features,
            stemFeatures: stemFeatures
        )
    }
    // swiftlint:enable function_parameter_count
}
