// RenderPipeline — MTKViewDelegate that drives the audio-reactive render loop.
// Supports both direct rendering and Milkdrop-style feedback (double-buffered ping-pong).
// Binds FFT magnitude and PCM waveform UMA buffers to a full-screen fragment shader.

import Metal
import MetalKit
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "RenderPipeline")

public final class RenderPipeline: NSObject, Rendering, @unchecked Sendable {

    // MARK: - Metal State

    let context: MetalContext
    var pipelineState: MTLRenderPipelineState
    let pipelineLock = NSLock()

    // MARK: - Audio Buffers (UMA zero-copy — written by audio thread, read by GPU)

    let fftMagnitudeBuffer: MTLBuffer   // 512 floats from FFTProcessor
    let waveformBuffer: MTLBuffer       // 2048 interleaved floats from AudioBuffer

    // MARK: - Particle System

    /// Optional particle geometry — compute update + point-sprite rendering.
    var particleGeometry: ProceduralGeometry?
    let particleLock = NSLock()

    // MARK: - Live Audio Features

    /// Latest audio features from MIR analysis (band energy, beats, spectral).
    /// Set from the analysis queue, read in the render loop.
    var latestFeatures = FeatureVector.zero
    let featuresLock = NSLock()

    // MARK: - Per-Stem Features

    /// Latest per-stem features from the background stem pipeline.
    /// Set from the stem queue (~5s cadence), read every frame in the render loop.
    var latestStemFeatures = StemFeatures.zero
    let stemFeaturesLock = NSLock()

    // MARK: - Feedback Textures (Milkdrop-style ping-pong)

    /// Double-buffered feedback textures. Index flips each frame.
    var feedbackTextures: [MTLTexture] = []
    /// Which texture is the current write target (0 or 1).
    var feedbackIndex: Int = 0
    /// Current feedback parameters (from preset descriptor).
    var currentFeedbackParams: FeedbackParams?
    /// Additive-blended pipeline for the feedback composite pass.
    var feedbackComposePipelineState: MTLRenderPipelineState?
    let feedbackLock = NSLock()

    /// Built-in pipeline states for feedback warp and blit passes.
    let feedbackWarpPipelineState: MTLRenderPipelineState
    let feedbackBlitPipelineState: MTLRenderPipelineState
    /// Bilinear, clamp-to-edge sampler for feedback texture reads.
    let feedbackSamplerState: MTLSamplerState

    // MARK: - Mesh Shader State

    /// Optional mesh generator — attached when the active preset has `useMeshShader: true`.
    var meshGenerator: MeshGenerator?
    let meshLock = NSLock()

    // MARK: - Post-Process Chain

    /// Optional HDR post-process chain — bloom + ACES tone mapping.
    var postProcessChain: PostProcessChain?
    let postProcessLock = NSLock()

    // MARK: - ICB State (Increment 3.5)

    /// Optional ICB state for GPU-driven indirect command buffer rendering.
    var icbState: IndirectCommandBufferState?
    let icbLock = NSLock()

    // MARK: - Ray March Pipeline (Increment 3.14)

    /// Optional deferred ray march pipeline — G-buffer + PBR lighting + composite.
    var rayMarchPipeline: RayMarchPipeline?
    let rayMarchLock = NSLock()

    // MARK: - Noise Textures (Increment 3.13)

    /// Optional noise texture manager — binds 5 pre-computed textures at slots 4–8.
    var textureManager: TextureManager?
    let textureManagerLock = NSLock()

    // MARK: - IBL Textures (Increment 3.16)

    /// Optional IBL texture manager — binds irradiance, prefiltered env, and BRDF LUT at slots 9–11.
    var iblManager: IBLManager?
    let iblManagerLock = NSLock()

    // MARK: - Render Graph (Increment 3.6)

    /// Active render passes declared by the current preset.
    ///
    /// `renderFrame` iterates this array and dispatches to the first pass whose
    /// required subsystem is available, replacing the old priority-ordered boolean
    /// flag chain.  Set atomically via `setActivePasses(_:)`.
    var activePasses: [RenderPass] = [.direct]
    let passesLock = NSLock()

    // MARK: - Accumulated Audio Time (Increment 3.15)

    /// Energy-weighted running time — accumulates faster during loud passages.
    /// Reset to 0 on track change via `resetAccumulatedAudioTime()`.
    private var _accumulatedAudioTime: Float = 0
    let audioTimeLock = NSLock()

    /// Current accumulated audio time (energy-weighted, reset on track change).
    public var accumulatedAudioTime: Float {
        audioTimeLock.withLock { _accumulatedAudioTime }
    }

