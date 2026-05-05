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

    /// Attach a per-preset world-state MTLBuffer for mesh presets (bound at object/mesh buffer(1)).
    /// Pass `nil` to detach. Thread-safe — can be called from any queue.
    public func setMeshPresetBuffer(_ buffer: MTLBuffer?) {
        meshPresetBufferLock.withLock { meshPresetBuffer = buffer }
    }

    /// Attach a per-frame tick closure for mesh preset state updates.
    /// Called once per frame before the mesh draw. Pass `nil` to detach.
    /// Thread-safe — can be called from any queue.
    public func setMeshPresetTick(_ tick: (@Sendable (FeatureVector, StemFeatures) -> Void)?) {
        meshPresetTickLock.withLock { meshPresetTick = tick }
    }

    /// Attach a particle system to the render loop.
    /// Thread-safe — can be called from any queue.
    public func setParticleGeometry(_ geometry: ProceduralGeometry?) {
        particleLock.withLock { particleGeometry = geometry }
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
    public func setStemFeatures(_ features: StemFeatures) {
        stemFeaturesLock.withLock { latestStemFeatures = features }
    }

    /// Attach a per-preset fragment buffer for mesh presets (bound at fragment buffer(4)).
    /// Pass nil to detach. Thread-safe — can be called from any queue.
    public func setMeshPresetFragmentBuffer(_ buffer: MTLBuffer?) {
        meshPresetFragmentBufferLock.withLock { meshPresetFragmentBuffer = buffer }
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
    public func setTextOverlayCallback(_ callback: ((DynamicTextOverlay) -> Void)?) {
        textOverlayCallbackLock.withLock { textOverlayCallback = callback }
    }
}
