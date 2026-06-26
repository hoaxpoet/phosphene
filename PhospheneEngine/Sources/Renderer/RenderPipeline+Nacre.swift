// RenderPipeline+Nacre — the Nacre mv_warp draw branch (NACRE.2b).
//
// Faithful port of the butterchurn builtin `$$$ Royal - Mashup (431)` render loop
// (read wholesale from source, FA #70). Per frame — the D-138 structure, simpler than
// Fata Morgana (no blur target, no shapes; the seed is folded into the warp):
//
//   warp(prev, u) → composeTexture       (custom feedback warp; bakes its own decay,
//                                          unsharp, grain, palette-tinted core seed)
//   comp(compose, u) → target            (the signature look; DISPLAY-only)
//   swap warpTexture ↔ composeTexture
//
// NacreUniforms carries the (431) builtins the custom shaders reference (time, the
// treble grain gate, feedback texel size + aspect, the fixed per-load randoms + slow
// colour roam). All time-driven / stateless — no CPU accumulators (the bass-onset kick
// runs GPU-side off bassDev in mvWarpPerVertex).

import Metal
@preconcurrency import MetalKit
import Shared

// MARK: - NacreUniforms (matches `struct NacreUniforms` in Nacre.metal)

/// 96-byte uniform bound at fragment buffer(1) of the warp + comp passes.
/// Layout: time/trebleGrain/coreEnergy/pad0 fill the first 16-byte slot, then
/// texel+pad1, then four 16-aligned SIMD4<Float> — byte-identical to the MSL struct.
struct NacreUniforms {
    var time: Float = 0
    var trebleGrain: Float = 0
    var coreEnergy: Float = 0
    var hueShift: Float = 0            // NACRE.3: harmony → palette-phase nudge (seconds), bounded
    var texel: SIMD2<Float> = .init(1, 1)
    var pad1: SIMD2<Float> = .init(0, 0)
    var aspect: SIMD4<Float> = .init(1, 1, 1, 1)
    // Fixed per-load random (the comp's tint + dz-scale character). Chosen in the
    // green-gold register the (431) reference sits in (tint 1+rand ≈ (1.62,1.74,1.30)).
    // Swept against the reference stills at port time; a comp-only constant.
    var randPreset: SIMD4<Float> = .init(0.62, 0.74, 0.30, 0.55)
    var slowRoamSin: SIMD4<Float> = .init(repeating: 0.5)
    var roamCos: SIMD4<Float> = .init(repeating: 0.5)
}

// NACRE.3 hue ← harmony tuning. The centroid deviation runs ~±0.03 (session 22-42-45Z),
// so a gain of 40 maps it to ~±1.2 palette-seconds; the bound caps it at ±1.5 s ≈ ±10 % of
// the ~14 s palette cycle — a subtle colour drift, not a hue meter. Both are feel knobs.
private let kNacreHueGain: Float = 40.0
private let kNacreHueBound: Float = 1.5

extension RenderPipeline {

    // MARK: Per-frame uniforms

