// RenderPipeline+RayMarch — Deferred ray march draw path (Increment 3.14).
//
// `drawWithRayMarch` is a render path parallel to `drawDirect`, `drawWithFeedback`,
// `drawWithPostProcess`, `drawWithMeshShader`, and `drawWithICB`.  It is invoked from
// `renderFrame` when `rayMarchEnabled == true` and a `RayMarchPipeline` is attached.
//
// The method delegates all G-buffer, lighting, and composite encoding to
// `RayMarchPipeline.render(...)`.  It only acquires the drawable and resolves the
// optional PostProcessChain for the bloom path.
//
// Priority in renderFrame(): mesh → postProcess → ICB → rayMarch → feedback → direct.

import Metal
@preconcurrency import MetalKit
import Shared
import os.log

private let rmLogger = Logger(subsystem: "com.phosphene.renderer", category: "RenderPipeline")

// MARK: - Texture + IBL Attachment

extension RenderPipeline {

    /// Attach noise textures that will be bound on every preset render encoder.
    ///
    /// Call once after app startup.  Pass `nil` to detach (noise textures will
    /// be unbound; shaders that sample them will read zeros).
    /// Thread-safe — can be called from any queue.
    public func setTextureManager(_ manager: TextureManager?) {
        textureManagerLock.withLock {
            textureManager = manager
        }
        rmLogger.info("TextureManager \(manager != nil ? "attached" : "detached")")
    }

    /// Attach IBL textures for the ray march lighting pass (Increment 3.16).
    ///
    /// Pass a non-nil manager to enable environment-based ambient and specular reflections.
    /// Pass `nil` to detach; the lighting pass will fall back to a minimum ambient term.
    /// Thread-safe — can be called from any queue.
    public func setIBLManager(_ manager: IBLManager?) {
        iblManagerLock.withLock {
            iblManager = manager
        }
        rmLogger.info("IBLManager \(manager != nil ? "attached" : "detached")")
    }
}

// MARK: - Ray March Draw Path

extension RenderPipeline {

    // swiftlint:disable function_parameter_count
    // `drawWithRayMarch` takes 7 parameters — the minimal render-pass context plus
    // an optional scene output texture for the mv_warp handoff.

