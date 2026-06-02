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

    public init(
        warpState: MTLRenderPipelineState,
        composeState: MTLRenderPipelineState,
        blitState: MTLRenderPipelineState,
        pixelFormat: MTLPixelFormat,
        feedbackFormat: MTLPixelFormat? = nil,
        blurState: MTLRenderPipelineState? = nil
    ) {
        self.warpState    = warpState
        self.composeState = composeState
        self.blitState    = blitState
        self.pixelFormat  = pixelFormat
        self.feedbackFormat = feedbackFormat ?? pixelFormat
        self.blurState    = blurState
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
}
