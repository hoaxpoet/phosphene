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
    /// Whether the active preset uses feedback.
    var feedbackEnabled: Bool = false
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
    /// Whether the active preset routes through the mesh shader draw path.
    var meshShaderEnabled: Bool = false
    let meshLock = NSLock()

    // MARK: - Post-Process Chain

    /// Optional HDR post-process chain — bloom + ACES tone mapping.
    /// Set via `setPostProcessChain(_:enabled:)` when switching to a post-process preset.
    var postProcessChain: PostProcessChain?
    /// Whether the active preset routes through the post-process render path.
    var postProcessEnabled: Bool = false
    let postProcessLock = NSLock()

    // MARK: - ICB State (Increment 3.5)

    /// Optional ICB state for GPU-driven indirect command buffer rendering.
    /// Set via `setICBState(_:enabled:)` when switching to an ICB-capable preset.
    var icbState: IndirectCommandBufferState?
    /// Whether the active preset routes through the ICB render path.
    var icbEnabled: Bool = false
    let icbLock = NSLock()

    // MARK: - Noise Textures (Increment 3.13)

    /// Optional noise texture manager — binds 5 pre-computed textures at slots 4–8.
    /// Set via `setTextureManager(_:)` once at app startup.
    var textureManager: TextureManager?
    let textureManagerLock = NSLock()

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
        logger.info("RenderPipeline initialized with feedback support")
    }

    // MARK: - Preset Switching

    /// Replace the active render pipeline state (e.g., when switching presets).
    /// Thread-safe — can be called from any queue.
    public func setActivePipelineState(_ newState: MTLRenderPipelineState) {
        pipelineLock.withLock {
            pipelineState = newState
        }
        // Disable feedback when using legacy API (no descriptor info).
        feedbackLock.withLock {
            feedbackEnabled = false
            currentFeedbackParams = nil
            feedbackComposePipelineState = nil
        }
        logger.info("Active pipeline state updated (feedback disabled)")
    }

    /// Set feedback parameters for the active preset. Pass nil to disable feedback.
    /// Thread-safe — can be called from any queue.
    public func setFeedbackParams(_ params: FeedbackParams?) {
        feedbackLock.withLock {
            currentFeedbackParams = params
            feedbackEnabled = params != nil
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
    /// Pass a non-nil generator and `enabled: true` to route `draw(in:)` through
    /// `drawWithMeshShader`.  Pass `nil` / `false` to fall back to the standard
    /// direct or feedback render path.  Thread-safe — can be called from any queue.
    public func setMeshGenerator(_ generator: MeshGenerator?, enabled: Bool = true) {
        meshLock.withLock {
            meshGenerator      = generator
            meshShaderEnabled  = generator != nil && enabled
        }
        logger.info("Mesh shader \(generator != nil && enabled ? "enabled" : "disabled")")
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
    /// Pass a non-nil chain and `enabled: true` to route `draw(in:)` through
    /// `drawWithPostProcess`.  Pass `nil` / `false` to fall back to the direct
    /// or feedback render path.  Thread-safe — can be called from any queue.
    public func setPostProcessChain(_ chain: PostProcessChain?, enabled: Bool = true) {
        postProcessLock.withLock {
            postProcessChain    = chain
            postProcessEnabled  = chain != nil && enabled
        }
        logger.info("Post-process chain \(chain != nil && enabled ? "enabled" : "disabled")")
    }

    /// Attach noise textures that will be bound on every preset render encoder.
    ///
    /// Call once after app startup.  Pass `nil` to detach (noise textures will
    /// be unbound; shaders that sample them will read zeros).
    /// Thread-safe — can be called from any queue.
    public func setTextureManager(_ manager: TextureManager?) {
        textureManagerLock.withLock {
            textureManager = manager
        }
        logger.info("TextureManager \(manager != nil ? "attached" : "detached")")
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

        renderFrame(
            commandBuffer: commandBuffer,
            view: view,
            features: &features
        )

        commandBuffer.commit()
    }
}
