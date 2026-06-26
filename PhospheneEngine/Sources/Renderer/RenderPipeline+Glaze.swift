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

/// 32-byte uniform bound at fragment buffer(1) of the warp + comp passes — byte-identical
/// to the MSL `GlazeUniforms` (time/coreEnergy/pokeStrength/pad0 | texel | pokeCenter).
struct GlazeUniforms {
    var time: Float = 0
    var coreEnergy: Float = 0       // reserved (silence-floor lever; the faithful warp self-seeds)
    var pokeStrength: Float = 0     // spring mass-3 x → the pixel-eq poke scale (`q3`)
    var seedY: Float = 0.5          // spring tail Y position → the seed band's vertical centre (GLAZE.3b)
    var texel: SIMD2<Float> = .init(1, 1)
    var pokeCenter: SIMD2<Float> = .init(0.5, 0.5)   // spring tail (cx1, cy1) — the poke centre
}

/// The source's 3-mass damped spring chain (frame_eqs), stepped CPU-side each frame. Masses
/// 2/3/4 hang off a driven anchor (mass 1); the free tail (mass 4) position + speed and mass-3
/// x drive the swirl-poke. Faithful constants (spring 18, grav 1, resist 5, bounce .9, dt .0003).
struct GlazeSpring {
    var x2: Float = 0, y2: Float = 0, vx2: Float = 0, vy2: Float = 0
    var x3: Float = 0, y3: Float = 0, vx3: Float = 0, vy3: Float = 0
    var x4: Float = 0, y4: Float = 0, vx4: Float = 0, vy4: Float = 0
    /// Anchor-drive envelopes (GLAZE.3a; source frame_eqs xx1/xx2/yy1): bass/treble DEVIATION
    /// accents → opposite directions of the lateral anchor swing; sustained Rel energy → lift.
    /// Resetting the struct zeroes these too (the test relies on that).
    var bassEMA: Float = 0, trebEMA: Float = 0, liftEMA: Float = 0

    mutating func step(anchorX x1: Float, anchorY y1: Float) {
        let spring: Float = 18, grav: Float = 1, dt: Float = 0.0003, bounce: Float = 0.9
        let damp: Float = 1 - 5 * dt   // resist = 5
        vx2 = vx2 * damp + dt * (x1 + x3 - 2 * x2) * spring
        vy2 = vy2 * damp + dt * ((y1 + y3 - 2 * y2) * spring - grav)
        vx3 = vx3 * damp + dt * (x2 + x4 - 2 * x3) * spring
        vy3 = vy3 * damp + dt * ((y2 + y4 - 2 * y3) * spring - grav)
        vx4 = vx4 * damp + dt * (x3 - x4) * spring
        vy4 = vy4 * damp + dt * ((y3 - y4) * spring - grav)
        x2 += vx2; y2 += vy2; x3 += vx3; y3 += vy3; x4 += vx4; y4 += vy4
        wall(&x2, &vx2, bounce); wall(&y2, &vy2, bounce)
        wall(&x3, &vx3, bounce); wall(&y3, &vy3, bounce)
        wall(&x4, &vx4, bounce); wall(&y4, &vy4, bounce)
    }

    /// Reflect velocity off the [0,1] walls (source `above`/`below` bounce guards).
    private func wall(_ pos: inout Float, _ vel: inout Float, _ bnc: Float) {
        if pos <= 0 { vel = abs(vel) * bnc } else if pos >= 1 { vel = -abs(vel) * bnc }
    }
}

// MARK: - GLAZE.3a audio-anchor gains (M7 render-tune levers)

/// Lateral anchor swing per unit of (bassDev − trebDev) envelope — the source's `x1` gain `1.5`.
private let kGlazeSwing: Float = 1.5
/// Anchor lift per unit of the sustained (bassRel + trebRel) envelope — the source's `y1` energy push.
private let kGlazeLift: Float = 1.2

extension RenderPipeline {

    // MARK: Per-frame uniforms

