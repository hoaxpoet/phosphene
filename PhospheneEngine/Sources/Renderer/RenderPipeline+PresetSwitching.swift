import Metal
import Shared
import os.log

private let presetLogger = Logger(subsystem: "com.phosphene.renderer", category: "RenderPipeline")

extension RenderPipeline {

    // MARK: - Preset Switching

    /// Replace the active render pipeline state (e.g., when switching presets).
    /// Thread-safe — can be called from any queue.
    public func setActivePipelineState(_ newState: MTLRenderPipelineState) {
        pipelineLock.withLock { pipelineState = newState }
        presetLogger.info("Active pipeline state updated")
    }

    /// Set feedback parameters for the active preset. Pass nil to disable feedback.
    /// Thread-safe — can be called from any queue.
    public func setFeedbackParams(_ params: FeedbackParams?) {
        feedbackLock.withLock { currentFeedbackParams = params }
    }

    /// Set the additive-blended pipeline state for feedback composite pass.
    /// Thread-safe — can be called from any queue.
    public func setFeedbackComposePipeline(_ state: MTLRenderPipelineState?) {
        feedbackLock.withLock { feedbackComposePipelineState = state }
    }

    /// Update the beat value in feedback params from live audio features.
    /// Called from the analysis queue each frame.
    public func updateFeedbackBeatValue(from features: FeatureVector) {
        feedbackLock.withLock {
            currentFeedbackParams?.beatValue = max(features.beatBass, features.beatComposite)
        }
    }

    /// Attach a mesh generator for mesh shader presets.
    /// Pass `nil` to detach. Thread-safe — can be called from any queue.
    public func setMeshGenerator(_ generator: MeshGenerator?) {
        meshLock.withLock { meshGenerator = generator }
        presetLogger.info("Mesh generator \(generator != nil ? "attached" : "detached")")
    }

    /// Attach a per-frame tick closure for mesh preset state updates.
    /// Called once per frame before the mesh draw. Pass `nil` to detach.
    /// Thread-safe — can be called from any queue.
    public func setMeshPresetTick(_ tick: (@Sendable (FeatureVector, StemFeatures) -> Void)?) {
        meshPresetTickLock.withLock { meshPresetTick = tick }
    }

    /// Attach a particle system to the render loop.
    /// Accepts any `ParticleGeometry` conformer (D-097). Thread-safe — can be
    /// called from any queue.
    public func setParticleGeometry(_ geometry: (any ParticleGeometry)?) {
        particleLock.withLock { particleGeometry = geometry }
    }

    /// Attach (or clear) the additive scene-geometry overlay drawn into the mv_warp
    /// scene texture after the background fragment — the Dragon Bloom spectral
    /// strands (D-137). Pass `nil` state to clear. Thread-safe.
    public func setSceneGeometry(
        _ state: MTLRenderPipelineState?,
        vertexCount: Int,
        instanceCount: Int,
        primitive: MTLPrimitiveType
    ) {
        sceneGeometryLock.withLock {
            sceneGeometryState = state
            sceneGeometryVertexCount = vertexCount
            sceneGeometryInstanceCount = instanceCount
            sceneGeometryPrimitive = primitive
        }
    }

    /// Set the Fata Morgana custom-shape pipelines (FM.L2, D-139) — additive (neon
    /// blobs) + normal-blend (textured echo). Pass `nil`/`nil` to clear. Drawn on top
    /// of the warp target in `drawWithFataMorgana`. Thread-safe (mvWarpLock).
    public func setFataShapePipelines(
        additive: MTLRenderPipelineState?,
        normal: MTLRenderPipelineState?
    ) {
        mvWarpLock.withLock {
            fataShapeAdditive = additive
            fataShapeNormal = normal
        }
        // Re-roll the horizon-glow phase so each session opens on a different point in
        // the spectrum cycle (Matt: "different on startup"). One full slow_roam_sin
        // period (~1257 s) of spread. Only on activation, not on clear.
        if additive != nil {
            fataGlowSeedJitter = Float.random(in: 0..<1300)
        }
    }

    /// Set the mv_warp chromatic colour-separation amount (Dragon Bloom L3, D-137).
    /// 0 ⇒ identity (the warp fragment leaves feedback colour unchanged — every
    /// other mv_warp preset). Thread-safe.
    public func setMVWarpChromatic(_ amount: Float) {
        mvWarpLock.withLock { mvWarpChromatic = amount }
    }

