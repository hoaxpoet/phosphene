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
import QuartzCore
import Shared
import os.log

private let rmLogger = Logger(subsystem: "com.phosphene.renderer", category: "RenderPipeline")

// MARK: - Texture + IBL Attachment

extension RenderPipeline {

    // MARK: - Marched-pixel budget (PERF.14)

    /// Largest marched pixel count measured on the fast side of the PERF.14 cliff.
    ///
    /// Volumetric Lithograph at `render_scale` 0.5 cost **175 ms** at 3840×2160 — 1920×1080
    /// marched — and **≤ 15 ms** at 0.4, which marches 1536×864. An 11.7× drop from a 1.56×
    /// pixel cut, live, same build, same preset. Ray-march cost is a STEP here, not a curve,
    /// so "ms per megapixel" does not predict it and a constant scale walks off the step as
    /// soon as the window grows. 1536×864 is the largest size measured below it.
    static let marchedPixelBudget = 1536 * 864

    /// Ray-march scale for a drawable of `width` × `height`.
    ///
    /// A `declared` scale of 1.0 means the preset never opted into scaled marching; it is
    /// returned untouched so the catalog's full-resolution presets keep the looks they were
    /// certified at. A lower value is reduced further when needed to stay inside
    /// ``marchedPixelBudget``, then clamped to the [0.4, 1.0] floor — below 0.4 the upscale
    /// stops being softness and starts being a different image.
    ///
    /// The budget only ever lowers the scale, so a preset declaring 0.5 keeps 0.5 at 1080p
    /// and in the 2884×1662 window VL was certified in, and gets 0.4 at 4K automatically.
    ///
    /// ponytail: one budget for the whole catalog. Per-preset budgets when a preset needs a
    /// different one, which none does today.
    static func marchScale(declared: Float, width: Int, height: Int) -> Float {
        guard declared < 1.0, width > 0, height > 0 else { return min(max(declared, 0.4), 1.0) }
        let budgetScale = (Float(marchedPixelBudget) / Float(width * height)).squareRoot()
        return min(max(min(declared, budgetScale), 0.4), 1.0)
    }
}

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

    // swiftlint:disable function_parameter_count function_body_length
    // `drawWithRayMarch` takes 7 parameters — the minimal render-pass context plus
    // an optional scene output texture for the mv_warp handoff. PERF.2-pass adds
    // a 7-line `onRayMarchPassTimingObserved` callback fire to surface per-sub-pass
    // timings, pushing the body just past the 60-line limit.

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
    @MainActor
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
            guard let desc = instrumentedDrawable(
                from: view, commandBuffer: commandBuffer, site: "rayMarch.output.drawable"
            ) else { return }
            outputTex = desc.texture
        }

        // Keep a reference to the drawable for presentation (normal path only).
        let drawable = sceneOutputTexture == nil
            ? instrumentedDrawable(
                from: view, commandBuffer: commandBuffer, site: "rayMarch.present.drawable")
            : nil

        let size = view.drawableSize
        let width = Int(size.width)
        let height = Int(size.height)
        // BUG-101 — the marcher may shade fewer pixels than the drawable. The composite pass
        // samples `litTexture` by UV through a linear sampler, so a smaller source upscales
        // with no extra pass; PERF.13 moved the post-process chain to march size too, so bloom
        // and ACES run at the marcher's scale and the single upscale happens at composite.
        //
        // The 0.4 floor is a HARD CLAMP, not a suggestion: a sidecar declaring a smaller
        // render_scale silently gets 0.4. PERF.14 probes at 0.25 and 0.35 both ran at 0.4 and
        // returned identical timings before anyone noticed. If you lower it, check here first.
        let marchScale = Self.marchScale(declared: rayMarchState.renderScale, width: width, height: height)
        let marchWidth = max(Int((Float(width) * marchScale).rounded()), 1)
        let marchHeight = max(Int((Float(height) * marchScale).rounded()), 1)
        rayMarchState.ensureAllocated(width: marchWidth, height: marchHeight)

        // Update per-frame uniforms: accumulated audio time, aspect ratio, and step-count multiplier.
        // MFX.1: lightingParams.z carries the PREVIOUS frame's accumulated audio
        // time so a preset can derive where its geometry was last frame
        // (`scenePrevPosition` → MetalFX motion vectors). Written before the new
        // value lands in sceneParamsA.x.
        rayMarchState.sceneUniforms.lightingParams.z = rayMarchState.sceneUniforms.sceneParamsA.x
        rayMarchState.sceneUniforms.sceneParamsA.x = features.accumulatedAudioTime
        // CLEAN.4.3: guard the divisor (height), not width — a zero-height drawable
        // divided to +inf/NaN aspect. Identical for any height > 0.
        rayMarchState.sceneUniforms.sceneParamsA.y = height > 0 ? Float(width) / Float(height) : 1.0
        // sceneParamsB.z carries the frame-budget step-count multiplier (D-057).
        // Default 1.0 = 128 steps; 0.75 = 96 steps (reducedRayMarch quality level).
        rayMarchState.sceneUniforms.sceneParamsB.z = rayMarchState.stepCountMultiplier

        rayMarchState.applyAudioModulation(features: features)

        // Resolve optional PostProcessChain for bloom: present only when .postProcess is
        // declared alongside .rayMarch in the preset's passes array.
        let passesIncludePostProcess = passesLock.withLock { activePasses.contains(.postProcess) }
        let ppChain = postProcessLock.withLock { postProcessChain }
        let chainForBloom: PostProcessChain? = passesIncludePostProcess ? ppChain : nil
        if let chain = chainForBloom {
            // BUG-101 — the chain renders at the SAME scale as the marcher. `runComposite`
            // writes into the drawable texture, so its internal scene/bloom targets being
            // smaller means one upscale at the final step rather than a full-resolution bloom
            // over an upscaled image. PERF.12 measured the cost of not doing this: with the
            // marcher alone scaled, VL only improved 1.5x live because the chain kept running
            // at full drawable size and did not shrink with it.
            chain.ensureAllocated(width: marchWidth, height: marchHeight)
        }

        // Enable SSGI when the active passes array includes .ssgi.
        let ssgiActive = passesLock.withLock { activePasses.contains(.ssgi) }
        rayMarchState.ssgiEnabled = ssgiActive
        // Propagate accessibility flag — a11y gate only. Governor gate managed via
        // applyQualityLevel(_:) → setGovernorSkipsSSGI. D-054, D-057.
        rayMarchState.setA11yReducedMotion(frameReduceMotion)

        let noiseTextures = textureManagerLock.withLock { textureManager }
        let ibl = iblManagerLock.withLock { iblManager }
        // Snapshot slot-8 per-preset buffer (D-LM-buffer-slot-8). Slot 8 is
        // read by the lighting pass only. (The §5.8 stage-rig slot-9 path
        // was retired in V.9 Session 4.5c — no longer in the preamble.)
        let presetBuf3 = directPresetFragmentBuffer3Lock.withLock { directPresetFragmentBuffer3 }
        let presetHeightTex = rayMarchPresetHeightTextureLock.withLock { rayMarchPresetHeightTexture }

        let frameDt = features.deltaTime > 0 ? features.deltaTime : 1.0 / 60.0

        // V.9 Session 4.5c / D-127 — aurora-reflection drum-energy smoother.
        // The Ferrofluid Ocean matID == 2 sky function (rm_ferrofluidSky) reads
        // `stems.drums_energy_dev_smoothed` for the curtain intensity envelope.
        // Smoothing runs unconditionally for every ray-march preset — cost is
        // one float MAD and an EMA — so we keep the dispatch logic in one
        // place rather than checking the active preset name here. Non-aurora
        // presets simply don't read the smoothed slot.
        //
        // 150 ms τ exponential smoother on `drumsEnergyDev`. EMA blend coefficient
        // `α = 1 − exp(−dt / τ)` gives frame-rate-independent smoothing. At 60 Hz
        // and τ=0.15 s, α ≈ 0.105 → step response ~95% in ~430 ms (3τ).
        // BUG-041 — the smoother alone is NOT enough at track starts: the
        // per-stem deviation EMA re-seeds when `StemAnalyzer` resets per track
        // and overswings 1.2–3.3× for the first ~10 s (measured on session
        // `2026-06-10T14-55-32Z` — smoothed peaks 2.35 / 1.37 / 1.23 on the
        // exact tracks Matt flagged as flashing, vs 0.23 on calm Love Rehab,
        // settling by ~10 s). A per-track linear warmup (0 → 1 over 10 s,
        // reset in `resetAccumulatedAudioTime()`) gates the driver, so the
        // aurora blooms in over a track's opening instead of flashing. Steady
        // state is untouched (the gate is 1.0 after 10 s). Step extracted to
        // `auroraDriverStep` so the real-session replay test exercises the
        // exact production arithmetic.
        let auroraStep = Self.auroraDriverStep(
            smoothed: auroraDrumsSmoothed,
            warmup01: auroraTrackWarmup01,
            drumsDev: stemFeatures.drumsEnergyDev,
            dt: frameDt)
        auroraDrumsSmoothed = auroraStep.smoothed
        auroraTrackWarmup01 = auroraStep.warmup01
        var lightingStems = stemFeatures
        lightingStems.drumsEnergyDevSmoothed = auroraStep.output

        // FBS.S5 (D-158) — aurora hue driver. The sky shader now reads ONE
        // CPU-smoothed palette phase instead of computing per-pixel from raw
        // `vocals_pitch_hz`/`confidence` (the gate-flapping strobe the S5
        // forensics convicted). Runs unconditionally like the drums smoother;
        // non-aurora presets don't read the slot.
        auroraHuePhase = Self.auroraHueStep(
            smoothedPhase: auroraHuePhase,
            pitchHz: stemFeatures.vocalsPitchHz,
            pitchConfidence: stemFeatures.vocalsPitchConfidence,
            valence: features.valence,
            dt: frameDt)
        lightingStems.auroraPalettePhase = auroraHuePhase

        // FBS Stage 2 — passage-loudness envelope for the punch height
        // (energy sets SIZE, the beat keeps the timing). Patched into the
        // stems snapshot like the two drivers above; only FFO reads it.
        punchEnergySmoothed = Self.punchEnergyStep(
            smoothed: punchEnergySmoothed,
            totalStemEnergy: stemFeatures.drumsEnergy + stemFeatures.bassEnergy
                + stemFeatures.vocalsEnergy + stemFeatures.otherEnergy,
            dt: frameDt)
        lightingStems.totalEnergySmoothed = punchEnergySmoothed

        // BUG-047 — aurora orbit azimuth, integrated (arousal scales the
        // speed of each increment; the old shader-side speed × total product
        // rescaled history whenever arousal moved).
        let aatDelta = lastAuroraAat.map { features.accumulatedAudioTime - $0 } ?? 0
        lastAuroraAat = features.accumulatedAudioTime
        auroraOrbitAzimuth = Self.auroraOrbitStep(
            azimuth: auroraOrbitAzimuth, aatDelta: aatDelta, arousal: features.arousal)
        lightingStems.auroraOrbitAzimuth = auroraOrbitAzimuth

        rayMarchState.render(
            gbufferPipelineState: activePipeline,
            features: &features,
            fftBuffer: fftMagnitudeBuffer,
            waveformBuffer: waveformBuffer,
            stemFeatures: lightingStems,
            outputTexture: outputTex,
            commandBuffer: commandBuffer,
            noiseTextures: noiseTextures,
            iblManager: ibl,
            postProcessChain: chainForBloom,
            presetFragmentBuffer3: presetBuf3,
            presetHeightTexture: presetHeightTex
        )

        // PERF.2-pass — surface per-sub-pass timings to the recorder so BUG-019
        // diagnosis can drill below renderframe_cpu_ms. Reads from
        // `rayMarchState`'s `lastFooPassMs` properties (set inside `render(...)`
        // on this same MainActor thread — no synchronization needed).
        onRayMarchPassTimingObserved?(
            rayMarchState.lastGBufferPassMs,
            rayMarchState.lastLightingPassMs,
            rayMarchState.lastSSGIPassMs,
            rayMarchState.lastPostProcessPassMs
        )

        // Present only when rendering directly to the drawable (normal path).
        // When sceneOutputTexture is non-nil, the mv_warp blit pass presents instead.
        if let drawable = drawable {
            instrumentedPresent(drawable, on: commandBuffer)
        }
    }

    // swiftlint:enable function_parameter_count function_body_length

    // MARK: - Audio-Reactive Modulation

}
