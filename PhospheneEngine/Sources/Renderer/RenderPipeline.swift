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

    private let context: MetalContext
    private var pipelineState: MTLRenderPipelineState
    private let pipelineLock = NSLock()

    // MARK: - Audio Buffers (UMA zero-copy — written by audio thread, read by GPU)

    private let fftMagnitudeBuffer: MTLBuffer   // 512 floats from FFTProcessor
    private let waveformBuffer: MTLBuffer       // 2048 interleaved floats from AudioBuffer

    // MARK: - Particle System

    /// Optional particle geometry — compute update + point-sprite rendering.
    private var particleGeometry: ProceduralGeometry?
    private let particleLock = NSLock()

    // MARK: - Live Audio Features

    /// Latest audio features from MIR analysis (band energy, beats, spectral).
    /// Set from the analysis queue, read in the render loop.
    private var latestFeatures = FeatureVector.zero
    private let featuresLock = NSLock()

    // MARK: - Feedback Textures (Milkdrop-style ping-pong)

    /// Double-buffered feedback textures. Index flips each frame.
    private var feedbackTextures: [MTLTexture] = []
    /// Which texture is the current write target (0 or 1).
    private var feedbackIndex: Int = 0
    /// Whether the active preset uses feedback.
    private var feedbackEnabled: Bool = false
    /// Current feedback parameters (from preset descriptor).
    private var currentFeedbackParams: FeedbackParams?
    /// Additive-blended pipeline for the feedback composite pass.
    private var feedbackComposePipelineState: MTLRenderPipelineState?
    private let feedbackLock = NSLock()

    /// Built-in pipeline states for feedback warp and blit passes.
    private let feedbackWarpPipelineState: MTLRenderPipelineState
    private let feedbackBlitPipelineState: MTLRenderPipelineState
    /// Bilinear, clamp-to-edge sampler for feedback texture reads.
    private let feedbackSamplerState: MTLSamplerState

    // MARK: - Timing

    private let startTime: CFAbsoluteTime
    private var lastFrameTime: CFAbsoluteTime

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

    /// Attach a particle system to the render loop.
    /// Thread-safe — can be called from any queue.
    public func setParticleGeometry(_ geometry: ProceduralGeometry?) {
        particleLock.withLock {
            particleGeometry = geometry
        }
    }

    /// Update the live audio features from MIR analysis.
    /// Thread-safe — called from the analysis queue each frame.
    public func setFeatures(_ features: FeatureVector) {
        featuresLock.withLock {
            latestFeatures = features
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

        // Snapshot state for this frame.
        let particles = particleLock.withLock { particleGeometry }
        let activePipeline = pipelineLock.withLock { pipelineState }

        // Lazy-allocate feedback textures if needed (drawableSizeWillChange may not fire).
        let drawableSize = view.drawableSize
        feedbackLock.withLock {
            if feedbackEnabled && feedbackTextures.isEmpty && drawableSize.width > 0 {
                let texWidth = max(Int(drawableSize.width), 1)
                let texHeight = max(Int(drawableSize.height), 1)
                var textures: [MTLTexture] = []
                for _ in 0..<2 {
                    if let tex = context.makeSharedTexture(
                        width: texWidth,
                        height: texHeight,
                        usage: [.renderTarget, .shaderRead]
                    ) {
                        textures.append(tex)
                    }
                }
                if textures.count == 2 {
                    feedbackTextures = textures
                    feedbackIndex = 0
                    logger.info("Feedback textures lazy-allocated: \(texWidth)×\(texHeight)")
                }
            }
        }

        let (fbEnabled, fbParams, fbCompose, fbTextures, fbIndex) = feedbackLock.withLock {
            (feedbackEnabled, currentFeedbackParams, feedbackComposePipelineState,
             feedbackTextures, feedbackIndex)
        }

        // ── Compute pass: update particles before rendering ─────────
        particles?.update(features: features, commandBuffer: commandBuffer)

        // Branch: feedback-enabled preset vs direct rendering.
        if fbEnabled, let params = fbParams, let composePipeline = fbCompose,
           fbTextures.count == 2 {
            drawWithFeedback(
                commandBuffer: commandBuffer,
                view: view,
                features: &features,
                params: params,
                activePipeline: activePipeline,
                composePipeline: composePipeline,
                particles: particles,
                textures: fbTextures,
                texIndex: fbIndex
            )
            feedbackLock.withLock { feedbackIndex = 1 - feedbackIndex }
        } else {
            drawDirect(
                commandBuffer: commandBuffer,
                view: view,
                features: &features,
                activePipeline: activePipeline,
                particles: particles
            )
        }

        commandBuffer.commit()
    }

    // MARK: - Direct Rendering (Non-Feedback)

    /// Original single-pass render directly to drawable.
    private func drawDirect(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        activePipeline: MTLRenderPipelineState,
        particles: ProceduralGeometry?
    ) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }

        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        // Draw preset visualization.
        encoder.setRenderPipelineState(activePipeline)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        encoder.setFragmentBuffer(fftMagnitudeBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        // Draw particles on top.
        particles?.render(encoder: encoder, features: features)

        encoder.endEncoding()

        commandBuffer.present(drawable)
    }

    // MARK: - Feedback Rendering (Milkdrop-Style)

    /// Feedback render path. Two modes depending on whether particles are attached:
    ///
    /// - **Particle mode** (Murmuration): warp (unused) → preset + particles drawn
    ///   directly to the drawable. The feedback texture is maintained but not shown,
    ///   to prevent additive washout over a vivid sky backdrop.
    ///
    /// - **Surface mode** (Membrane): warp → composite (additive) → blit to drawable.
    ///   The preset's contribution accumulates into the feedback texture each frame
    ///   and the warped/decayed previous state provides visual memory. This is the
    ///   true Milkdrop-style feedback loop.
    private func drawWithFeedback(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        params: FeedbackParams,
        activePipeline: MTLRenderPipelineState,
        composePipeline: MTLRenderPipelineState,
        particles: ProceduralGeometry?,
        textures: [MTLTexture],
        texIndex: Int
    ) {
        let currentTex = textures[texIndex]
        let previousTex = textures[1 - texIndex]
        var fbParams = params
        fbParams.beatValue = params.beatValue

        runWarpPass(
            commandBuffer: commandBuffer,
            features: &features,
            params: &fbParams,
            target: currentTex,
            source: previousTex
        )

        if particles != nil {
            drawParticleMode(
                commandBuffer: commandBuffer,
                view: view,
                features: &features,
                activePipeline: activePipeline,
                particles: particles
            )
        } else {
            drawSurfaceMode(
                commandBuffer: commandBuffer,
                view: view,
                features: &features,
                composePipeline: composePipeline,
                feedbackTexture: currentTex
            )
        }
    }

    /// Pass 1 of the feedback loop: read the previous texture, apply decay and
    /// any subtle warp, write the result into the current texture.
    private func runWarpPass(
        commandBuffer: MTLCommandBuffer,
        features: inout FeatureVector,
        params: inout FeedbackParams,
        target: MTLTexture,
        source: MTLTexture
    ) {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else {
            return
        }
        encoder.setRenderPipelineState(feedbackWarpPipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<FeedbackParams>.stride, index: 1)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(feedbackSamplerState, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Particle mode drawable pass: render the preset + particles directly to the
    /// drawable without blending through the feedback texture.
    private func drawParticleMode(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        activePipeline: MTLRenderPipelineState,
        particles: ProceduralGeometry?
    ) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encoder.setRenderPipelineState(activePipeline)
            encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
            encoder.setFragmentBuffer(fftMagnitudeBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            particles?.render(encoder: encoder, features: features)
            encoder.endEncoding()
        }
        commandBuffer.present(drawable)
    }

    /// Surface mode: composite the preset additively into the (already warped)
    /// feedback texture, then blit the result to the drawable.
    private func drawSurfaceMode(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        composePipeline: MTLRenderPipelineState,
        feedbackTexture: MTLTexture
    ) {
        // Pass 2: additive composite into the warped feedback texture.
        let composeDesc = MTLRenderPassDescriptor()
        composeDesc.colorAttachments[0].texture = feedbackTexture
        composeDesc.colorAttachments[0].loadAction = .load
        composeDesc.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: composeDesc) {
            encoder.setRenderPipelineState(composePipeline)
            encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
            encoder.setFragmentBuffer(fftMagnitudeBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        // Drawable pass: blit feedback texture to screen.
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encoder.setRenderPipelineState(feedbackBlitPipelineState)
            encoder.setFragmentTexture(feedbackTexture, index: 0)
            encoder.setFragmentSamplerState(feedbackSamplerState, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        commandBuffer.present(drawable)
    }
}
