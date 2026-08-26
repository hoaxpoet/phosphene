// RayMarchPipeline+AudioModulation — Option-A preset-agnostic audio modulation.
//
// Lived in RayMarchPipeline+MetalFX until D-213/RECON.14 deleted the MFX.1
// surface around it; the modulation itself is load-bearing (FLY.6 harness
// parity — see the doc comment below).

import Foundation
import QuartzCore
import Metal
import simd
import Shared

/// Smoothstep on Float (no simd overload for scalars in this context).
private func smoothstepF(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let tt = min(max((x - e0) / max(e1 - e0, 1e-6), 0), 1)
    return tt * tt * (3 - 2 * tt)
}

extension RayMarchPipeline {

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

        // Camera orbit: a slow turntable around the world origin on the Y axis. A
        // static shot undersells a ray-marched shape's actual depth (roundness and
        // self-occlusion read mainly through parallax, not a single still). Rosette
        // (WHIT.2b) was this feature's first consumer, then removed it (D-223: a
        // constant-rate orbit read as disconnected from the music, and periodically
        // flattened its wholly-planar scene edge-on) before being retired itself
        // (D-224) — no current consumer. Kept as generic camera plumbing for a future
        // preset with real out-of-plane geometry and/or an audio-modulated rate.
        // Orthogonal to the dolly above: computed purely from `base.cameraPosition`,
        // ignoring `cameraDollyOffset` — no current preset drives both at once.
        if cameraOrbitSpeed != 0 {
            cameraOrbitAngle += dt * cameraOrbitSpeed
            applyCameraOrbit(aroundOrigin: base.cameraPosition, angle: cameraOrbitAngle)
        }
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
        // FLY.9 — smoothed fold/"event" driver, published in the free cameraUp.w
        // lane. `bass_att_rel` is a spiky deviation primitive: fed raw to a
        // GEOMETRY parameter it snapped the whole structure frame-to-frame (11
        // visible snaps in the first 10 s of Matt's session — his "camera jumps
        // around"). An EMA over a swell-length window turns it into the sustained
        // build a musical "arrival" actually needs.
        let foldTarget = max(0, min(1.5, features.bassAttRel))
        let foldTau: Float = 0.45                       // ~0.45 s swell window
        let foldAlpha = dt > 0 ? min(1, dt / foldTau) : 1
        smoothedFoldDrive += (foldTarget - smoothedFoldDrive) * foldAlpha
        sceneUniforms.cameraUp.w = smoothedFoldDrive

        let valence = max(-1, min(1, features.valence))
        let warm = max(0, valence)
        let cool = max(0, -valence)
        let tint = SIMD3<Float>(
            1.0 + warm * 0.40 - cool * 0.25,
            1.0 + warm * 0.15 - cool * 0.10,
            1.0 + cool * 0.40 - warm * 0.30
        )
        // FLY.10 — FRAMING driver (how vast the world feels), published in the
        // free lightColor.w lane. MUST be written AFTER lightColor above, which
        // zeroes .w. Driven by AROUSAL, deliberately a different primitive from
        // the fold's bass_att_rel (FA #67: one primitive per layer) — arousal is
        // the slow mood envelope, which is the right timescale for framing: you
        // do not want the composition twitching per beat.
        //
        // Calibrated to REAL data, not to the nominal [-1,1]: measured over Matt's
        // session arousal spans -0.08 .. +0.68 and a strong passage swings ~0 -> +0.5, so
        // mapping 0.02..0.58 is what uses the FULL swing (the round-9 lesson — a driver
        // calibrated to a range it never reaches produces an invisible effect).
        let framingRaw = smoothstepF(0.02, 0.58, features.arousal)
        // FLY.11: 1.6 -> 3.2. A fast lens change re-projects every pixel, which
        // reads as zoom PUMPING; framing should breathe over musical phrases.
        let framingTau: Float = 3.2
        let framingAlpha = dt > 0 ? min(1, dt / framingTau) : 1
        smoothedFraming += (framingRaw - smoothedFraming) * framingAlpha
        sceneUniforms.lightColor = SIMD4(base.lightColor * tint, smoothedFraming)

        // FLY.11 — apply framing to the LENS. A wide FOV takes in a whole vast
        // space; a narrow one compresses into a tight corridor — and changing it
        // moves NO geometry, so nothing sweeps through the camera.
        if fovFramingRange != 0 {
            sceneUniforms.cameraOriginAndFov.w = base.fov + fovFramingRange * smoothedFraming
        }
        let arousal = max(-1, min(1, features.arousal))
        let fogScale: Float = arousal >= 0
            ? (1.0 - arousal * 0.7)
            : (1.0 + (-arousal) * 1.0)
        sceneUniforms.sceneParamsB.y = base.fogFar * fogScale
        let bassDrive = max(0, min(1, features.subBass + features.lowBass))
        let finCX: Float = 1.20 - (1.20 - 0.85) * bassDrive
        sceneUniforms.cameraForward.w = finCX
    }

    /// WHIT.2b camera-orbit math, split out of `applyAudioModulation` to keep that
    /// function under the lint length gate. Rotates `origin` around the world Y axis by
    /// `angle` and re-derives a look-at-world-origin basis — the turntable shot a static
    /// camera undersells for a ray-marched tube (roundness/self-occlusion read mainly
    /// through parallax).
    private func applyCameraOrbit(aroundOrigin origin: SIMD3<Float>, angle: Float) {
        let sinAngle = sin(angle), cosAngle = cos(angle)
        let rotatedPos = SIMD3<Float>(
            cosAngle * origin.x + sinAngle * origin.z,
            origin.y,
            -sinAngle * origin.x + cosAngle * origin.z)
        let forward = simd_normalize(-rotatedPos)   // target is always the world origin
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(worldUp, forward))
        let up = simd_cross(forward, right)
        sceneUniforms.cameraOriginAndFov.x = rotatedPos.x
        sceneUniforms.cameraOriginAndFov.y = rotatedPos.y
        sceneUniforms.cameraOriginAndFov.z = rotatedPos.z
        sceneUniforms.cameraForward = SIMD4(forward.x, forward.y, forward.z, 0)
        sceneUniforms.cameraRight   = SIMD4(right.x, right.y, right.z, 0)
        sceneUniforms.cameraUp      = SIMD4(up.x, up.y, up.z, 0)
    }
}
