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
import os.log

private let mvWarpLogger = Logger(subsystem: "com.phosphene.renderer", category: "MVWarp")

// MVWarpPipelineBundle + MVWarpState now live in MVWarpTypes.swift.

// MARK: - MVWarp Draw Path

extension RenderPipeline {

    // MARK: Setup

    /// Allocate mv_warp textures and store pipeline states from the preset bundle.
    ///
    /// Call from `applyPreset` when the incoming preset declares `.mvWarp`.
    /// Call again from `drawableSizeWillChange` to reallocate at the new size.
    /// Thread-safe — wraps the write in `mvWarpLock`.
    public func setupMVWarp(bundle: MVWarpPipelineBundle, size: CGSize) {
        let width  = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)

        guard let warpTex    = makeWarpTexture(width: width, height: height, format: bundle.feedbackFormat),
              let composeTex = makeWarpTexture(width: width, height: height, format: bundle.feedbackFormat),
              let sceneTex   = makeWarpTexture(width: width, height: height, format: bundle.feedbackFormat)
        else {
            mvWarpLogger.error("Failed to allocate mv_warp textures at \(width)×\(height)")
            return
        }

        // AV.2.1: clear freshly-allocated textures to the canvas ground — .private GPU
        // memory isn't zero-initialised, so the first post-switch frame can read stale bits
        // (live AV.2: full-screen magenta for ~1 s after preset switch).
        // Skein.ENGINE.1.1 (D-143): clear colour is per-preset (black byte-identical for all
        // but marks-on-top presets, where this clear IS the held ground — Skein's cream).
        // Skein.5.3b: a per-track ground override (palette light/dark grounds) wins over the
        // preset-static colour, incl. on the resize re-clear (→ the current track's ground).
        let cc = mvWarpLock.withLock { mvWarpCanvasGroundOverride } ?? bundle.canvasClearColor
        let canvasClear = MTLClearColor(red: cc.x, green: cc.y, blue: cc.z, alpha: cc.w)
        clearWarpTextures([warpTex, composeTex, sceneTex], to: canvasClear)

