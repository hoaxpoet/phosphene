// MVWarpTypes — value types for the Milkdrop-style mv_warp feedback pass (MV-2,
// D-027). Split out of RenderPipeline+MVWarp.swift for file length. The draw path,
// setup, and pass encoders live in RenderPipeline+MVWarp.swift; the Fata Morgana
// branch (D-139) in RenderPipeline+FataMorgana.swift.

import Metal

// MARK: - MVWarpPipelineBundle

/// The per-preset compiled pipeline states needed for the mv_warp pass.
///
/// Created in `VisualizerEngine+Presets.swift` by combining the pipeline states
/// compiled by `PresetLoader` (which has the preset's `mvWarpPerFrame`/`mvWarpPerVertex`
/// implementations) with the pixel format of the current drawable.
public struct MVWarpPipelineBundle: Sendable {
    public let warpState: MTLRenderPipelineState    // mvWarp_vertex + mvWarp_fragment
    public let composeState: MTLRenderPipelineState // fullscreen_vertex + mvWarp_compose_fragment
    public let blitState: MTLRenderPipelineState    // fullscreen_vertex + mvWarp_blit_fragment
    /// Drawable pixel format (the blit pass renders to this).
    public let pixelFormat: MTLPixelFormat
    /// Pixel format for the three FEEDBACK textures (warp / compose / scene).
    /// Usually equals `pixelFormat`; `.rgba16Float` for HDR-feedback presets
    /// (Dragon Bloom, D-137) so colour/saturation survives the feedback loop and
    /// additive scene injection isn't clamped at 1.0.
    public let feedbackFormat: MTLPixelFormat
    /// Optional blur-of-prev pipeline (Fata Morgana, D-139). When present, the draw
    /// path runs the fata branch: blur(prev) → custom warp → shapes-on-top → custom
    /// mirage comp → swap. nil ⇒ the standard Dragon-Bloom/default mv_warp path.
    public let blurState: MTLRenderPipelineState?
    /// Nacre (NACRE.2b): routes the draw path to the nacre branch (custom warp → custom
    /// signature comp → swap; the seed is folded into the warp). Keyed on the preset
    /// name at bundle build — Nacre and Fata Morgana would both otherwise match the
    /// blur heuristic, so this disambiguates. false for every other mv_warp preset.
    public let isNacre: Bool
    /// Glaze (GLAZE.2a): routes the draw path to the glaze branch (custom warp → display
    /// comp → swap). Like Nacre, keyed on the preset name at bundle build (Glaze also uses
    /// `.rgba16Float` feedback; in 2b it adds the blur pyramid, so this disambiguates it
    /// from the Fata Morgana blur heuristic). false for every other mv_warp preset.
    public let isGlaze: Bool
    /// Initial clear colour for the three feedback textures (Skein.ENGINE.1.1, D-143).
    /// On the marks-on-top path the background fragment (Pass 0) is skipped, so this is
    /// the held GROUND the marks sit on (Skein's cream). Stored as RGBA components
    /// (Sendable) and converted to `MTLClearColor` at the clear site. Defaults to opaque
    /// black — every existing mv_warp preset clears to black, byte-identical.
    public let canvasClearColor: SIMD4<Double>

    public init(
        warpState: MTLRenderPipelineState,
        composeState: MTLRenderPipelineState,
        blitState: MTLRenderPipelineState,
        pixelFormat: MTLPixelFormat,
        feedbackFormat: MTLPixelFormat? = nil,
        blurState: MTLRenderPipelineState? = nil,
        isNacre: Bool = false,
        isGlaze: Bool = false,
        canvasClearColor: SIMD4<Double> = SIMD4<Double>(0, 0, 0, 1)
    ) {
        self.warpState    = warpState
        self.composeState = composeState
        self.blitState    = blitState
        self.pixelFormat  = pixelFormat
        self.feedbackFormat = feedbackFormat ?? pixelFormat
        self.blurState    = blurState
        self.isNacre      = isNacre
        self.isGlaze      = isGlaze
        self.canvasClearColor = canvasClearColor
    }
}

// MARK: - MVWarpState

/// All Metal resources and pipeline states needed for one frame of mv_warp rendering.
///
/// Allocated in `setupMVWarp(bundle:size:)` and reallocated on drawable resize.
/// Stored behind `mvWarpLock` in `RenderPipeline`.
public struct MVWarpState: @unchecked Sendable {
    /// Previous frame's accumulated warp output (read source in warp pass).
    public var warpTexture: MTLTexture
    /// Current frame's working output (written by warp + compose; read by blit).
    public var composeTexture: MTLTexture
    /// Current scene render output (written by preceding ray march / direct pass;
    /// read in the compose pass to add the new frame's contribution).
    public var sceneTexture: MTLTexture

    // Pipeline states compiled per-preset from the preset's Metal library.
    public let warpPipeline: MTLRenderPipelineState    // mvWarp_vertex + mvWarp_fragment
    public let composePipeline: MTLRenderPipelineState // fullscreen_vertex + mvWarp_compose_fragment
    public let blitPipeline: MTLRenderPipelineState    // fullscreen_vertex + mvWarp_blit_fragment
    public let pixelFormat: MTLPixelFormat
    /// Feedback-texture format (float for HDR-feedback presets; else == pixelFormat).
    public let feedbackFormat: MTLPixelFormat
    /// Fata Morgana (D-139): blur-of-prev pipeline + its target texture. Non-nil ⇒
    /// the fata draw branch runs. nil for Dragon Bloom / default mv_warp presets.
    public let blurPipeline: MTLRenderPipelineState?
    public var blurTexture: MTLTexture?
    /// Nacre (NACRE.2b): routes `drawWithMVWarp` to the nacre branch. false otherwise.
    public var isNacre: Bool = false
    /// Glaze (GLAZE.2a): routes `drawWithMVWarp` to the glaze branch. false otherwise.
    public var isGlaze: Bool = false
    /// Initial feedback-texture clear colour (Skein.ENGINE.1.1, D-143), as RGBA
    /// components. Carried so `reallocateMVWarpTextures` (resize) re-clears to the same
    /// ground. (0,0,0,1) for every preset except marks-on-top canvas-hold presets
    /// (Skein's cream).
    public let canvasClearColor: SIMD4<Double>
}