    /// Reset accumulated audio time to zero. Call on track change.
    public func resetAccumulatedAudioTime() {
        audioTimeLock.withLock { _accumulatedAudioTime = 0 }
    }

    /// Advance accumulated audio time by one frame.
    /// `energy` should be `max(0, (bass + mid + treble) / 3.0)`.
    /// Called by `draw(in:)` each frame; also accessible from tests via `@testable import`.
    func stepAccumulatedTime(energy: Float, deltaTime: Float) {
        audioTimeLock.withLock {
            _accumulatedAudioTime += max(0, energy) * deltaTime
        }
    }

    // MARK: - Timing

    let startTime: CFAbsoluteTime
    var lastFrameTime: CFAbsoluteTime

    // MARK: - Init

    /// Create the render pipeline with audio buffer bindings and feedback infrastructure.
    ///
    /// - Parameters:
    ///   - context: Metal context (device, queue, semaphore).
    ///   - shaderLibrary: Compiled shader library for pipeline state creation.
    ///   - fftBuffer: UMA buffer containing 512 FFT magnitude bins (from FFTProcessor).
    ///   - waveformBuffer: UMA buffer containing interleaved stereo PCM (from AudioBuffer).
    public init(
        context: MetalContext,
        shaderLibrary: ShaderLibrary,
        fftBuffer: MTLBuffer,
        waveformBuffer: MTLBuffer
    ) throws {
        self.context = context
        self.fftMagnitudeBuffer = fftBuffer
        self.waveformBuffer = waveformBuffer
        self.startTime = CFAbsoluteTimeGetCurrent()
        self.lastFrameTime = self.startTime

        // Create render pipeline state: fullscreen_vertex → waveform_fragment.
        self.pipelineState = try shaderLibrary.renderPipelineState(
            named: "waveform",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "waveform_fragment",
            pixelFormat: context.pixelFormat,
            device: context.device
        )

        // Feedback warp pipeline: fullscreen_vertex → feedback_warp_fragment.
        self.feedbackWarpPipelineState = try shaderLibrary.renderPipelineState(
            named: "feedback_warp",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "feedback_warp_fragment",
            pixelFormat: context.pixelFormat,
            device: context.device
        )

        // Feedback blit pipeline: fullscreen_vertex → feedback_blit_fragment.
        self.feedbackBlitPipelineState = try shaderLibrary.renderPipelineState(
            named: "feedback_blit",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "feedback_blit_fragment",
            pixelFormat: context.pixelFormat,
            device: context.device
        )

        // Bilinear, clamp-to-edge sampler for feedback texture reads.
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        guard let sampler = context.device.makeSamplerState(descriptor: samplerDesc) else {
            throw MetalContextError.noDevice
        }
        self.feedbackSamplerState = sampler

        super.init()
        logger.info("RenderPipeline initialized with render-graph support")
    }

    // MARK: - Render Graph

    /// Set the active render passes for the current preset.
    ///
    /// Called from `applyPreset` after all subsystems are configured.
    /// `renderFrame` iterates this array each frame to select the draw path.
    /// Thread-safe — can be called from any queue.
    public func setActivePasses(_ passes: [RenderPass]) {
        passesLock.withLock { activePasses = passes }
        logger.info("Active passes: [\(passes.map(\.rawValue).joined(separator: ", "))]")
    }

    /// The currently active render passes (snapshot for testing / diagnostics).
    public var currentPasses: [RenderPass] {
        passesLock.withLock { activePasses }
    }

    // MARK: - Preset Switching

    /// Replace the active render pipeline state (e.g., when switching presets).
    /// Thread-safe — can be called from any queue.
    public func setActivePipelineState(_ newState: MTLRenderPipelineState) {
        pipelineLock.withLock {
            pipelineState = newState
        }
        logger.info("Active pipeline state updated")
    }

    /// Set feedback parameters for the active preset. Pass nil to disable feedback.
    /// Thread-safe — can be called from any queue.
    public func setFeedbackParams(_ params: FeedbackParams?) {
        feedbackLock.withLock {
            currentFeedbackParams = params
        }
    }

    /// Set the additive-blended pipeline state for feedback composite pass.
    /// Thread-safe — can be called from any queue.
    public func setFeedbackComposePipeline(_ state: MTLRenderPipelineState?) {
        feedbackLock.withLock {
            feedbackComposePipelineState = state
        }
    }