        // Fata Morgana (D-139): the blur-of-prev target at 1/4 RESOLUTION — butterchurn's
        // blur1 is a downsampled separable gaussian (blurRatios ~0.25), and the
        // downsample + the warp's bilinear read are what make it a WIDE low-pass (which
        // drives the warp's coherent large-scale smearing of the blobs into ribbons). A
        // full-res blur was too narrow (blobs stayed discrete particles).
        // Glaze (GLAZE.2b.1): a 3-level pyramid (½ + ¼ + ⅛ res) — the resolution halving
        // widens the per-level gaussian for the multi-scale gel sheen (warp uses blur1+2,
        // comp uses blur1+2+3). FM: a single ¼-res blur. Others: none.
        func mk(_ div: Int) -> MTLTexture? {
            makeWarpTexture(width: max(width / div, 1), height: max(height / div, 1), format: bundle.feedbackFormat)
        }
        let blurTex  = bundle.isGlaze ? mk(4) : (bundle.blurState != nil ? mk(4) : nil)
        let blurTex2 = bundle.isGlaze ? mk(8) : nil
        let blurTex3 = bundle.isGlaze ? mk(16) : nil
        // The blur intermediates always start black — they are not the canvas ground.
        let blurClear = [blurTex, blurTex2, blurTex3].compactMap { $0 }
        if !blurClear.isEmpty { clearWarpTextures(blurClear, to: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)) }

        let state = MVWarpState(
            warpTexture: warpTex,
            composeTexture: composeTex,
            sceneTexture: sceneTex,
            warpPipeline: bundle.warpState,
            composePipeline: bundle.composeState,
            blitPipeline: bundle.blitState,
            pixelFormat: bundle.pixelFormat,
            feedbackFormat: bundle.feedbackFormat,
            blurPipeline: bundle.blurState,
            blurTexture: blurTex,
            blurTexture2: blurTex2,
            blurTexture3: blurTex3,
            isNacre: bundle.isNacre,
            isFloret: bundle.isFloret,
            isGlaze: bundle.isGlaze,
            canvasClearColor: bundle.canvasClearColor
        )
        mvWarpLock.withLock { mvWarpState = state }
        mvWarpLogger.info("mv_warp textures allocated: \(width)×\(height), format=\(bundle.pixelFormat.rawValue)")
    }

    /// Clear each mv_warp texture to `clearColor` via load-action-clear render passes so
    /// first-frame compose reads the intended ground, not undefined GPU memory.
    /// (Skein.ENGINE.1.1 / D-143: was `clearWarpTexturesToBlack`; the colour is now
    /// per-preset — black for every preset except marks-on-top canvas-hold presets.)
    private func clearWarpTextures(_ textures: [MTLTexture], to clearColor: MTLClearColor) {
        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else { return }
        for tex in textures {
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture     = tex
            desc.colorAttachments[0].loadAction  = .clear
            desc.colorAttachments[0].clearColor  = clearColor
            desc.colorAttachments[0].storeAction = .store
            if let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: desc) { encoder.endEncoding() }
        }
        cmdBuf.commit()
    }

    /// Reallocate the mv_warp textures at a new drawable size (called from `drawableSizeWillChange`).
    /// No-op if no mv_warp state is active.
    public func reallocateMVWarpTextures(size: CGSize) {
        guard let existing = mvWarpLock.withLock({ mvWarpState }) else { return }
        let bundle = MVWarpPipelineBundle(
            warpState: existing.warpPipeline,
            composeState: existing.composePipeline,
            blitState: existing.blitPipeline,
            pixelFormat: existing.pixelFormat,
            feedbackFormat: existing.feedbackFormat,
            blurState: existing.blurPipeline,
            isNacre: existing.isNacre,
            isFloret: existing.isFloret,
            isGlaze: existing.isGlaze,
            canvasClearColor: existing.canvasClearColor   // resize re-clears to the same ground (D-143)
        )
        setupMVWarp(bundle: bundle, size: size)
    }

    /// Detach mv_warp state. Call from `applyPreset` reset block.
    public func clearMVWarpState() {
        mvWarpLock.withLock { mvWarpState = nil }
    }

    /// Wipe the mv_warp canvas back to the preset's ground colour (Skein.3 §1.5 track-change
    /// reset: the held canvas-hold painting is the PREVIOUS track's fingerprint, so a new track
    /// starts on fresh cream). Lightweight — re-clears the existing textures, no reallocation.
    /// No-op when no mv_warp state is active. Called only for canvas-hold presets (Skein) on
    /// track change; every decay-based mv_warp preset (Dragon Bloom / Fata Morgana) never calls
    /// it, so their cross-track feedback is unchanged.
    public func clearMVWarpCanvasToGround() {
        guard let state = mvWarpLock.withLock({ mvWarpState }) else { return }
        // Skein.5.3b: the per-track ground override (set from SkeinState's palette pick on
        // track change, BEFORE this wipe) wins over the preset-static colour.
        let cc = mvWarpLock.withLock { mvWarpCanvasGroundOverride } ?? state.canvasClearColor
        let ground = MTLClearColor(red: cc.x, green: cc.y, blue: cc.z, alpha: cc.w)
        var textures = [state.warpTexture, state.composeTexture, state.sceneTexture]
        if let blur = state.blurTexture { textures.append(blur) }
        clearWarpTextures(textures, to: ground)
    }

    /// Set the decay value used by the mv_warp compose pass.
    ///
    /// Must match the `pf.decay` returned by the preset's `mvWarpPerFrame` shader function.
    /// Call this from `applyPreset` alongside `setupMVWarp` so the compose blend equation
    /// `Σ(1−d)×d^n = 1` holds and the scene converges to 1× brightness at steady state.
    public func setMVWarpDecay(_ decay: Float) {
        mvWarpLock.withLock { mvWarpDecay = decay }
    }

    // MARK: Texture Helper

    private func makeWarpTexture(width: Int, height: Int, format: MTLPixelFormat) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return context.device.makeTexture(descriptor: desc)
    }

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
