// RayMarchPipeline+MetalFX — MFX.1 temporal anti-aliasing wiring.
//
// Split out of RayMarchPipeline / +Passes so the MetalFX surface (readiness,
// jitter, the motion-vector pass) reads as one unit instead of being scattered
// through the main render file — and so both files stay inside the length gates.
// See MetalFXTemporalUpscaler for why temporal AA is needed and what it costs.

import Foundation
import QuartzCore
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

    /// Option-A preset-agnostic audio modulation.
    ///
    /// FLY.6: lives on RayMarchPipeline (moved off RenderPipeline) so the offline
    /// replay harness calls the SAME code production does. It previously sat in
    /// RenderPipeline, which the harness bypasses entirely — so every offline
    /// frame was rendered WITHOUT the per-frame fog / light-intensity / valence
    /// tint that production applies, and offline images looked cleaner and
    /// differently lit than the live app (BUG-071 round 6). Parity by
    /// construction beats parity by discipline.
    ///
    /// Original doc follows.
    /// Option-A preset-agnostic audio modulation: drives light, fog, camera dolly,
    /// and fin position from the feature vector, additive on top of the preset's
    /// JSON baseline (`baseScene`). Geometry stays static — music moves the camera
    /// and lights the space (D-020).
    func applyAudioModulation(features: FeatureVector) {
        let base = baseScene
        let now = CACurrentMediaTime()
        let dt: Float = lastDollyFrameTime.map { Float(max(0, now - $0)) } ?? 0
        lastDollyFrameTime = now
        let bassContribution = max(0, min(1.1, features.bass * 1.1))
        let instantaneousSpeed = cameraDollySpeed * (0.5 + bassContribution)
        cameraDollyOffset += dt * instantaneousSpeed
        let dollyZ = base.cameraPosition.z + cameraDollyOffset
        sceneUniforms.cameraOriginAndFov.x = base.cameraPosition.x
        sceneUniforms.cameraOriginAndFov.y = base.cameraPosition.y
        sceneUniforms.cameraOriginAndFov.z = dollyZ
        // PERF.3 (BUG-019 fix) — light-intensity restructured per CLAUDE.md Failed
        // Approach #4 (beat is accent, never primary). Previous formula
        // `0.4 + beatPulse * 2.6` had the beat term 6.5× the baseline; every beat
        // fired a single-frame 2.1× brightness multiplier swing of the whole scene,
        // visible as 3 Hz flicker on FFO (verified by ffmpeg signalstats on
        // session 2026-05-27T22-49-42Z video.mp4: 76 brightness-oscillation events
        // across 200 s of playback, matching beat firing rate). The restructured
        // formula puts continuous bass as the primary driver (per the Audio Data
        // Hierarchy rule) and keeps the beat as a small accent. Worst-case range
        // [1.0, 1.55]; single-frame beat-fire swing ±0.15 (vs ±2.1 before).
        let bassPrimary = max(0, min(1.0, features.bass))
        let beatPulse = max(features.beatBass, max(features.beatMid, features.beatComposite))
        let beatAccent = max(0, min(1.0, beatPulse))
        let intensityMulTarget = 1.0 + bassPrimary * 0.4 + beatAccent * 0.15
        // BUG-038 (continuation of BUG-019, FBS pre-step) — temporally smooth the
        // light multiplier so it cannot step frame-to-frame. The beat-onset signals
        // fire on ~97 % of frames on real sessions (a near-constant jitter, NOT clean
        // beats) and `f.bass` is noisy; together they flickered the whole scene's
        // brightness 7–9 perceptible steps/sec (the BUG-019 residual). An EMA
        // (τ ≈ 0.12 s) drops that to ~0 (verified on 4 sessions: streaming Love
        // Rehab / So What / Lotus Flower + clean-signal Cherub) while preserving the
        // slower musical brightness swell. Preset-agnostic + mean-preserving → no
        // certified-preset regression. The PERF.3 formula (continuous bass primary,
        // beat as a small accent) is unchanged; it is only low-passed now.
        smoothedLightIntensityMul = RayMarchPipeline.smoothLightIntensity(
            previous: smoothedLightIntensityMul,
            target: intensityMulTarget,
            dt: dt)
        sceneUniforms.lightPositionAndIntensity.w =
            base.lightIntensity * smoothedLightIntensityMul
        let valence = max(-1, min(1, features.valence))
        let warm = max(0, valence)
        let cool = max(0, -valence)
        let tint = SIMD3<Float>(
            1.0 + warm * 0.40 - cool * 0.25,
            1.0 + warm * 0.15 - cool * 0.10,
            1.0 + cool * 0.40 - warm * 0.30
        )
        sceneUniforms.lightColor = SIMD4(base.lightColor * tint, 0)
        let arousal = max(-1, min(1, features.arousal))
        let fogScale: Float = arousal >= 0
            ? (1.0 - arousal * 0.7)
            : (1.0 + (-arousal) * 1.0)
        sceneUniforms.sceneParamsB.y = base.fogFar * fogScale
        let bassDrive = max(0, min(1, features.subBass + features.lowBass))
        let finCX: Float = 1.20 - (1.20 - 0.85) * bassDrive
        sceneUniforms.cameraForward.w = finCX
    }
}