    /// Update the beat value in feedback params from live audio features.
    /// Called from the analysis queue each frame. The beat source was set on preset switch.
    public func updateFeedbackBeatValue(from features: FeatureVector) {
        feedbackLock.withLock {
            // Use beatBass as the default beat source (matches most presets).
            // The full beatSource selection would require storing the PresetDescriptor,
            // but beatBass is correct for the Starburst preset (beat_source: "bass").
            currentFeedbackParams?.beatValue = max(features.beatBass, features.beatComposite)
        }
    }

    /// Attach a mesh generator for mesh shader presets.
    ///
    /// Pass a non-nil generator to route `draw(in:)` through `drawWithMeshShader`.
    /// Pass `nil` to detach.  Thread-safe — can be called from any queue.
    public func setMeshGenerator(_ generator: MeshGenerator?) {
        meshLock.withLock {
            meshGenerator = generator
        }
        logger.info("Mesh generator \(generator != nil ? "attached" : "detached")")
    }

    /// Attach a particle system to the render loop.
    /// Thread-safe — can be called from any queue.
    public func setParticleGeometry(_ geometry: ProceduralGeometry?) {
        particleLock.withLock {
            particleGeometry = geometry
        }
    }

    /// Attach a post-process chain to the render loop.
    ///
    /// Pass a non-nil chain to enable bloom + ACES tone mapping when the active
    /// passes include `.postProcess`.  Pass `nil` to detach.
    /// Thread-safe — can be called from any queue.
    public func setPostProcessChain(_ chain: PostProcessChain?) {
        postProcessLock.withLock {
            postProcessChain = chain
        }
        logger.info("Post-process chain \(chain != nil ? "attached" : "detached")")
    }

    /// Attach a deferred ray march pipeline to the render loop.
    ///
    /// Pass a non-nil pipeline to enable G-buffer + PBR lighting when the active
    /// passes include `.rayMarch`.  Pass `nil` to detach.
    /// Thread-safe — can be called from any queue.
    public func setRayMarchPipeline(_ pipeline: RayMarchPipeline?) {
        rayMarchLock.withLock {
            rayMarchPipeline = pipeline
        }
        logger.info("Ray march pipeline \(pipeline != nil ? "attached" : "detached")")
    }

    /// Update the live audio features from MIR analysis.
    /// Thread-safe — called from the analysis queue each frame.
    public func setFeatures(_ features: FeatureVector) {
        featuresLock.withLock {
            latestFeatures = features
        }
    }

    /// Update per-stem features from the background stem pipeline.
    /// Thread-safe — called from the stem queue at ~5s cadence.
    public func setStemFeatures(_ features: StemFeatures) {
        stemFeaturesLock.withLock {
            latestStemFeatures = features
        }
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)

        // Allocate double-buffered feedback textures at drawable size.
        var textures: [MTLTexture] = []
        for i in 0..<2 {
            guard let tex = context.makeSharedTexture(
                width: width,
                height: height,
                usage: [.renderTarget, .shaderRead]
            ) else {
                logger.error("Failed to allocate feedback texture \(i)")
                return
            }
            textures.append(tex)
        }

        feedbackLock.withLock {
            feedbackTextures = textures
            feedbackIndex = 0
        }

        // Reallocate post-process textures if a chain is attached.
        postProcessLock.withLock {
            postProcessChain?.allocateTextures(width: width, height: height)
        }

        // Reallocate ray march G-buffer and lit textures if a pipeline is attached.
        rayMarchLock.withLock {
            rayMarchPipeline?.allocateTextures(width: width, height: height)
        }

        logger.info("Feedback textures allocated: \(width)×\(height)")
    }

    public func draw(in view: MTKView) {
        // Wait for an available frame slot (triple buffering).
        context.inflightSemaphore.wait()

        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            context.inflightSemaphore.signal()
            return
        }

        commandBuffer.addCompletedHandler { [semaphore = context.inflightSemaphore] _ in
            semaphore.signal()
        }

        // Timing.
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = Float(now - startTime)
        let deltaTime = Float(now - lastFrameTime)
        lastFrameTime = now

        // Build FeatureVector: start from live MIR features, overlay timing.
        var features = featuresLock.withLock { latestFeatures }
        features.time = elapsed
        features.deltaTime = deltaTime
        let size = view.drawableSize
        features.aspectRatio = size.height > 0 ? Float(size.width / size.height) : 1.777

        // Accumulate energy-weighted audio time and inject into the feature vector.
        let energy = (features.bass + features.mid + features.treble) / 3.0
        stepAccumulatedTime(energy: energy, deltaTime: deltaTime)
        features.accumulatedAudioTime = audioTimeLock.withLock { _accumulatedAudioTime }

        renderFrame(
            commandBuffer: commandBuffer,
            view: view,
            features: &features
        )

        commandBuffer.commit()
    }
}
