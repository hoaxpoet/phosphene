// RenderPipeline+FataMorgana — the Fata Morgana mv_warp draw branch (D-139).
//
// Faithful port of the butterchurn builtin `martin [shadow harlequins shape code]
// - fata morgana` render loop (read wholesale from source, FA #70). Per frame:
//
//   blur(prev) → blurTexture                      (the butterchurn `blur1` the warp reads)
//   warp(prev, blur, u) → composeTexture          (custom feedback warp; bakes its own decay)
//   [shapes drawn normal/additive on top → L2]    (== the feedback, like DB strands-on-top)
//   comp(compose, noise, u) → drawable            (the procedural MIRAGE; display-only)
//   swap warpTexture ↔ composeTexture
//
// L1 (this increment): warp + comp + blur substrate, no shapes. The mirage's
// starfield/horizon/neon-grid are procedural in the comp, so they render against
// an empty feedback field; the floor reflection fills in once shapes land (L2).
//
// FataUniforms carries the butterchurn builtins the custom shaders reference
// (time, q1/q2 beat-rotation cos/sin, the roaming sin vectors, rand_preset,
// texsize). The frame_eqs beat-rotation accumulator runs CPU-side here.

import Metal
@preconcurrency import MetalKit
import Shared

// MARK: - FataUniforms (matches `struct FataUniforms` in FataMorgana.metal)

/// 80-byte uniform bound at fragment buffer(1) of the warp + comp passes.
/// Layout: 4 leading floats pack into the first 16-byte slot, then four 16-aligned
/// SIMD4<Float> — byte-identical to the MSL struct.
struct FataUniforms {
    var time: Float = 0
    var q1: Float = 1
    var q2: Float = 0
    var gammaAdj: Float = 1.98
    var texsize: SIMD4<Float> = .init(1, 1, 1, 1)
    var roamSin: SIMD4<Float> = .init(repeating: 0.5)
    var slowRoamSin: SIMD4<Float> = .init(repeating: 0.5)
    // rand_preset is RANDOM per-load in butterchurn (only its .z scales the sky's
    // blue gradient via `rand_preset*(0.5-uv.y)*vec3(0,0,1)`). The faithful oracle's
    // load had a low blue (near-black starfield sky); a high .z drowns the stars in
    // a blue wash. Fixed to a low value to match the oracle's dark-sky register.
    var randPreset: SIMD4<Float> = .init(0.30, 0.40, 0.14, 0.60)
}

// MARK: - FataShapeParams (matches `struct FataShapeParams` in FataMorgana.metal)

/// 32-byte per-shape uniform bound at vertex buffer(1) of the shape draw.
struct FataShapeParams {
    var shapeIndex: Int32
    var sides: Int32
    var numInst: Int32
    var frame: Float
    var aspectY: Float
    var audioBoost: Float
    var pad0: Float = 0
    var pad1: Float = 0
}

/// The 4 fata shapes' fixed config (sides + instance count). Shape 0 = textured echo
/// (normal blend), 1/2/3 = mid/bass/treb additive blobs. D-139.
struct FataShapeDraw {
    let shapeIndex: Int32
    let sides: Int32
    let numInst: Int32
    static let all: [FataShapeDraw] = [
        FataShapeDraw(shapeIndex: 0, sides: 30, numInst: 1),
        FataShapeDraw(shapeIndex: 1, sides: 40, numInst: 4),
        FataShapeDraw(shapeIndex: 2, sides: 40, numInst: 1),
        FataShapeDraw(shapeIndex: 3, sides: 40, numInst: 5),
    ]
}

extension RenderPipeline {

    // MARK: Per-frame uniforms + beat-rotation accumulator

    /// Compute the Fata Morgana warp/comp uniforms for this frame, advancing the
    /// frame_eqs beat-rotation accumulator (verbatim from source — see the plan).
    @MainActor
    func computeFataUniforms(features: FeatureVector) -> FataUniforms {
        var uni = FataUniforms()
        let tSec = features.time
        uni.time = tSec

        // roam_sin / slow_roam_sin (butterchurn time-roam vectors).
        uni.roamSin = SIMD4<Float>(0.5 + 0.5 * sin(tSec * 0.3),
                                   0.5 + 0.5 * sin(tSec * 1.3),
                                   0.5 + 0.5 * sin(tSec * 5.0),
                                   0.5 + 0.5 * sin(tSec * 20.0))
        uni.slowRoamSin = SIMD4<Float>(0.5 + 0.5 * sin(tSec * 0.005),
                                       0.5 + 0.5 * sin(tSec * 0.008),
                                       0.5 + 0.5 * sin(tSec * 0.013),
                                       0.5 + 0.5 * sin(tSec * 0.022))

        // texsize (feedback px size + reciprocal).
        let size = mvWarpDrawableSize
        let wPx = max(Float(size.width), 1), hPx = max(Float(size.height), 1)
        uni.texsize = SIMD4<Float>(wPx, hPx, 1.0 / wPx, 1.0 / hPx)

        // frame_eqs beat-rotation accumulator (source verbatim, order preserved):
        let dts = max(features.deltaTime, 1e-3)
        let decMed  = pow(Float(0.7), 30.0 * dts)
        let decSlow = pow(Float(0.99), 30.0 * dts)
        let beat = max(max(features.bass, features.mid), features.treble)
        fataAvg = fataAvg * decSlow + beat * (1 - decSlow)
        let isBeat = (beat > 0.2 + fataAvg + fataPeak) && (tSec > fataT0 + 0.2)
        if isBeat { fataT0 = tSec }
        fataPeak = isBeat ? beat : fataPeak * decMed
        if isBeat { fataIndex = (fataIndex + 1) % 8 }
        // k1: beat AND index even → step p1.
        if isBeat && (fataIndex % 2 == 0) { fataP1 += 1 }
        fataP2 = decMed * fataP2 + (1 - decMed) * fataP1
        let rott = Float.pi * fataP2 / 4.0
        uni.q1 = cos(rott)
        uni.q2 = sin(rott)
        return uni
    }

