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
    /// Pixel format for all three mv_warp textures (matches the drawable).
    public let pixelFormat: MTLPixelFormat

    public init(
        warpState: MTLRenderPipelineState,
        composeState: MTLRenderPipelineState,
        blitState: MTLRenderPipelineState,
        pixelFormat: MTLPixelFormat
    ) {
        self.warpState    = warpState
        self.composeState = composeState
        self.blitState    = blitState
        self.pixelFormat  = pixelFormat
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

        guard let warpTex    = makeWarpTexture(width: width, height: height, format: bundle.pixelFormat),
              let composeTex = makeWarpTexture(width: width, height: height, format: bundle.pixelFormat),
              let sceneTex   = makeWarpTexture(width: width, height: height, format: bundle.pixelFormat)
        else {
            mvWarpLogger.error("Failed to allocate mv_warp textures at \(width)×\(height)")
            return
        }

        let state = MVWarpState(
            warpTexture: warpTex,
            composeTexture: composeTex,
            sceneTexture: sceneTex,
            warpPipeline: bundle.warpState,
            composePipeline: bundle.composeState,
            blitPipeline: bundle.blitState,
            pixelFormat: bundle.pixelFormat
        )
        mvWarpLock.withLock { mvWarpState = state }
        mvWarpLogger.info("mv_warp textures allocated: \(width)×\(height), format=\(bundle.pixelFormat.rawValue)")
    }

    /// Reallocate the mv_warp textures at a new drawable size (called from `drawableSizeWillChange`).
    /// No-op if no mv_warp state is active.
    public func reallocateMVWarpTextures(size: CGSize) {
        guard let existing = mvWarpLock.withLock({ mvWarpState }) else { return }
        let bundle = MVWarpPipelineBundle(
            warpState: existing.warpPipeline,
            composeState: existing.composePipeline,
            blitState: existing.blitPipeline,
            pixelFormat: existing.pixelFormat
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

        // ── Pass 0: Scene render (direct-render presets only) ─────────────────
        // For ray-march presets the scene is already in warpState.sceneTexture;
        // drawWithRayMarch renders to that texture when mv_warp is active.
        if !sceneAlreadyRendered {
            renderSceneToTexture(
                commandBuffer: commandBuffer,
                features: &features,
                stemFeatures: stemFeatures,
                activePipeline: activePipeline,
                target: warpState.sceneTexture
            )
        }

        // ── Pass 1: Warp pass → Pass 2: Compose pass ─────────────────────────
        var currentDecay: Float = 0.96
        encodeMVWarpPass(
            commandBuffer: commandBuffer,
            features: &features,
            stemFeatures: stemFeatures,
            warpState: warpState
        )
        currentDecay = mvWarpLock.withLock { mvWarpDecay }

        // ── Pass 2: Compose pass ──────────────────────────────────────────────
        // Fullscreen quad. mvWarp_compose_fragment alpha-blends the scene onto
        // the decay-warped composeTexture using sourceAlpha × src + one × dst.
        // Steady state: sum(n=0..∞, (1-decay) × decay^n) = 1.0 × scene.
        do {
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture     = warpState.composeTexture
            desc.colorAttachments[0].loadAction  = .load   // keep warp result
            desc.colorAttachments[0].storeAction = .store

            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) {
                encoder.setRenderPipelineState(warpState.composePipeline)
                encoder.setFragmentTexture(warpState.sceneTexture, index: 0)
                encoder.setFragmentBytes(&currentDecay, length: MemoryLayout<Float>.stride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
            }
        }

        // ── Pass 3: Blit to drawable ─────────────────────────────────────────
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }
        // .dontCare is correct — the full-screen triangle overwrites every pixel.
        descriptor.colorAttachments[0].loadAction  = .dontCare
        descriptor.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encoder.setRenderPipelineState(warpState.blitPipeline)
            encoder.setFragmentTexture(warpState.composeTexture, index: 0)
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
        // 31×23 quads × 2 triangles × 3 vertices = 4278 vertices
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)
        encoder.endEncoding()
    }

    // MARK: Scene → Texture (direct-render presets)

    /// Render the preset's direct fragment shader to an offscreen texture.
    /// Used for non-ray-march presets (e.g. Starburst) with `.mvWarp` in their passes.
    private func renderSceneToTexture(
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

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else {
            return
        }
        encoder.setRenderPipelineState(activePipeline)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        encoder.setFragmentBuffer(fftMagnitudeBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
        var stems = stemFeatures
        encoder.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.stride, index: 3)
        // Bind optional per-preset fragment data at buffer(6) (e.g. GossamerState wave pool).
        if let presetBuf = directPresetFragmentBufferLock.withLock({ directPresetFragmentBuffer }) {
            encoder.setFragmentBuffer(presetBuf, offset: 0, index: 6)
        }
        // Bind optional secondary per-preset fragment data at buffer(7) (e.g. ArachneSpiderGPU).
        if let presetBuf2 = directPresetFragmentBuffer2Lock.withLock({ directPresetFragmentBuffer2 }) {
            encoder.setFragmentBuffer(presetBuf2, offset: 0, index: 7)
        }
        // Bind optional tertiary per-preset fragment data at buffer(8) (D-LM-buffer-slot-8).
        if let presetBuf3 = directPresetFragmentBuffer3Lock.withLock({ directPresetFragmentBuffer3 }) {
            encoder.setFragmentBuffer(presetBuf3, offset: 0, index: 8)
        }
        // Bind optional quaternary per-preset fragment data at buffer(9) (V.9 Session 3 / D-125).
        if let presetBuf4 = directPresetFragmentBuffer4Lock.withLock({ directPresetFragmentBuffer4 }) {
            encoder.setFragmentBuffer(presetBuf4, offset: 0, index: 9)
        }
        bindNoiseTextures(to: encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // MARK: Helpers

    /// Extract the current SceneUniforms from the attached ray march pipeline (if any).
    /// Falls back to a zeroed struct for direct-render presets.
    private func getSceneUniforms() -> SceneUniforms {
        return rayMarchLock.withLock { rayMarchPipeline?.sceneUniforms } ?? SceneUniforms()
    }
}