    /// Set the mv_warp display-stage post params (Dragon Bloom L4, D-137).
    /// `invert` = source.milk `bInvert` (flips the cool full-warp fill to warm),
    /// `echo` = `fVideoEchoAlpha`, `gamma` = `fGammaAdj`. Display-only (applied in the
    /// blit, never fed back). `(0, 0, 1)` ⇒ identity blit (every other mv_warp preset
    /// unchanged).
    ///
    /// `beatPulse` (Skein.ENGINE.1.1, D-143): whether the per-frame comp beat pump fires
    /// at the blit (`mvWarpBeatPulse` → `post.w`). Formerly keyed on `sceneGeometryState
    /// != nil`; now per-preset so a marks-on-top preset that wants a quiet canvas (Skein)
    /// gets true comp-identity. Defaults false — only Dragon Bloom passes true, and it is
    /// the only `strandsOnTop` preset today, so all existing presets are byte-identical.
    /// Thread-safe.
    public func setMVWarpPost(invert: Float, echo: Float = 0, gamma: Float = 1, beatPulse: Bool = false) {
        mvWarpLock.withLock {
            mvWarpInvert = invert
            mvWarpEcho = echo
            mvWarpGamma = gamma
            mvWarpBeatPulseEnabled = beatPulse
        }
    }

    /// Attach a post-process chain for bloom + ACES when passes include `.postProcess`.
    /// Pass `nil` to detach. Thread-safe — can be called from any queue.
    public func setPostProcessChain(_ chain: PostProcessChain?) {
        postProcessLock.withLock { postProcessChain = chain }
        presetLogger.info("Post-process chain \(chain != nil ? "attached" : "detached")")
    }

    /// Attach a deferred ray march pipeline when passes include `.rayMarch`.
    /// Pass `nil` to detach. Thread-safe — can be called from any queue.
    public func setRayMarchPipeline(_ pipeline: RayMarchPipeline?) {
        rayMarchLock.withLock { rayMarchPipeline = pipeline }
        presetLogger.info("Ray march pipeline \(pipeline != nil ? "attached" : "detached")")
    }

    /// Update the live audio features from MIR analysis.
    /// Thread-safe — called from the analysis queue each frame.
    public func setFeatures(_ features: FeatureVector) {
        featuresLock.withLock {
            // Preserve valence/arousal — produced by mood classifier on a slower
            // cadence; without this they reset to 0 every MIR frame.
            let valence = latestFeatures.valence
            let arousal = latestFeatures.arousal
            latestFeatures = features
            latestFeatures.valence = valence
            latestFeatures.arousal = arousal
        }
    }

    /// Update only the mood components from the mood classifier.
    /// Preserves all other MIR-populated fields. Thread-safe.
    public func setMood(valence: Float, arousal: Float) {
        featuresLock.withLock {
            latestFeatures.valence = valence
            latestFeatures.arousal = arousal
        }
    }

    /// Update per-stem features from the background stem pipeline.
    /// Thread-safe — called from the stem queue at ~5s cadence.
    ///
    /// CSP.3 (2026-05-27) — `cachedBassProportion` is **preserved** across
    /// updates: the incoming `features.cachedBassProportion` is ignored and
    /// the field retains whatever value was last set via
    /// `setCachedBassProportion(_:)`. This implements the "frozen for the
    /// track's duration" contract — live per-frame stem analysis must not
    /// overwrite the cached preview-derived proportion that Ferrofluid
    /// Ocean's spike-height baseline depends on.
    public func setStemFeatures(_ features: StemFeatures) {
        stemFeaturesLock.withLock {
            var next = features
            next.cachedBassProportion = latestStemFeatures.cachedBassProportion
            latestStemFeatures = next
        }
    }

    /// CSP.3 — install the cached bass proportion for the current track.
    /// Called once at track-change from the app layer's `resetStemPipeline`,
    /// computed from `CachedTrackData.stemFeatures` (the preview-analysis
    /// snapshot). Preserved across all subsequent `setStemFeatures(_:)`
    /// updates until the next call to this method. Thread-safe.
    public func setCachedBassProportion(_ value: Float) {
        stemFeaturesLock.withLock {
            latestStemFeatures.cachedBassProportion = value
        }
    }

