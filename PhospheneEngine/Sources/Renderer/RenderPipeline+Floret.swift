// RenderPipeline+Floret — the Floret mv_warp draw branch (FLORET.2a).
//
// Port of the butterchurn builtin `suksma - Rovastar - Sunflower Passion (Enlightment
// Mix)` render loop, on the Nacre/D-138 dedicated-branch structure (FA #70). Per frame:
//
//   warp(prev, u) → composeTexture       (custom feedback warp; bakes its own decay + seed)
//   comp(compose, u) → target            (the signature look; DISPLAY-only)
//   swap warpTexture ↔ composeTexture
//
// FloretUniforms carries the builtins the custom shaders reference (time, total-energy
// seed gate, feedback texel size + aspect). FLORET.2a is the WIRING STUB — the faithful
// warp/comp mechanic + audio routing land at FLORET.2b/.3 (FA #65). All time-driven /
// stateless for now (no CPU accumulators).

import Metal
@preconcurrency import MetalKit
import Shared

// MARK: - FloretUniforms (matches `struct FloretUniforms` in Floret.metal)

/// 32-byte uniform bound at fragment buffer(1) of the warp + comp passes.
/// 48-byte uniform. Layout: time/coreEnergy/swell/spin (16) · texel/barPush/pad0 (16) ·
/// aspect (16) — byte-identical to the MSL struct.
struct FloretUniforms {
    var time: Float = 0
    var coreEnergy: Float = 0          // total energy → the warp's volume-gated core seed
    var swell: Float = 0               // FLORET.3a: avg-stem envelope → bloom inflation (warp)
    var spin: Float = 0                // FLORET.3a: bass-accumulated rotation angle (rad) → comp spin
    var texel: SIMD2<Float> = .init(1, 1)
    var barPush: Float = 0             // FLORET.3a: downbeat envelope → comp camera magnify (beat-lock)
    var pad0: Float = 0
    var aspect: SIMD4<Float> = .init(1, 1, 1, 1)
}

// FLORET.3a motion-bundle tuning (Matt M7 "add movement"; grounded in the SOSB session).
// Energy swell tracks the song's arc on a ~0.5 s envelope (full-band-aware avg-stem, since raw
// mid/treble are dead on shoegaze). Spin accumulates a rotation from the bass deviation
// (soft-saturated — bassDev spikes to ~2.2×) + a faint base rate so the field is never frozen.
private let kFloretSwellSmooth: Float = 0.03      // ~0.5 s EMA at 60 fps
private let kFloretSpinBase: Float = 0.0015       // rad/frame floor (alive at silence)
private let kFloretSpinBassGain: Float = 0.020    // rad/frame added at full bass (matches kFloretSpinMax)

extension RenderPipeline {

    // MARK: Per-frame uniforms

    /// Compute the Floret warp/comp uniforms for this frame. FLORET.3a holds the motion-bundle
    /// accumulators (`floretSwellEMA`/`floretSpin`) — the audio routes Matt greenlit.
    @MainActor
    func computeFloretUniforms(features: FeatureVector, stems: StemFeatures) -> FloretUniforms {
        var uni = FloretUniforms()
        uni.time = features.time
        uni.coreEnergy = max(0, (features.bass + features.mid + features.treble) / 3.0)

        // ── Energy swell ← avg-stem envelope (FLORET.3a) ──────────────────────────
        // The bloom inflates as the music fills out. Driven off the average stem energy
        // (full-band-aware — raw mid/treble are ~dead on real shoegaze, the session showed;
        // the energy lives in the stems) on a ~0.5 s EMA, so it reads as the song's arc, not a
        // per-frame jolt. The Nacre "turning ← energy" precedent, re-aimed at bloom extent.
        let avgStem = max(0, (stems.drumsEnergy + stems.bassEnergy
                              + stems.vocalsEnergy + stems.otherEnergy) * 0.25)
        floretSwellEMA += (avgStem - floretSwellEMA) * kFloretSwellSmooth
        uni.swell = floretSwellEMA

        // ── Bass spin ← bass deviation, accumulated (FLORET.3a) ───────────────────
        // The field rotates; the rate rises with the bass (bassDev — the dynamic band here,
        // spikes ~2.2×). Soft-saturated (tanh) so a transient can't fling it (the deviation-
        // real-range lesson); a faint base rate keeps it turning at silence. Accumulates → the
        // comp re-samples the already-rotated field, so even a small rate reads as a clear spin.
        let bassKick = tanh(max(0, features.bassDev))
        floretSpin += kFloretSpinBase + kFloretSpinBassGain * bassKick
        uni.spin = floretSpin

        // ── Beat-lock camera push ← the cached downbeat (FLORET.3a) ───────────────
        // The motion Matt validated by eye, made real on EVERY track: a sharp-attack / bar-decay
        // envelope on the cached BeatGrid's barPhase01 → the comp magnifies the field on the
        // downbeat (display-stage, no smear). Static on beatless tracks. (Nacre NACRE.4.)
        uni.barPush = pow(max(0, 1 - features.barPhase01), 2.5)

        let size = mvWarpDrawableSize
        let wPx = max(Float(size.width), 1), hPx = max(Float(size.height), 1)
        uni.texel = SIMD2<Float>(1.0 / wPx, 1.0 / hPx)
        // butterchurn aspect: the LONGER axis is normalised to 1, the shorter carries the
        // ratio — keeps the comp's cell field round on a wide canvas (Nacre precedent).
        let aspectX: Float = wPx >= hPx ? hPx / wPx : 1
        let aspectY: Float = hPx > wPx ? wPx / hPx : 1
        uni.aspect = SIMD4<Float>(aspectX, aspectY, 1.0 / aspectX, 1.0 / aspectY)
        return uni
    }