    // MARK: Draw branch

    /// Fata Morgana feedback loop: blur → warp → [shapes L2] → mirage comp → swap.
    @MainActor
    func drawWithFataMorgana(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        warpState: MVWarpState
    ) {
        fataFrame &+= 1
        var uni = computeFataUniforms(features: features)

        // ── Blur pass: blur(prev) → blurTexture (the warp's `blur1`) ──────────
        if let blurPipe = warpState.blurPipeline, let blurTex = warpState.blurTexture {
            let bdesc = MTLRenderPassDescriptor()
            bdesc.colorAttachments[0].texture = blurTex
            bdesc.colorAttachments[0].loadAction = .dontCare
            bdesc.colorAttachments[0].storeAction = .store
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: bdesc) {
                enc.setRenderPipelineState(blurPipe)
                enc.setFragmentTexture(warpState.warpTexture, index: 0)
                enc.setFragmentBytes(&uni, length: MemoryLayout<FataUniforms>.stride, index: 1)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
            }
        }

        // ── Warp pass: warp(prev, blur, u) → composeTexture ───────────────────
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
            if let blurTex = warpState.blurTexture { enc.setFragmentTexture(blurTex, index: 1) }
            enc.setFragmentBytes(&uni, length: MemoryLayout<FataUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)  // 31×23 quads
            enc.endEncoding()
        }

        // ── Shapes on top of composeTexture (FM.L2; = the feedback) ───────────
        encodeFataShapes(commandBuffer: commandBuffer, warpState: warpState, features: features)

        // ── Comp blit: mirage(compose, noise, u) → drawable ───────────────────
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }
        descriptor.colorAttachments[0].loadAction  = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            enc.setRenderPipelineState(warpState.blitPipeline)
            enc.setFragmentTexture(warpState.composeTexture, index: 0)
            bindNoiseTextures(to: enc)   // noiseLQ→4, noiseHQ→5 (the comp's pw_noise_lq / noise_hq)
            enc.setFragmentBytes(&uni, length: MemoryLayout<FataUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        commandBuffer.present(drawable)

        // ── Swap: composeTexture becomes next frame's warpTexture ─────────────
        mvWarpLock.withLock {
            guard var state = mvWarpState else { return }
            swap(&state.warpTexture, &state.composeTexture)
            mvWarpState = state
        }
    }

    // MARK: Shapes (FM.L2)

    /// Draw the 4 custom shapes on top of the warped composeTexture (= the feedback).
    /// Shape 0 (normal-blend textured echo, samples the prev frame), then the 3
    /// additive neon blobs sized by mid/bass/treb attack. One render pass, pipeline
    /// switched per shape. (Faithful to butterchurn's draw order: 0,1,2,3.)
    @MainActor
    func encodeFataShapes(
        commandBuffer: MTLCommandBuffer,
        warpState: MVWarpState,
        features: FeatureVector
    ) {
        let (additive, normal) = mvWarpLock.withLock { (fataShapeAdditive, fataShapeNormal) }
        guard let additive, let normal else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = warpState.composeTexture
        desc.colorAttachments[0].loadAction = .load       // keep the warped feedback
        desc.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }

        let sz = mvWarpDrawableSize
        let aspectY = Float(min(sz.width, sz.height)) / Float(max(sz.width, sz.height))
        let boost = RenderPipeline.fataShapeAudioBoost
        var feat = features
        enc.setVertexBytes(&feat, length: MemoryLayout<FeatureVector>.stride, index: 0)
        enc.setFragmentTexture(warpState.warpTexture, index: 0)   // prev frame, for shape 0 texturing

        // Draw order 0,1,2,3 (faithful to butterchurn): textured echo, then mid/bass/treb blobs.
        for shape in FataShapeDraw.all {
            enc.setRenderPipelineState(shape.shapeIndex == 0 ? normal : additive)
            var params = FataShapeParams(
                shapeIndex: shape.shapeIndex,
                sides: shape.sides,
                numInst: shape.numInst,
                frame: Float(fataFrame),
                aspectY: aspectY,
                audioBoost: boost)
            enc.setVertexBytes(&params, length: MemoryLayout<FataShapeParams>.stride, index: 1)
            let vc = Int(shape.sides) * 3, ic = Int(shape.numInst)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vc, instanceCount: ic)
        }
        enc.endEncoding()
    }

    /// Multiplies the band attack driving the blob radii. butterchurn feeds
    /// 6×-boosted audio (D-138); start at 1.0 against Phosphene's attack values and
    /// tune against the oracle at M7.
    static let fataShapeAudioBoost: Float = 1.0
}
