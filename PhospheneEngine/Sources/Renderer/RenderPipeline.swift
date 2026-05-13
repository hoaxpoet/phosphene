// RenderPipeline — MTKViewDelegate that drives the audio-reactive render loop.
// Supports both direct rendering and Milkdrop-style feedback (double-buffered ping-pong).
// Binds FFT magnitude and PCM waveform UMA buffers to a full-screen fragment shader.
// swiftlint:disable file_length

import Metal
@preconcurrency import MetalKit
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
    /// Typed as `any ParticleGeometry` so per-preset conformers (Murmuration's
    /// `ProceduralGeometry`, future siblings) can attach via `setParticleGeometry`. D-097.
    var particleGeometry: (any ParticleGeometry)?
    let particleLock = NSLock()

    // MARK: - Live Audio Features

    /// Latest audio features from MIR analysis (band energy, beats, spectral).
    /// Set from the analysis queue, read in the render loop.
    var latestFeatures = FeatureVector.zero
    let featuresLock = NSLock()

    // MARK: - Session Recording Hook

    /// Per-frame capture hook for SessionRecorder. Invoked after `renderFrame`,
    /// before commit. Nil = zero overhead.
    public var onFrameRendered: ((_ drawableTexture: MTLTexture,
                                  _ features: FeatureVector,
                                  _ stems: StemFeatures,
                                  _ commandBuffer: MTLCommandBuffer) -> Void)?

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

    /// Optional per-preset world-state buffer for mesh presets (e.g. ArachneState.webBuffer).
    /// When non-nil, bound at object buffer(1) + mesh buffer(1) before the mesh draw.
    var meshPresetBuffer: MTLBuffer?
    let meshPresetBufferLock = NSLock()

    /// Optional per-frame tick closure for mesh preset state (e.g. ArachneState.tick).
    /// Called once per frame in renderFrame before the draw pass.
    var meshPresetTick: (@Sendable (FeatureVector, StemFeatures) -> Void)?
    let meshPresetTickLock = NSLock()

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

    // MARK: - MV-Warp State (MV-2, D-027)

    /// Optional per-vertex feedback warp state — allocated when the active preset
    /// declares `.mvWarp` in its passes array.
    var mvWarpState: MVWarpState?
    /// Decay for the mv_warp compose pass — mirrors preset descriptor `pf.decay`.
    var mvWarpDecay: Float = 0.96
    /// Last drawable size reported by `mtkView(_:drawableSizeWillChange:)`.
    /// Used by `setupMVWarp` so mid-session preset switches allocate at the real size.
    var currentDrawableSize: CGSize = CGSize(width: 1920, height: 1080)

    /// Public accessor for the last known drawable size (guarded by mvWarpLock).
    public var mvWarpDrawableSize: CGSize {
        mvWarpLock.withLock { currentDrawableSize }
    }
    let mvWarpLock = NSLock()

    // MARK: - Noise Textures (Increment 3.13)

    /// Optional noise texture manager — binds 5 pre-computed textures at slots 4–8.
    var textureManager: TextureManager?
    let textureManagerLock = NSLock()

    // MARK: - Spectral History (buffer(5))

    /// Per-frame MIR history ring buffer — bound at fragment buffer(5). Updated each frame.
    public let spectralHistory: SpectralHistoryBuffer

    // MARK: - Mesh Preset Fragment Buffer (buffer(4))

    /// Per-preset fragment buffer for mesh presets (e.g. Arachne spider). Bound at fragment buffer(4).
    var meshPresetFragmentBuffer: MTLBuffer?
    let meshPresetFragmentBufferLock = NSLock()

    // MARK: - Direct Preset Fragment Buffer (buffer(6))

    /// Per-preset fragment buffer at index 6 for direct mv_warp presets (e.g. Gossamer).
    /// Follows the same pattern as `meshPresetBuffer`.
    var directPresetFragmentBuffer: MTLBuffer?
    let directPresetFragmentBufferLock = NSLock()

    // MARK: - Direct Preset Fragment Buffer 2 (buffer(7))

    /// Secondary per-preset fragment buffer at index 7 for direct mv_warp presets (e.g. Arachne).
    /// Second CPU-side state buffer; web pool at buffer(6), spider GPU at buffer(7).
    var directPresetFragmentBuffer2: MTLBuffer?
    let directPresetFragmentBuffer2Lock = NSLock()

    // MARK: - Direct Preset Fragment Buffer 3 (buffer(8))

    /// Tertiary per-preset fragment buffer at index 8. Reserved for future
    /// preset-uniform CPU-driven state. Currently unused; first planned consumer
    /// is Lumen Mosaic (Phase LM) for `LumenPatternState`. Slot is shared — any
    /// future preset that needs a third per-frame state buffer binds here. See
    /// CLAUDE.md GPU Contract for the slot 6 / 7 / 8 reservation list. (D-LM-buffer-slot-8)
    var directPresetFragmentBuffer3: MTLBuffer?
    let directPresetFragmentBuffer3Lock = NSLock()

    // MARK: - Direct Preset Fragment Buffer 4 (buffer(9))

    /// Quaternary per-preset fragment buffer at index 9. Reserved for the
    /// `SHADER_CRAFT.md §5.8` stage-rig recipe (V.9 Session 3 / D-125). Bound at
    /// fragment slot 9 of BOTH the ray-march G-buffer pass AND the ray-march
    /// lighting pass — non-stage-rig presets receive the zero-filled
    /// `RayMarchPipeline.stageRigPlaceholderBuffer` so the slot 9 declaration
    /// is always satisfied. First consumer: Ferrofluid Ocean V.9 (carrier
    /// struct: `StageRigState` in `Shared/StageRigState.swift`). (D-125)
    var directPresetFragmentBuffer4: MTLBuffer?
    let directPresetFragmentBuffer4Lock = NSLock()

    // MARK: - Dynamic Text Overlay (texture 12)

    /// Per-frame CPU text rasterization for text-overlay presets (e.g. SpectralCartograph).
    /// Bound at fragment texture(12). Created/destroyed by `setDynamicTextOverlay(_:)`.
    var dynamicTextOverlay: DynamicTextOverlay?
    let dynamicTextOverlayLock = NSLock()

    /// Per-frame callback invoked in `refresh()` to populate the text overlay.
    /// Set by the app layer when a text-overlay preset is active.
    /// The callback receives the overlay and the current frame's FeatureVector.
    var textOverlayCallback: ((DynamicTextOverlay, FeatureVector) -> Void)?
    let textOverlayCallbackLock = NSLock()

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

    // MARK: - Staged Composition (V.ENGINE.1)

    /// Active staged stages + per-stage offscreen textures. See RenderPipeline+Staged.
    var stagedStages: [StagedStageSpec] = []
    var stagedTextures: [String: MTLTexture] = [:]
    let stagedLock = NSLock()

    // MARK: - Accessibility Flags (U.9, D-054)

    /// Beat-pulse amplitude scale. `1.0` normal; `0.5` reduced-motion. See D-054.
    public var beatAmplitudeScale: Float = 1.0
    /// When true, mv_warp and SSGI passes are suppressed. See D-054.
    public var frameReduceMotion: Bool = false

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

    // MARK: - Frame Budget Governor (D-057)

    /// Optional frame budget governor. When nil, the governor is disabled (tests,
    /// headless contexts). Wire in from VisualizerEngine after construction.
    public var frameBudgetManager: FrameBudgetManager?

    /// Secondary timing observer for soak/diagnostics (D-060c). Same source as `frameBudgetManager`.
    public var onFrameTimingObserved: ((_ cpuMs: Float, _ gpuMs: Float?) -> Void)?

    // MARK: - Timing

    let startTime: CFAbsoluteTime
    var lastFrameTime: CFAbsoluteTime
    var drawStartTime: CFAbsoluteTime = 0

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
        self.spectralHistory = SpectralHistoryBuffer(device: context.device)

        self.pipelineState = try shaderLibrary.renderPipelineState(
            named: "waveform",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "waveform_fragment",
            pixelFormat: context.pixelFormat,
            device: context.device
        )
        self.feedbackWarpPipelineState = try shaderLibrary.renderPipelineState(
            named: "feedback_warp",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "feedback_warp_fragment",
            pixelFormat: context.pixelFormat,
            device: context.device
        )
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

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)

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

        // Track size so mid-session preset switches allocate mv_warp textures correctly.
        mvWarpLock.withLock { currentDrawableSize = size }

        // Reallocate mv_warp textures if the active preset uses the warp pass.
        reallocateMVWarpTextures(size: size)
        // Reallocate per-stage offscreen textures for staged-composition presets.
        reallocateStagedTextures(size: size)

        logger.info("Feedback textures allocated: \(width)×\(height)")
    }

    @MainActor
    public func draw(in view: MTKView) {
        // Wait for an available frame slot (triple buffering).
        context.inflightSemaphore.wait()

        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            context.inflightSemaphore.signal()
            return
        }

        let cpuDrawStart = CACurrentMediaTime()
        commandBuffer.addCompletedHandler { [semaphore = context.inflightSemaphore, weak self, cpuDrawStart] cb in
            semaphore.signal()
            let cpuMs = Float((CACurrentMediaTime() - cpuDrawStart) * 1000)
            let gpuMs: Float? = cb.gpuEndTime > cb.gpuStartTime
                ? Float((cb.gpuEndTime - cb.gpuStartTime) * 1000)
                : nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onFrameTimingObserved?(cpuMs, gpuMs)
                guard let mgr = self.frameBudgetManager else { return }
                let level = mgr.observe(.init(cpuFrameMs: cpuMs, gpuFrameMs: gpuMs))
                self.applyQualityLevel(level)
            }
        }

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = Float(now - startTime)
        let deltaTime = Float(now - lastFrameTime)
        lastFrameTime = now

        var features = featuresLock.withLock { latestFeatures }
        features.time = elapsed
        features.deltaTime = deltaTime
        let size = view.drawableSize
        features.aspectRatio = size.height > 0 ? Float(size.width / size.height) : 1.777

        let energy = (features.bass + features.mid + features.treble) / 3.0
        stepAccumulatedTime(energy: energy, deltaTime: deltaTime)
        features.accumulatedAudioTime = audioTimeLock.withLock { _accumulatedAudioTime }

        // Beat clamp: scale onset-pulse amplitudes (U.9, D-054). Timing primitives NOT clamped.
        let beatScale = beatAmplitudeScale
        features.beatBass *= beatScale
        features.beatMid *= beatScale
        features.beatTreble *= beatScale
        features.beatComposite *= beatScale

        let stemSnap = stemFeaturesLock.withLock { latestStemFeatures }
        spectralHistory.append(features: features, stems: stemSnap)

        renderFrame(commandBuffer: commandBuffer, view: view, features: &features)

        // Session recording hook — after renderFrame so drawable has the final image.
        if let hook = onFrameRendered, let drawable = view.currentDrawable {
            let stems = stemFeaturesLock.withLock { latestStemFeatures }
            hook(drawable.texture, features, stems, commandBuffer)
        }

        commandBuffer.commit()
    }
}