    // MARK: Draw branch

    /// Live entry point: render the Floret frame to the drawable, then present. Thin wrapper
    /// over `renderFloret(target:)` so the live path and the diag harness run the EXACT SAME
    /// render code (FA #66 — no reimplemented test path).
    @MainActor
    func drawWithFloret(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        warpState: MVWarpState
    ) {
        guard let drawable = view.currentDrawable else { return }
        renderFloret(
            commandBuffer: commandBuffer,
            features: features,
            stemFeatures: stemFeatures,
            warpState: warpState,
            target: drawable.texture)
        commandBuffer.present(drawable)
    }

    /// Floret feedback loop rendered into `target`: warp → signature comp (→ target) → swap.
    /// Target-agnostic so the live drawable path and the offscreen diag both call it
    /// identically (FA #66). `stemFeatures` is accepted for parity with the dispatch + the
    /// FLORET.3 stem routing; the 2a stub uniforms don't read it yet.
    @MainActor
    func renderFloret(
        commandBuffer: MTLCommandBuffer,
        features: FeatureVector,
        stemFeatures: StemFeatures,
        warpState: MVWarpState,
        target: MTLTexture
    ) {
        var uni = computeFloretUniforms(features: features, stems: stemFeatures)

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
            enc.setFragmentBytes(&uni, length: MemoryLayout<FloretUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)  // 31×23 quads
            enc.endEncoding()
        }

        // ── Comp blit: signature(compose, u) → target (display-only) ──────────
        let cdesc = MTLRenderPassDescriptor()
        cdesc.colorAttachments[0].texture     = target
        cdesc.colorAttachments[0].loadAction  = .dontCare
        cdesc.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: cdesc) {
            enc.setRenderPipelineState(warpState.blitPipeline)
            enc.setFragmentTexture(warpState.composeTexture, index: 0)
            enc.setFragmentBytes(&uni, length: MemoryLayout<FloretUniforms>.stride, index: 1)
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

    /// Reduced-motion (U.9 / a11y) Floret frame into `target`: the signature comp of the
    /// CURRENT (un-advanced) feedback — NO warp pass, NO swap → no feedback accumulation,
    /// hence no motion. Floret's direct pipeline is compiled for its `.rgba16Float`
    /// feedback format, so (like Nacre, BUG-061) routing reduced-motion through the comp
    /// (blit) pipeline — which IS the drawable format — is both crash-safe and the correct
    /// static frame the U.9 contract wants. Target-agnostic (FA #66).
    @MainActor
    func renderFloretReducedMotion(
        commandBuffer: MTLCommandBuffer,
        features: FeatureVector,
        warpState: MVWarpState,
        target: MTLTexture
    ) {
        var uni = computeFloretUniforms(features: features, stems: .zero)
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = target
        desc.colorAttachments[0].loadAction  = .dontCare
        desc.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        enc.setRenderPipelineState(warpState.blitPipeline)        // floret_comp (drawable format)
        enc.setFragmentTexture(warpState.warpTexture, index: 0)   // current feedback, NOT advanced
        enc.setFragmentBytes(&uni, length: MemoryLayout<FloretUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }
}