    /// Read the latest per-stem features snapshot. Thread-safe.
    /// Returns `.zero` until the first stem separation completes.
    public func currentStemFeatures() -> StemFeatures {
        stemFeaturesLock.withLock { latestStemFeatures }
    }

    /// Attach a per-preset fragment buffer for direct-fragment mv_warp presets (bound at buffer(6)).
    /// Pass nil to detach. Thread-safe — can be called from any queue.
    public func setDirectPresetFragmentBuffer(_ buffer: MTLBuffer?) {
        directPresetFragmentBufferLock.withLock { directPresetFragmentBuffer = buffer }
    }

    /// Attach a secondary per-preset fragment buffer for direct-fragment mv_warp presets (bound at buffer(7)).
    /// Pass nil to detach. Thread-safe — can be called from any queue.
    public func setDirectPresetFragmentBuffer2(_ buffer: MTLBuffer?) {
        directPresetFragmentBuffer2Lock.withLock { directPresetFragmentBuffer2 = buffer }
    }

    /// Attach a tertiary per-preset fragment buffer (bound at buffer(8)).
    ///
    /// Bound at fragment slot 8 in every per-frame uniform binding site that
    /// also binds slots 6 / 7 (staged composition, mv_warp scene-to-texture,
    /// direct-pass) plus the ray-march lighting pass. The G-buffer pass does
    /// NOT bind this slot — only lighting / composite consumers see slot 8.
    /// First planned consumer: Lumen Mosaic (Phase LM) for `LumenPatternState`.
    /// Pass nil to detach. Thread-safe — can be called from any queue. (D-LM-buffer-slot-8)
    public func setDirectPresetFragmentBuffer3(_ buffer: MTLBuffer?) {
        directPresetFragmentBuffer3Lock.withLock { directPresetFragmentBuffer3 = buffer }
    }

    /// Attach a per-preset baked height field for ray-march presets (bound at fragment texture(10)).
    ///
    /// Bound at fragment texture slot 10 of the ray-march G-buffer pass.
    /// Non-Ferrofluid presets pass `nil` so the zero-filled 1×1
    /// `RayMarchPipeline.ferrofluidHeightPlaceholderTexture` is bound — Metal
    /// validation requires every declared texture to be bound at draw time.
    /// First consumer: Ferrofluid Ocean V.9's `FerrofluidParticles`
    /// (V.9 Session 4.5b Phase 1). Thread-safe — can be called from any queue.
    public func setRayMarchPresetHeightTexture(_ texture: MTLTexture?) {
        rayMarchPresetHeightTextureLock.withLock { rayMarchPresetHeightTexture = texture }
    }

    /// Attach the mesh G-buffer encode closure (V.9 Session 4.5c Phase 1
    /// Step B). When set, the ray-march pipeline dispatches via
    /// `runMeshGBufferPass` instead of the SDF `runGBufferPass` —
    /// replacing the SDF geometry path entirely for the active preset.
    /// First consumer: Ferrofluid Ocean's `FerrofluidMesh`. Pass nil to
    /// return to SDF. Thread-safe.
    public func setMeshGBufferEncoder(_ encoder: RayMarchPipeline.MeshGBufferEncode?) {
        rayMarchLock.withLock {
            rayMarchPipeline?.setMeshGBufferEncoder(encoder)
        }
    }

    /// Attach a dynamic text overlay for presets that declare `text_overlay: true`.
    /// The overlay texture is bound at fragment texture(12) during direct-pass draws.
    /// Pass `nil` to detach (e.g. on preset switch away from a text-overlay preset).
    /// Thread-safe — can be called from any queue.
    public func setDynamicTextOverlay(_ overlay: DynamicTextOverlay?) {
        dynamicTextOverlayLock.withLock { dynamicTextOverlay = overlay }
    }

    /// Set the per-frame callback that populates the dynamic text overlay.
    /// Called once per frame from `drawDirect` if an overlay is attached.
    /// Pass `nil` to detach. Thread-safe — can be called from any queue.
    public func setTextOverlayCallback(_ callback: ((DynamicTextOverlay, FeatureVector) -> Void)?) {
        textOverlayCallbackLock.withLock { textOverlayCallback = callback }
    }
}