    /// Compute the Nacre warp/comp uniforms for this frame. Pure (time + drawable size +
    /// features.trebleDev) — no stateful accumulators.
    @MainActor
    func computeNacreUniforms(features: FeatureVector, stems: StemFeatures) -> NacreUniforms {
        var uni = NacreUniforms()
        let tSec = features.time
        uni.time = tSec
        uni.trebleGrain = max(0, features.trebDev)

        // ── Core ← voice (NACRE.3) ───────────────────────────────────────────────
        // The central light is the visual hero, the voice is the hero sound — pulse the
        // core with the VOCALS stem (dynamic: phrases come and go) rather than the near-
        // constant total volume that read as static (Matt M7: "not registering a
        // connection"). A gentler total-energy floor keeps the core alive in instrumental
        // sections; the warp's coreGate baseline holds it dim-but-visible at silence (D-019).
        // Smoothed ~0.16 s — swells with the vocal phrasing, doesn't flicker.
        // SOFT-SATURATE the vocal signal (tanh): vocalsEnergy spikes to ~3× on peaks
        // (max 2.95 in session 13-40-34Z), so the raw value slammed the core to max
        // brightness → over-bloom → the bright core dragged outward by the zoom into
        // "stretches and smears" (Matt M7). tanh caps the spike to ~1, smooth knee — the
        // core still swells with the voice but never blooms. Same fix as the zoom/kick
        // (project_deviation_primitive_real_range — soft-saturate vs p99, never vs 1.0).
        let total = max(0, (features.bass + features.mid + features.treble) / 3.0)
        let coreTarget = max(tanh(max(0, stems.vocalsEnergy)), 0.35 * total)
        nacreCoreEMA += (coreTarget - nacreCoreEMA) * 0.10
        uni.coreEnergy = nacreCoreEMA

        // ── Hue ← harmony (NACRE.3) ──────────────────────────────────────────────
        // Nudge the palette PHASE (a subtle drift on top of the slow time-rotation, NOT a
        // hue meter) by the music's spectral colour. Track-robust + calm by construction:
        //   · drive from the centroid's DEVIATION from a slow section-norm (not its absolute
        //     value — which is track-dependent), so it responds to harmonic/timbral SHIFTS;
        //   · gate by energy so silence holds the base palette (no hue jump at track gaps);
        //   · heavily smoothed + bounded → responds to the slow harmonic drift, not every
        //     note (Matt: half/quarter-time is fine). v1 uses the whole-mix centroid as the
        //     harmony proxy (chroma isn't available); can narrow to the `other` stem later.
        let gate = max(0, min(1, (total - 0.03) / 0.09))              // 0 at silence → 1 with music
        if total > 0.05 {                                            // track the norm only on signal
            nacreCentroidNorm += (features.spectralCentroid - nacreCentroidNorm) * 0.003   // ~5 s
        }
        let dev = (features.spectralCentroid - nacreCentroidNorm) * gate
        let hueTarget = max(-kNacreHueBound, min(kNacreHueBound, dev * kNacreHueGain))
        nacreHueEMA += (hueTarget - nacreHueEMA) * 0.04              // ~0.4 s calm output smoothing
        uni.hueShift = nacreHueEMA

        let size = mvWarpDrawableSize
        let wPx = max(Float(size.width), 1), hPx = max(Float(size.height), 1)
        uni.texel = SIMD2<Float>(1.0 / wPx, 1.0 / hPx)
        // butterchurn aspect: the LONGER axis is normalised to 1, the shorter carries
        // the ratio — keeps the comp's sine-cell field round on a wide canvas.
        let aspectX: Float = wPx >= hPx ? hPx / wPx : 1
        let aspectY: Float = hPx > wPx ? wPx / hPx : 1
        uni.aspect = SIMD4<Float>(aspectX, aspectY, 1.0 / aspectX, 1.0 / aspectY)

        // Slow colour roam (the comp's subtractive `slow_roam_sin.wzy * roam_cos.zxy`).
        // Slow rates → a gentle desaturating drift; the *0.4 in-shader keeps it subtle.
        uni.slowRoamSin = SIMD4<Float>(0.5 + 0.5 * sin(tSec * 0.05),
                                       0.5 + 0.5 * sin(tSec * 0.08),
                                       0.5 + 0.5 * sin(tSec * 0.13),
                                       0.5 + 0.5 * sin(tSec * 0.22))
        uni.roamCos = SIMD4<Float>(0.5 + 0.5 * cos(tSec * 0.03),
                                   0.5 + 0.5 * cos(tSec * 0.05),
                                   0.5 + 0.5 * cos(tSec * 0.08),
                                   0.5 + 0.5 * cos(tSec * 0.11))
        return uni
    }

    // MARK: Draw branch

    /// Live entry point: render the Nacre frame to the drawable, then present. Thin
    /// wrapper over `renderNacre(target:)` so the live path and the diag harness run the
    /// EXACT SAME render code (FA #66 — no reimplemented test path).
    @MainActor
    func drawWithNacre(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        warpState: MVWarpState
    ) {
        guard let drawable = view.currentDrawable else { return }
        renderNacre(
            commandBuffer: commandBuffer,
            features: features,
            stemFeatures: stemFeatures,
            warpState: warpState,
            target: drawable.texture)
        commandBuffer.present(drawable)
    }

    /// Nacre feedback loop rendered into `target`: warp → signature comp (→ target) →
    /// swap. Target-agnostic so the live drawable path and the offscreen diag both call
    /// it identically.
    @MainActor
    func renderNacre(
        commandBuffer: MTLCommandBuffer,
        features: FeatureVector,
        stemFeatures: StemFeatures,
        warpState: MVWarpState,
        target: MTLTexture
    ) {
        var uni = computeNacreUniforms(features: features, stems: stemFeatures)

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
            enc.setFragmentBytes(&uni, length: MemoryLayout<NacreUniforms>.stride, index: 1)
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
            enc.setFragmentBytes(&uni, length: MemoryLayout<NacreUniforms>.stride, index: 1)
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

    /// Reduced-motion (U.9 / a11y) Nacre frame into `target`: the signature comp of the
    /// CURRENT (un-advanced) feedback — NO warp pass, NO swap → no feedback accumulation,
    /// hence no motion. Target-agnostic (FA #66) so the live drawable path and a headless
    /// test drive the same code.
    ///
    /// This exists because the shared `drawMVWarpReducedMotion` renders a preset's DIRECT
    /// pipeline straight to the drawable, and Nacre's direct pipeline is compiled for its
    /// `.rgba16Float` feedback format — a 16-float pipeline → 8-bit drawable is an
    /// attachment-format mismatch that crashes (BUG-061). The comp (blit) pipeline is
    /// compiled for the drawable format, so routing reduced-motion Nacre through it is
    /// both crash-safe and the correct "static frame" the U.9 contract wants.
    @MainActor
    func renderNacreReducedMotion(
        commandBuffer: MTLCommandBuffer,
        features: FeatureVector,
        warpState: MVWarpState,
        target: MTLTexture
    ) {
        var uni = computeNacreUniforms(features: features, stems: .zero)   // static frame; no vocal pulse
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = target
        desc.colorAttachments[0].loadAction  = .dontCare
        desc.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        enc.setRenderPipelineState(warpState.blitPipeline)        // nacre_comp (drawable format)
        enc.setFragmentTexture(warpState.warpTexture, index: 0)   // current feedback, NOT advanced
        enc.setFragmentBytes(&uni, length: MemoryLayout<NacreUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }
}