    /// Compute the Glaze warp/comp uniforms for this frame. Steps the 3-mass spring off an
    /// audio-driven anchor (GLAZE.3a — bass/treble deviation → lateral swing, energy → lift;
    /// the `glaze*EMA` accumulators are the source's xx1/xx2/yy1 envelopes). Per-stem routing
    /// into the anchor is the greenlit uplift A (GLAZE.5), not here.
    @MainActor
    func computeGlazeUniforms(features: FeatureVector, stems: StemFeatures) -> GlazeUniforms {
        var uni = GlazeUniforms()
        let tSec = features.time
        uni.time = tSec

        // Spring anchor (source frame_eqs x1/y1) — AUDIO-DRIVEN (GLAZE.3a, §6 routing table).
        // Bass yanks the anchor right, treble flicks it left (lateral swing); sustained energy
        // lifts it. EMA envelopes off the DEVIATION primitives (D-026 / FA #31 — never absolute
        // AGC energy), so the spring integrates spiky onsets into smooth organic momentum (the
        // FA #4/#31 "no primary motion from raw onsets" failure sidestepped by construction).
        // A small time idle keeps the anchor roaming at silence so the field stays alive (D-019).
        // One physical input (FA #67): bass/treble are opposite directions of the SAME anchor
        // axis, energy is the other axis — no two visual layers share a primitive at a timescale.
        glazeSpring.bassEMA = 0.9 * glazeSpring.bassEMA + 0.1 * features.bassDev
        glazeSpring.trebEMA = 0.9 * glazeSpring.trebEMA + 0.1 * features.trebDev
        glazeSpring.liftEMA = 0.94 * glazeSpring.liftEMA + 0.06 * max(0, features.bassRel + features.trebRel) * 0.5
        // ponytail: kGlazeSwing/kGlazeLift are the render-tune levers (M7); start at the source's
        // 1.5 lateral gain + a gentle lift, adjust by render-compare against the oracle.
        let anchorX = 0.5 + 0.10 * sin(tSec * 0.37) + kGlazeSwing * (glazeSpring.bassEMA - glazeSpring.trebEMA)
        let anchorY = 0.5 + 0.08 * sin(tSec * 0.53) + kGlazeLift * glazeSpring.liftEMA
        glazeSpring.step(anchorX: anchorX, anchorY: anchorY)
        // Source pixel_eqs: poke centre = (mass-4 x, tail SPEED), poke scale = mass-3 x.
        let tailSpeed = (glazeSpring.vx4 * glazeSpring.vx4 + glazeSpring.vy4 * glazeSpring.vy4).squareRoot()
        uni.pokeCenter = SIMD2<Float>(glazeSpring.x4, tailSpeed)
        uni.pokeStrength = glazeSpring.x3
        // GLAZE.3b: the seed band rides the jelly's vertical position — as the audio-driven tail
        // sweeps up/down (full [0,1] range on real music), the bright seed paints the whole frame
        // and the zoom accretes it into the nested field (band-only when the tail idles at silence).
        uni.seedY = glazeSpring.y4

        let size = mvWarpDrawableSize
        uni.texel = SIMD2<Float>(1.0 / max(Float(size.width), 1), 1.0 / max(Float(size.height), 1))
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

        // ── Blur pyramid (GLAZE.2b.1): prev → blur1 → blur2 → blur3 (progressive
        // downsample; FM's blur-of-prev pattern). Both warp and comp sample these — a
        // 1-frame blur lag vs the current warp output, visually negligible on a coherent
        // feedback field. Skipped if the pyramid isn't allocated (defensive).
        if let blurPipe = warpState.blurPipeline,
           let b1 = warpState.blurTexture, let b2 = warpState.blurTexture2, let b3 = warpState.blurTexture3 {
            encodeGlazeBlur(commandBuffer, blurPipe, src: warpState.warpTexture, dst: b1)
            encodeGlazeBlur(commandBuffer, blurPipe, src: b1, dst: b2)
            encodeGlazeBlur(commandBuffer, blurPipe, src: b2, dst: b3)
        }

        // ── Warp pass: warp(prev, blur1/2, u) → composeTexture ────────────────
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
            enc.setFragmentTexture(warpState.blurTexture, index: 1)
            enc.setFragmentTexture(warpState.blurTexture2, index: 2)
            enc.setFragmentBytes(&uni, length: MemoryLayout<GlazeUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)  // 31×23 quads
            enc.endEncoding()
        }

        // ── Comp blit: display(compose, blur1/2/3, u) → target (display-only) ──
        let cdesc = MTLRenderPassDescriptor()
        cdesc.colorAttachments[0].texture     = target
        cdesc.colorAttachments[0].loadAction  = .dontCare
        cdesc.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: cdesc) {
            enc.setRenderPipelineState(warpState.blitPipeline)
            enc.setFragmentTexture(warpState.composeTexture, index: 0)
            enc.setFragmentTexture(warpState.blurTexture, index: 1)
            enc.setFragmentTexture(warpState.blurTexture2, index: 2)
            enc.setFragmentTexture(warpState.blurTexture3, index: 3)
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

    /// One blur-pyramid pass: a fullscreen `glaze_blur_fragment` of `src` into the
    /// (smaller) `dst`. Run progressively (prev→1→2→3) by `renderGlaze`.
    @MainActor
    private func encodeGlazeBlur(_ commandBuffer: MTLCommandBuffer, _ pipeline: MTLRenderPipelineState,
                                 src: MTLTexture, dst: MTLTexture) {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = dst
        desc.colorAttachments[0].loadAction = .dontCare
        desc.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(src, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
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
