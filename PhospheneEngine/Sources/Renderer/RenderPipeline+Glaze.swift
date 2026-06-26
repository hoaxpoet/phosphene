// RenderPipeline+Glaze — the Glaze mv_warp draw branch (GLAZE.2a).
//
// Port of the butterchurn builtin `Flexi + stahlregen - jelly showoff parade` (cream-of-
// crop legends; the glossy "wet jelly" contour-gel). Dedicated branch mirroring Nacre /
// Fata Morgana. Per frame — the Nacre structure (no blur target in 2a; the source's
// 3-level blur pyramid + its emboss/sheen consumer land together in GLAZE.2b):
//
//   warp(prev, u) → composeTexture   (custom feedback warp; bakes its own decay + seed)
//   comp(compose, u) → target        (the display look; DISPLAY-only, never fed back)
//   swap warpTexture ↔ composeTexture
//
// GLAZE.2a (THIS) wires the branch with STUB shaders (see Glaze.metal) — proves the live
// dispatch + test harness end to end. GLAZE.2b fills the faithful spring-physics warp
// center + blur-pyramid gel sheen; the greenlit uplifts (A/B/C) are GLAZE.5+ (FA #65).

import Metal
@preconcurrency import MetalKit
import Shared

// MARK: - GlazeUniforms (matches `struct GlazeUniforms` in Glaze.metal)

/// 32-byte uniform bound at fragment buffer(1) of the warp + comp passes.
/// Layout: time/coreEnergy fill the first 8 bytes, texel the next 8, then the
/// 16-aligned aspect SIMD4 — byte-identical to the MSL struct.
struct GlazeUniforms {
    var time: Float = 0
    var coreEnergy: Float = 0      // STEADY total energy → gates the warp seed (no smear)
    var texel: SIMD2<Float> = .init(1, 1)
    var aspect: SIMD4<Float> = .init(1, 1, 1, 1)
}

extension RenderPipeline {

    // MARK: Per-frame uniforms

    /// Compute the Glaze warp/comp uniforms for this frame. Holds the `glazeSeedEMA`
    /// smoothing accumulator (the seed's total-energy envelope). GLAZE.2b+ extends this
    /// with the spring-physics state (anchor ← per-stem audio; 3 masses; tail pos/speed).
    @MainActor
    func computeGlazeUniforms(features: FeatureVector, stems: StemFeatures) -> GlazeUniforms {
        var uni = GlazeUniforms()
        uni.time = features.time

        // Seed ← STEADY total energy (~0.5 s EMA): faithful modwavealphabyvolume + the
        // musical role (the field is alive at silence via the seed's floor, brighter with
        // audio). Steady (not transient) so the fed-back seed never flares into smears.
        let total = max(0, (features.bass + features.mid + features.treble) / 3.0)
        glazeSeedEMA += (total - glazeSeedEMA) * 0.03
        uni.coreEnergy = glazeSeedEMA

        let size = mvWarpDrawableSize
        let wPx = max(Float(size.width), 1), hPx = max(Float(size.height), 1)
        uni.texel = SIMD2<Float>(1.0 / wPx, 1.0 / hPx)
        // butterchurn aspect: the LONGER axis is normalised to 1, the shorter carries the
        // ratio — keeps the contour field round on a wide canvas.
        let aspectX: Float = wPx >= hPx ? hPx / wPx : 1
        let aspectY: Float = hPx > wPx ? wPx / hPx : 1
        uni.aspect = SIMD4<Float>(aspectX, aspectY, 1.0 / aspectX, 1.0 / aspectY)
        return uni
    }

    // MARK: Draw branch

    /// Live entry point: render the Glaze frame to the drawable, then present. Thin wrapper
    /// over `renderGlaze(target:)` so the live path and the diag harness run the EXACT SAME
    /// render code (FA #66 — no reimplemented test path).
    @MainActor
    func drawWithGlaze(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        warpState: MVWarpState
    ) {
        guard let drawable = view.currentDrawable else { return }
        renderGlaze(
            commandBuffer: commandBuffer,
            features: features,
            stemFeatures: stemFeatures,
            warpState: warpState,
            target: drawable.texture)
        commandBuffer.present(drawable)
    }

    /// Glaze feedback loop rendered into `target`: warp → display comp (→ target) → swap.
    /// Target-agnostic so the live drawable path and the offscreen diag both call it
    /// identically (FA #66).
    @MainActor
    func renderGlaze(
        commandBuffer: MTLCommandBuffer,
        features: FeatureVector,
        stemFeatures: StemFeatures,
        warpState: MVWarpState,
        target: MTLTexture
    ) {
        var uni = computeGlazeUniforms(features: features, stems: stemFeatures)

        // ── Warp pass: warp(prev, u) → composeTexture ─────────────────────────
        let wdesc = MTLRenderPassDescriptor()
        wdesc.colorAttachments[0].texture = warpState.composeTexture
        wdesc.colorAttachments[0].loadAction = .clear
        wdesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        wdesc.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: wdesc) {
            enc.setRenderPipelineState(warpState.warpPipeline)
            var feat = features
            enc.setVertexBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 0)
            var stm = stemFeatures
            enc.setVertexBytes(&stm, length: MemoryLayout<StemFeatures>.stride, index: 1)
            var scene = getSceneUniforms()
            enc.setVertexBytes(&scene, length: MemoryLayout<SceneUniforms>.stride, index: 2)
            enc.setFragmentTexture(warpState.warpTexture, index: 0)
            enc.setFragmentBytes(&uni, length: MemoryLayout<GlazeUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)  // 31×23 quads
            enc.endEncoding()
        }

        // ── Comp blit: display(compose, u) → target (display-only) ────────────
        let cdesc = MTLRenderPassDescriptor()
        cdesc.colorAttachments[0].texture     = target
        cdesc.colorAttachments[0].loadAction  = .dontCare
        cdesc.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: cdesc) {
            enc.setRenderPipelineState(warpState.blitPipeline)
            enc.setFragmentTexture(warpState.composeTexture, index: 0)
            enc.setFragmentBytes(&uni, length: MemoryLayout<GlazeUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        // ── Swap: composeTexture becomes next frame's warpTexture ─────────────
        mvWarpLock.withLock {
            guard var state = mvWarpState else { return }
            swap(&state.warpTexture, &state.composeTexture)
            mvWarpState = state
        }
    }

    /// Reduced-motion (U.9 / a11y) Glaze frame into `target`: the display comp of the
    /// CURRENT (un-advanced) feedback — NO warp pass, NO swap → no accumulation, no motion.
    /// Mirrors `renderNacreReducedMotion` (BUG-061): Glaze's direct pipeline is compiled for
    /// `.rgba16Float`, so routing reduced-motion through the drawable-format comp pipeline is
    /// both crash-safe and the correct "static frame" the U.9 contract wants.
    @MainActor
    func renderGlazeReducedMotion(
        commandBuffer: MTLCommandBuffer,
        features: FeatureVector,
        warpState: MVWarpState,
        target: MTLTexture
    ) {
        var uni = computeGlazeUniforms(features: features, stems: .zero)
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = target
        desc.colorAttachments[0].loadAction  = .dontCare
        desc.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        enc.setRenderPipelineState(warpState.blitPipeline)        // glaze_comp (drawable format)
        enc.setFragmentTexture(warpState.warpTexture, index: 0)   // current feedback, NOT advanced
        enc.setFragmentBytes(&uni, length: MemoryLayout<GlazeUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }
}
