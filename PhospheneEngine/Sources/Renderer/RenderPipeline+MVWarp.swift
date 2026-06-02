// RenderPipeline+MVWarp — Milkdrop-style per-vertex feedback warp pass (MV-2, D-027).
//
// `drawWithMVWarp` is called from `renderFrame` after the scene has been rendered
// to `mvWarpState.sceneTexture` by a preceding pass (`.rayMarch` + optional
// `.postProcess`), or — for direct-render presets like Starburst — it renders
// the preset fragment to `sceneTexture` itself before applying the warp.
//
// Three-pass rendering per frame:
//   1. Warp pass   — 32×24 vertex grid warps `warpTexture` (previous frame) at
//                    per-vertex displaced UVs × decay → `composeTexture`
//   2. Compose pass— fullscreen quad, scene alpha-blended onto `composeTexture`
//   3. Blit pass   — `composeTexture` → drawable; swap warp ↔ compose

import Metal
@preconcurrency import MetalKit
import Shared
import os.log

private let mvWarpLogger = Logger(subsystem: "com.phosphene.renderer", category: "MVWarp")

// MARK: - MVWarpPipelineBundle

/// The three per-preset compiled pipeline states needed for the mv_warp pass.
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

    public init(
        warpState: MTLRenderPipelineState,
        composeState: MTLRenderPipelineState,
        blitState: MTLRenderPipelineState,
        pixelFormat: MTLPixelFormat,
        feedbackFormat: MTLPixelFormat? = nil
    ) {
        self.warpState    = warpState
        self.composeState = composeState
        self.blitState    = blitState
        self.pixelFormat  = pixelFormat
        self.feedbackFormat = feedbackFormat ?? pixelFormat
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
}

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

        // AV.2.1: clear freshly-allocated textures to black. storageMode =
        // .private GPU memory is NOT guaranteed zero-initialised — without
        // this, the first post-preset-switch frame can read whatever bit
        // pattern previously occupied that memory (live AV.2 session read
        // as full-screen magenta for ~1 s after preset switch).
        clearWarpTexturesToBlack(warpTex: warpTex,
                                 composeTex: composeTex,
                                 sceneTex: sceneTex)

        let state = MVWarpState(
            warpTexture: warpTex,
            composeTexture: composeTex,
            sceneTexture: sceneTex,
            warpPipeline: bundle.warpState,
            composePipeline: bundle.composeState,
            blitPipeline: bundle.blitState,
            pixelFormat: bundle.pixelFormat,
            feedbackFormat: bundle.feedbackFormat
        )
        mvWarpLock.withLock { mvWarpState = state }
        mvWarpLogger.info("mv_warp textures allocated: \(width)×\(height), format=\(bundle.pixelFormat.rawValue)")
    }

    /// Clear each mv_warp texture to black via load-action-clear render
    /// passes so first-frame compose reads black, not undefined GPU memory.
    private func clearWarpTexturesToBlack(warpTex: MTLTexture, composeTex: MTLTexture, sceneTex: MTLTexture) {
        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else { return }
        for tex in [warpTex, composeTex, sceneTex] {
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture     = tex
            desc.colorAttachments[0].loadAction  = .clear
            desc.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
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
            feedbackFormat: existing.feedbackFormat
        )
        setupMVWarp(bundle: bundle, size: size)
    }

    /// Detach mv_warp state. Call from `applyPreset` reset block.
    public func clearMVWarpState() {
        mvWarpLock.withLock { mvWarpState = nil }
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

        // Dragon Bloom (D-137): when a scene-geometry overlay (the strands) is
        // attached, replicate butterchurn's custom-warp loop exactly — warp the
        // previous frame (NO decay; the custom warp self-regulates) then draw the
        // waves NORMAL-ALPHA directly ON TOP of the warp result; that IS the
        // feedback (comp/echo/invert is display-only at blit). No separate scene
        // texture, no decayed compose. Other presets keep the scene+decayed-compose.
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

        // ── Pass 3: Blit to drawable ─────────────────────────────────────────
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }
        // .dontCare is correct — the full-screen triangle overwrites every pixel.
        descriptor.colorAttachments[0].loadAction  = .dontCare
        descriptor.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encoder.setRenderPipelineState(warpState.blitPipeline)
            encoder.setFragmentTexture(warpState.composeTexture, index: 0)
            // Beat pulse (Dragon Bloom only): a crisp per-beat pump+brighten at the
            // comp/display stage (not fed back). beatComposite (shaped to its strong
            // peaks) OR the drums-stem kick transient — whichever is bigger — so it
            // dances on the beat across genres. Other presets get 0 (identity).
            let beat = strandsOnTop ? mvWarpBeatPulse(features: features, stems: stemFeatures) : 0
            var post = mvWarpLock.withLock {
                SIMD4<Float>(mvWarpInvert, mvWarpEcho, mvWarpGamma, beat)
            }
            encoder.setFragmentBytes(&post, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)

        // ── Swap: composeTexture becomes next frame's warpTexture ─────────────
        mvWarpLock.withLock {
            guard var state = mvWarpState else { return }
            swap(&state.warpTexture, &state.composeTexture)
            mvWarpState = state
        }
    }
    // swiftlint:enable function_parameter_count

    // MARK: Reduced-Motion Fallback (U.9)

    /// Single-frame render when `frameReduceMotion` is true — skips feedback accumulation.
    @MainActor
    // swiftlint:disable:next function_parameter_count
    private func drawMVWarpReducedMotion(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        activePipeline: MTLRenderPipelineState,
        warpState: MVWarpState,
        sceneAlreadyRendered: Bool
    ) {
        guard let drawable = view.currentDrawable else { return }
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
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }
        commandBuffer.present(drawable)
    }

    // MARK: - Warp Pass Encoder

    /// Encodes the 32×24 vertex-grid warp pass to `warpState.composeTexture`.
    @MainActor
    private func encodeMVWarpPass(
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
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)  // 31×23 quads
        encoder.endEncoding()
    }

    // MARK: Helpers

    /// Extract the current SceneUniforms from the attached ray march pipeline (if any).
    /// Falls back to a zeroed struct for direct-render presets.
    func getSceneUniforms() -> SceneUniforms {
        return rayMarchLock.withLock { rayMarchPipeline?.sceneUniforms } ?? SceneUniforms()
    }
}