    /// Deferred ray march render pass.
    ///
    /// Lazily allocates the pipeline's G-buffer and lit-scene textures if needed,
    /// then delegates all GPU work to `RayMarchPipeline.render(...)`.
    ///
    /// The pipeline runs:
    ///   1. G-buffer pass — preset `sceneSDF` + `sceneMaterial` → 3 G-buffer targets
    ///   2. Lighting pass — Cook-Torrance PBR + screen-space soft shadows → `.rgba16Float`
    ///   3. Composite pass — ACES tone-map to drawable (when no PostProcessChain);
    ///      OR bloom via `PostProcessChain.runBloomAndComposite` when ppChain is provided.
    ///
    /// - Parameters:
    ///   - commandBuffer: Active command buffer to encode all passes into.
    ///   - view: MTKView providing the current drawable.
    ///   - features: Audio feature vector (time/delta pre-filled by `draw(in:)`).
    ///   - stemFeatures: Per-stem features from the background separation pipeline.
    ///   - activePipeline: The preset's compiled G-buffer pipeline state.
    ///   - rayMarchState: Pipeline that owns G-buffer + lit textures and pass encoders.
    ///   - sceneOutputTexture: When non-nil (MV-2 mv_warp handoff), the final composite
    ///     is written here instead of the drawable and `commandBuffer.present` is skipped.
    ///     The caller (`.mvWarp` in `renderFrame`) reads this texture and presents via its
    ///     own blit pass.  Pass `nil` for normal (non-warp) ray march rendering.
    func drawWithRayMarch(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        activePipeline: MTLRenderPipelineState,
        rayMarchState: RayMarchPipeline,
        sceneOutputTexture: MTLTexture?
    ) {
        // When rendering to an offscreen texture for mv_warp, we don't need the drawable
        // during scene rendering. We still need it to exist for command buffer presentation
        // (done by the mv_warp blit pass instead). Acquire it only for the normal path.
        let outputTex: MTLTexture
        if let offscreen = sceneOutputTexture {
            outputTex = offscreen
        } else {
            guard let d = view.currentDrawable else { return }
            outputTex = d.texture
        }

        // Keep a reference to the drawable for presentation (normal path only).
        let drawable = sceneOutputTexture == nil
            ? view.currentDrawable
            : nil

        let size = view.drawableSize
        let width = Int(size.width)
        let height = Int(size.height)
        rayMarchState.ensureAllocated(width: width, height: height)

        // Update per-frame uniforms: accumulated audio time and aspect ratio.
        rayMarchState.sceneUniforms.sceneParamsA.x = features.accumulatedAudioTime
        rayMarchState.sceneUniforms.sceneParamsA.y = width > 0 ? Float(width) / Float(height) : 1.0

        // ── Option-A audio-reactive modulation (preset-agnostic) ──────────────
        // Drive light, fog, and camera dolly from the feature vector. Geometry
        // stays static; the music lights the space and moves the camera, not
        // the architecture. All modulations are relative to the preset's
        // JSON baseline (captured in `baseScene`), so the modulation is
        // additive on top of the preset's intent rather than clobbering it.

        let base = rayMarchState.baseScene

        // Constant-speed forward dolly: camera Z advances at a fixed
        // units/sec regardless of audio energy. Baseline Z comes from the
        // preset JSON; advance is pure wall-time so motion feels like
        // actual forward travel, not "faster when the song is loud".
        let dollyZ = base.cameraPosition.z + features.time * rayMarchState.cameraDollySpeed
        rayMarchState.sceneUniforms.cameraOriginAndFov.x = base.cameraPosition.x
        rayMarchState.sceneUniforms.cameraOriginAndFov.y = base.cameraPosition.y
        rayMarchState.sceneUniforms.cameraOriginAndFov.z = dollyZ

        // Light intensity pulses with the strongest of bass/mid/composite
        // onsets — `beat_bass` alone misses snare-driven tracks like Love
        // Shack where the kick drum is muted relative to the snare. Taking
        // the max across bands gives a beat pulse that fires for any genre.
        // Range: 0.4× (silence) → 3.0× (peak). 7.5× swing.
        let beatPulse = max(features.beatBass,
                            max(features.beatMid, features.beatComposite))
        let beatClamped = max(0, min(1, beatPulse))
        let intensityMul = 0.4 + beatClamped * 2.6
        rayMarchState.sceneUniforms.lightPositionAndIntensity.w = base.lightIntensity * intensityMul

        // Light colour shifts with valence: amplified from ±15% to ±40% per
        // channel so the warm/cool shift is clearly visible across genres.
        // Positive valence (happy/major key) → warm amber; negative (sad/
        // minor) → cold blue. The preset's palette still anchors at valence=0.
        let valence = max(-1, min(1, features.valence))
        let warm = max(0, valence)
        let cool = max(0, -valence)
        let tint = SIMD3<Float>(
            1.0 + warm * 0.40 - cool * 0.25,
            1.0 + warm * 0.15 - cool * 0.10,
            1.0 + cool * 0.40 - warm * 0.30
        )
        let modulatedColor = base.lightColor * tint
        rayMarchState.sceneUniforms.lightColor = SIMD4(modulatedColor, 0)

        // Fog density tracks arousal much more aggressively: calm → fog at
        // 2.0× baseline distance (long sightlines through clear corridor),
        // frantic → fog at 0.30× baseline (wall of mist closes in). The
        // ratio means high-arousal frames vanish to fog within ~5 bays
        // while calm frames see all the way to the horizon.
        let arousal = max(-1, min(1, features.arousal))
        let fogScale: Float = arousal >= 0
            ? (1.0 - arousal * 0.7)              // 1.0 → 0.30 as arousal 0 → 1
            : (1.0 + (-arousal) * 1.0)            // 1.0 → 2.0 as arousal 0 → -1
        rayMarchState.sceneUniforms.sceneParamsB.y = base.fogFar * fogScale

        // Corridor-path width modulation (Glass Brutalist only): fin
        // X-centre distance shrinks when bass is loud so the path between
        // the glass fins narrows. Writes into `cameraForward.w` — a free
        // SIMD4 lane read by both `sceneSDF` and `sceneMaterial` so the
        // glass/concrete classification stays consistent across the
        // deformation. Non-GB presets leave this unused (their shaders
        // don't read `cameraForward.w`).
        let bassDrive = max(0, min(1, features.subBass + features.lowBass))
        let finBase: Float = 1.20   // matches GB_GLASS_CX rest value
        let finNarrow: Float = 0.85 // at bassDrive=1
        let finCX = finBase - (finBase - finNarrow) * bassDrive
        rayMarchState.sceneUniforms.cameraForward.w = finCX

        // Resolve optional PostProcessChain for bloom: present only when .postProcess is
        // declared alongside .rayMarch in the preset's passes array.
        let passesIncludePostProcess = passesLock.withLock { activePasses.contains(.postProcess) }
        let ppChain = postProcessLock.withLock { postProcessChain }
        let chainForBloom: PostProcessChain? = passesIncludePostProcess ? ppChain : nil
        if let chain = chainForBloom {
            chain.ensureAllocated(width: width, height: height)
        }

        // Enable SSGI when the active passes array includes .ssgi.
        let ssgiActive = passesLock.withLock { activePasses.contains(.ssgi) }
        rayMarchState.ssgiEnabled = ssgiActive

        let noiseTextures = textureManagerLock.withLock { textureManager }
        let ibl = iblManagerLock.withLock { iblManager }
        rayMarchState.render(
            gbufferPipelineState: activePipeline,
            features: &features,
            fftBuffer: fftMagnitudeBuffer,
            waveformBuffer: waveformBuffer,
            stemFeatures: stemFeatures,
            outputTexture: outputTex,
            commandBuffer: commandBuffer,
            noiseTextures: noiseTextures,
            iblManager: ibl,
            postProcessChain: chainForBloom
        )

        // Present only when rendering directly to the drawable (normal path).
        // When sceneOutputTexture is non-nil, the mv_warp blit pass presents instead.
        if let drawable = drawable {
            commandBuffer.present(drawable)
        }
    }

    // swiftlint:enable function_parameter_count
}
