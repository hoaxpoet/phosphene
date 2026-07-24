// RayMarchPipeline+MetalFX — MFX.1 temporal anti-aliasing wiring.
//
// Split out of RayMarchPipeline / +Passes so the MetalFX surface (readiness,
// jitter, the motion-vector pass) reads as one unit instead of being scattered
// through the main render file — and so both files stay inside the length gates.
// See MetalFXTemporalUpscaler for why temporal AA is needed and what it costs.

import Foundation
import Metal
import simd
import Shared

extension RayMarchPipeline {

    /// True when everything the resolve needs is present.
    var metalFXReady: Bool {
        metalFXEnabled && metalFX != nil && motionPipelineState != nil
            && mfxMotionTexture != nil && mfxDepthTexture != nil && mfxResolvedTexture != nil
    }

    /// Pick this frame's jitter and bake it into the camera basis so the G-buffer
    /// marches the offset rays. Returns the jitter for the scaler.
    ///
    /// The ray is built as `camFwd + ndc.x·xFov·camRt − ndc.y·yFov·camUp`, so a
    /// sub-pixel NDC offset is equivalent to nudging `camFwd` — which means the
    /// jitter needs no new uniform slot and every pass that reconstructs from the
    /// camera basis (lighting, shadows, motion) stays automatically consistent.
    func applyJitter(width: Int, height: Int) {
        guard metalFXReady, let mfx = metalFX, width > 0, height > 0 else {
            currentJitter = .zero
            return
        }
        // BUG-071 round 3 (the "nearly unwatchable" regression): this MUST derive
        // from the unjittered forward. The first version read the LIVE
        // `sceneUniforms.cameraForward`, added jitter, and wrote it back — and
        // nothing resets `cameraForward.xyz` per frame (applyAudioModulation only
        // touches `.w`), so every frame jittered the ALREADY-jittered vector. Two
        // consequences: the camera direction random-walked (~4.5°/min), and —
        // far worse — the offset MetalFX was told to undo (`currentJitter`, the
        // per-frame Halton value) no longer matched the camera's ACTUAL cumulative
        // offset, so the temporal resolve reprojected against a mis-aligned history
        // and smeared. Capturing the base once and always offsetting from it keeps
        // the reported jitter and the real jitter identical, which is the whole
        // precondition for temporal accumulation.
        let base = jitterBaseForward ?? sceneUniforms.cameraForward
        if jitterBaseForward == nil { jitterBaseForward = base }

        let jit = mfx.currentJitter()
        currentJitter = jit
        let yFov = tan(sceneUniforms.cameraOriginAndFov.w * 0.5)
        let xFov = yFov * sceneUniforms.sceneParamsA.y
        // Jitter is in pixels; convert to the NDC span of one pixel (NDC is 2 wide).
        let ndcX = (jit.x * 2.0 / Float(width)) * xFov
        let ndcY = (jit.y * 2.0 / Float(height)) * yFov
        let rgt = sceneUniforms.cameraRight
        let upv = sceneUniforms.cameraUp
        let jittered = SIMD3(base.x, base.y, base.z)
            + ndcX * SIMD3(rgt.x, rgt.y, rgt.z)
            - ndcY * SIMD3(upv.x, upv.y, upv.z)
        // Preserve .w — it carries per-preset payload (Ferrofluid's finCX).
        sceneUniforms.cameraForward = SIMD4(jittered, sceneUniforms.cameraForward.w)
    }

    /// MFX.1 — motion-vector + depth pass. Reads gbuffer0 (normalized depth),
    /// reconstructs each hit's world position, asks the preset where that point was
    /// last frame (`scenePrevPosition`), and writes the screen-space delta MetalFX
    /// needs to reproject its history.
    struct MotionPassTargets {
        let pipelineState: MTLRenderPipelineState
        let motionTexture: MTLTexture
        let depthTexture: MTLTexture
    }

    func runMotionPass(
        commandBuffer: MTLCommandBuffer,
        targets: MotionPassTargets,
        features: inout FeatureVector,
        stemFeatures: StemFeatures
    ) {
        let motionPipelineState = targets.pipelineState
        let motionTexture = targets.motionTexture
        let depthTexture = targets.depthTexture
        guard let gbuf0 = gbuffer0 else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture     = motionTexture
        desc.colorAttachments[0].loadAction  = .clear
        desc.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        desc.colorAttachments[0].storeAction = .store
        desc.colorAttachments[1].texture     = depthTexture
        desc.colorAttachments[1].loadAction  = .clear
        desc.colorAttachments[1].clearColor  = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 0)
        desc.colorAttachments[1].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(motionPipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        var stems = stemFeatures
        encoder.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.size, index: 3)
        encoder.setFragmentBytes(&sceneUniforms, length: MemoryLayout<SceneUniforms>.size, index: 4)
        encoder.setFragmentTexture(gbuf0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
