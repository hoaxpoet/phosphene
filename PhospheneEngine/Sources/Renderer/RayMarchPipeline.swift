// RayMarchPipeline — Deferred ray march pipeline for Increment 3.14.
//
// Owns G-buffer textures, the lit scene texture, and the fixed lighting and
// composite pipeline states.  The G-buffer pass pipeline state is provided
// per-frame by the caller (it is preset-specific — compiled from the preset
// source that defines `sceneSDF` and `sceneMaterial`).
//
// Render path (all on one command buffer):
//   1. runGBufferPass   — preset → 3 G-buffer targets (.rg16Float, .rgba8Snorm, .rgba8Unorm)
//   2. runLightingPass  — G-buffer → litTexture (.rgba16Float), PBR + screen-space shadows
//   3. runSSGIPass      — (optional, Increment 3.17) G-buffers + litTexture → ssgiTexture (half-res)
//   4. runSSGIBlendPass — (optional) additively upsample ssgiTexture into litTexture
//   5. runCompositePass — litTexture → outputTexture (ACES SDR) OR
//      (optional) caller feeds litTexture into PostProcessChain.runBloomAndComposite()
//
// SSGI is enabled by setting `ssgiEnabled = true` before calling `render(...)`.
// `RenderPipeline+RayMarch` sets this flag when `.ssgi` is present in `activePasses`.
//
// When both `useRayMarch: true` and a PostProcessChain are desired, the caller:
//   1. Runs RayMarchPipeline.render(..., postProcessChain: chain)
//   2. The pipeline runs G-buffer + lighting (+ optional SSGI) into litTexture, then calls
//      chain.runBloomAndComposite(from: litTexture, to: outputTexture, ...)
//   3. The composite pass is skipped in favour of the chain's bloom composite.

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "RayMarchPipeline")

// MARK: - RayMarchPipeline

/// Deferred PBR ray march pipeline: G-buffer pass → lighting pass → composite/post-process.
///
/// Textures are lazily allocated at drawable size via `ensureAllocated(width:height:)`.
/// The lighting and composite pipeline states are compiled once at init from the
/// Renderer `ShaderLibrary`.
public final class RayMarchPipeline: @unchecked Sendable {

    // MARK: - G-buffer Textures

    /// G-buffer 0: `.rg16Float` — R = depth_normalized [0..1), G = unused.
    public private(set) var gbuffer0: MTLTexture?

    /// G-buffer 1: `.rgba8Snorm` — RGB = world-space normal, A = ambient occlusion.
    public private(set) var gbuffer1: MTLTexture?

    /// G-buffer 2: `.rgba8Unorm` — RGB = albedo, A = packed roughness (upper 4b) + metallic (lower 4b).
    public private(set) var gbuffer2: MTLTexture?

    /// Lit scene texture: `.rgba16Float` — PBR lighting output before tone-mapping.
    /// After the optional SSGI blend pass this also contains indirect diffuse contributions.
    public private(set) var litTexture: MTLTexture?

    /// SSGI accumulation texture: `.rgba16Float`, half drawable resolution.
    /// Written by `runSSGIPass`; blended additively into `litTexture` by `runSSGIBlendPass`.
    /// Nil until `allocateTextures` is called.
    public private(set) var ssgiTexture: MTLTexture?

    // MARK: - Pipeline States

    /// Lighting pass: reads 3 G-buffer targets, evaluates PBR, writes to `.rgba16Float`.
    let lightingPipeline: MTLRenderPipelineState

    /// SSGI accumulation pass (Increment 3.17): reads G-buffers + lit texture → half-res indirect diffuse.
    let ssgiPipeline: MTLRenderPipelineState

    /// SSGI blend pass (Increment 3.17): additive upsample of ssgiTexture into litTexture.
    let ssgiBlendPipeline: MTLRenderPipelineState

    /// Composite pass: reads litTexture, applies ACES, writes to drawable format.
    let compositePipeline: MTLRenderPipelineState

    // MARK: - SSGI State

    /// When `true`, `render(...)` runs the SSGI accumulation and blend passes between
    /// the lighting pass and the composite/bloom pass.
    /// Set by `RenderPipeline+RayMarch` when `.ssgi` is present in `activePasses`.
    /// Defaults to `false`.
    public var ssgiEnabled: Bool = false

    // MARK: - Depth Debug Mode

    /// When `true`, `render(...)` bypasses all lighting, SSGI, and post-processing and
    /// renders a split-screen depth/albedo diagnostic:
    ///   Left half:  depth map — white = near, dark = far, RED = sky/miss.
    ///   Right half: raw unlit albedo from gbuf2.
    /// Temporarily enabled in applyPreset for diagnostic review — disable after.
    public var depthDebugEnabled: Bool = false

    /// Direct depth+albedo diagnostic pipeline — compiled from `raymarch_depth_debug_fragment`.
    let depthDebugPipeline: MTLRenderPipelineState

    // MARK: - G-buffer Debug Mode

    /// When `true`, `render(...)` skips the lighting pass, SSGI, and ACES tone-mapping
    /// and copies `gbuffer2` directly to the output texture.
    ///
    /// This makes the `#ifdef GBUFFER_DEBUG` 4-quadrant visualization readable on screen:
    ///   TL = green (hit) / red (miss)
    ///   TR = SDF sign at ray start (green = outside, red = inside)
    ///   BL = step count greyscale (black = few, white = 128 steps)
    ///   BR = hit depth greyscale / red on miss
    ///
    /// Toggle with the 'G' key in ContentView via `VisualizerEngine.debugGBufferMode`.
    public var debugGBufferMode: Bool = false

    /// Direct-copy pipeline for the G-buffer debug pass.
    /// Reads `gbuffer2` at texture(0) and writes it unmodified to the drawable.
    /// Compiled from `raymarch_gbuffer_debug_fragment` in the Renderer library.
    let gbufferDebugPipeline: MTLRenderPipelineState

    // MARK: - Sampler

    /// Bilinear, clamp-to-edge sampler shared across all passes.
    let sampler: MTLSamplerState

    // MARK: - Metal

    let context: MetalContext

    // MARK: - Scene Uniforms

    /// Per-scene camera, light, and animation parameters.
    /// Updated each frame before `render(...)` by the caller or render loop.
    public var sceneUniforms: SceneUniforms

    // MARK: - Audio-Reactive Modulation (Option A design)

    /// Snapshot of the preset's JSON-specified scene uniforms, captured once
    /// at preset apply time. The shared render path reads these each frame
    /// as the baseline to which per-frame audio modulation is applied — so
    /// modulation accumulates from the preset's intent, not from whatever
    /// the previous frame wrote.
    ///
    /// Fields preserved: camera position (z becomes dolly base), light
    /// intensity, light color, fog far plane.
    public var baseScene: BaseSceneSnapshot = BaseSceneSnapshot()

    /// Forward dolly speed in world-units per second of wall-clock time.
    /// `0` disables dolly (Kinetic Sculpture / Test Sphere stay static).
    /// Set by `applyPreset` from a preset-specific rule.
    ///
    /// Per-frame actual speed = `cameraDollySpeed × (0.5 + bassContribution)`
    /// where bassContribution comes from the audio FeatureVector.  Keeps
    /// camera always moving (autonomous baseline per design) while letting
    /// bass energy modulate the perceived pace 0.5× to ~1.6×.
    public var cameraDollySpeed: Float = 0

    /// Integrated forward camera offset (world units).  Advanced each frame
    /// by `deltaTime × instantaneousSpeed` in `drawWithRayMarch`.  Replaces
    /// the earlier `features.time × cameraDollySpeed` formula so the speed
    /// can vary per frame without historical camera position being rewritten
    /// retroactively (multiplying a constant into accumulated time would do
    /// exactly that).
    public var cameraDollyOffset: Float = 0

    /// Timestamp of the previous drawWithRayMarch invocation — used to
    /// compute `deltaTime` for the dolly integrator.  `nil` before the
    /// first draw.  Reset on preset change.
    public var lastDollyFrameTime: CFTimeInterval?

    /// Captured baseline scene values from the preset JSON.
    public struct BaseSceneSnapshot: Sendable {
        public var cameraPosition: SIMD3<Float> = .zero
        public var lightIntensity: Float = 1.0
        public var lightColor: SIMD3<Float> = SIMD3(1, 1, 1)
        public var fogFar: Float = 30.0
        public init() {}
    }

    // MARK: - Init

    /// Create the ray march pipeline from a compiled shader library.
    ///
    /// Lighting and composite pipeline states are compiled immediately.
    /// Textures are allocated lazily via `ensureAllocated(width:height:)`.
    ///
    /// - Parameters:
    ///   - context: Shared Metal context (device, pixel format).
    ///   - shaderLibrary: Compiled Renderer library containing `raymarch_*` functions.
    /// - Throws: `RayMarchPipelineError` if a shader function is missing, or
    ///   `MTLRenderPipelineState` creation fails.
    public init(context: MetalContext, shaderLibrary: ShaderLibrary) throws {
        self.context = context
        self.sceneUniforms = SceneUniforms()

        let device = context.device

        guard let vertexFn = shaderLibrary.function(named: "fullscreen_vertex") else {
            throw RayMarchPipelineError.functionNotFound("fullscreen_vertex")
        }
        guard let lightingFn = shaderLibrary.function(named: "raymarch_lighting_fragment") else {
            throw RayMarchPipelineError.functionNotFound("raymarch_lighting_fragment")
        }
        guard let ssgiFn = shaderLibrary.function(named: "ssgi_fragment") else {
            throw RayMarchPipelineError.functionNotFound("ssgi_fragment")
        }
        guard let ssgiBlendFn = shaderLibrary.function(named: "ssgi_blend_fragment") else {
            throw RayMarchPipelineError.functionNotFound("ssgi_blend_fragment")
        }
        guard let compositeFn = shaderLibrary.function(named: "raymarch_composite_fragment") else {
            throw RayMarchPipelineError.functionNotFound("raymarch_composite_fragment")
        }
        guard let debugFn = shaderLibrary.function(named: "raymarch_gbuffer_debug_fragment") else {
            throw RayMarchPipelineError.functionNotFound("raymarch_gbuffer_debug_fragment")
        }

        // Lighting pass — outputs linear HDR to .rgba16Float.
        let lightDesc = MTLRenderPipelineDescriptor()
        lightDesc.vertexFunction = vertexFn
        lightDesc.fragmentFunction = lightingFn
        lightDesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.lightingPipeline = try device.makeRenderPipelineState(descriptor: lightDesc)

        // SSGI accumulation pass — half-res, writes indirect diffuse to .rgba16Float.
        let ssgiDesc = MTLRenderPipelineDescriptor()
        ssgiDesc.vertexFunction = vertexFn
        ssgiDesc.fragmentFunction = ssgiFn
        ssgiDesc.colorAttachments[0].pixelFormat = .rgba16Float
        self.ssgiPipeline = try device.makeRenderPipelineState(descriptor: ssgiDesc)

        // SSGI blend pass — additive upsample of ssgiTexture into litTexture (.rgba16Float).
        let ssgiBlendDesc = MTLRenderPipelineDescriptor()
        ssgiBlendDesc.vertexFunction = vertexFn
        ssgiBlendDesc.fragmentFunction = ssgiBlendFn
        ssgiBlendDesc.colorAttachments[0].pixelFormat = .rgba16Float
        ssgiBlendDesc.colorAttachments[0].isBlendingEnabled = true
        ssgiBlendDesc.colorAttachments[0].rgbBlendOperation = .add
        ssgiBlendDesc.colorAttachments[0].alphaBlendOperation = .add
        ssgiBlendDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        ssgiBlendDesc.colorAttachments[0].destinationRGBBlendFactor = .one
        ssgiBlendDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        ssgiBlendDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
        self.ssgiBlendPipeline = try device.makeRenderPipelineState(descriptor: ssgiBlendDesc)

        // Composite pass — ACES tone-map to drawable format.
        let compositeDesc = MTLRenderPipelineDescriptor()
        compositeDesc.vertexFunction = vertexFn
        compositeDesc.fragmentFunction = compositeFn
        compositeDesc.colorAttachments[0].pixelFormat = context.pixelFormat
        self.compositePipeline = try device.makeRenderPipelineState(descriptor: compositeDesc)

        // G-buffer debug pass — copies gbuf2 (.rgba8Unorm) directly to the drawable.
        // Bypasses lighting/SSGI/ACES so diagnostic colors are read unmodified.
        let debugDesc = MTLRenderPipelineDescriptor()
        debugDesc.vertexFunction = vertexFn
        debugDesc.fragmentFunction = debugFn
        debugDesc.colorAttachments[0].pixelFormat = context.pixelFormat
        self.gbufferDebugPipeline = try device.makeRenderPipelineState(descriptor: debugDesc)

        // Depth debug pass — split screen: left=depth, right=albedo. No lighting/ACES.
        guard let depthDebugFn = shaderLibrary.function(named: "raymarch_depth_debug_fragment") else {
            throw RayMarchPipelineError.functionNotFound("raymarch_depth_debug_fragment")
        }
        let depthDebugDesc = MTLRenderPipelineDescriptor()
        depthDebugDesc.vertexFunction = vertexFn
        depthDebugDesc.fragmentFunction = depthDebugFn
        depthDebugDesc.colorAttachments[0].pixelFormat = context.pixelFormat
        self.depthDebugPipeline = try device.makeRenderPipelineState(descriptor: depthDebugDesc)

        // Bilinear, clamp-to-edge sampler.
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        guard let samp = device.makeSamplerState(descriptor: samplerDesc) else {
            throw RayMarchPipelineError.samplerCreationFailed
        }
        self.sampler = samp

        logger.info("RayMarchPipeline initialized")
    }

    // MARK: - Texture Allocation

    /// Allocate (or reallocate) G-buffer and lit scene textures for the given size.
    ///
    /// - Parameters:
    ///   - width:  Full-resolution width in pixels (drawable width).
    ///   - height: Full-resolution height in pixels (drawable height).
    public func allocateTextures(width: Int, height: Int) {
        let texWidth  = max(width, 1)
        let texHeight = max(height, 1)

        let ssgiW = max(texWidth / 2, 1)
        let ssgiH = max(texHeight / 2, 1)

        gbuffer0    = context.makeSharedTexture(width: texWidth, height: texHeight, pixelFormat: .rg16Float)
        gbuffer1    = makeSnormTexture(width: texWidth, height: texHeight)
        gbuffer2    = context.makeSharedTexture(width: texWidth, height: texHeight, pixelFormat: .rgba8Unorm)
        litTexture  = context.makeSharedTexture(width: texWidth, height: texHeight, pixelFormat: .rgba16Float)
        ssgiTexture = context.makeSharedTexture(width: ssgiW, height: ssgiH, pixelFormat: .rgba16Float)

        logger.info("RayMarchPipeline textures allocated: \(texWidth)×\(texHeight), SSGI: \(ssgiW)×\(ssgiH)")
    }

    /// Lazy allocator — no-op if textures are already allocated.
    public func ensureAllocated(width: Int, height: Int) {
        guard gbuffer0 == nil else { return }
        allocateTextures(width: width, height: height)
    }

    // MARK: - Render Entry Point

    // swiftlint:disable function_parameter_count
    // `render` takes 9 parameters — the minimal render context for a multi-pass pipeline.

    /// Run the full deferred ray march pipeline on the given command buffer.
    ///
    /// Pass 1 (`gbufferPipelineState`) renders the preset's SDF scene into 3 G-buffer targets.
    /// Pass 2 (`lightingPipeline`) evaluates PBR + screen-space shadows into `litTexture`.
    /// Pass 3 depends on `postProcessChain`:
    ///   - Nil: `compositePipeline` tone-maps `litTexture` → `outputTexture` directly (SDR).
    ///   - Non-nil: calls `chain.runBloomAndComposite(from: litTexture, to: outputTexture, ...)`.
    ///
    /// - Parameters:
    ///   - gbufferPipelineState: Preset-compiled G-buffer pipeline (uses `raymarch_gbuffer_fragment`).
    ///   - features: Audio feature vector (bound at fragment buffer 0).
    ///   - fftBuffer: FFT magnitudes (buffer 1).
    ///   - waveformBuffer: PCM waveform (buffer 2).
    ///   - stemFeatures: Per-stem features (buffer 3).
    ///   - outputTexture: Final render target (drawable texture or chain input).
    ///   - commandBuffer: All render passes are encoded into this buffer.
    ///   - noiseTextures: Optional noise texture manager — binds at slots 4–8.
    ///   - iblManager: Optional IBL texture manager — binds at slots 9–11.
    ///   - postProcessChain: Optional bloom chain. When non-nil, replaces the composite pass.
    public func render(
        gbufferPipelineState: MTLRenderPipelineState,
        features: inout FeatureVector,
        fftBuffer: MTLBuffer,
        waveformBuffer: MTLBuffer,
        stemFeatures: StemFeatures,
        outputTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        noiseTextures: TextureManager? = nil,
        iblManager: IBLManager? = nil,
        postProcessChain: PostProcessChain? = nil
    ) {
        guard gbuffer0 != nil, gbuffer1 != nil, gbuffer2 != nil, litTexture != nil else {
            logger.error("RayMarchPipeline.render called before textures allocated — skipping")
            return
        }

        runGBufferPass(
            commandBuffer: commandBuffer,
            gbufferPipelineState: gbufferPipelineState,
            features: &features,
            fftBuffer: fftBuffer,
            waveformBuffer: waveformBuffer,
            stemFeatures: stemFeatures,
            noiseTextures: noiseTextures
        )

        // G-buffer debug bypass: skip lighting/SSGI/ACES entirely.
        // gbuf2 is written directly to the drawable so the 4-quadrant
        // diagnostic colors are unmodified when they reach the screen.
        if debugGBufferMode {
            runGBufferDebugPass(commandBuffer: commandBuffer, outputTexture: outputTexture)
            return
        }

        runLightingPass(
            commandBuffer: commandBuffer,
            features: &features,
            noiseTextures: noiseTextures,
            iblManager: iblManager
        )

        // Optional SSGI pass (Increment 3.17): indirect diffuse between lighting and composite.
        if ssgiEnabled {
            runSSGIPass(commandBuffer: commandBuffer, features: &features, noiseTextures: noiseTextures)
            runSSGIBlendPass(commandBuffer: commandBuffer)
        }

        if let chain = postProcessChain {
            // Route litTexture through the PostProcessChain bloom + ACES path.
            guard let lit = litTexture else { return }
            chain.ensureAllocated(width: lit.width, height: lit.height)
            chain.runBloomAndComposite(from: lit, to: outputTexture, commandBuffer: commandBuffer)
        } else {
            runCompositePass(commandBuffer: commandBuffer, outputTexture: outputTexture)
        }
    }

    // swiftlint:enable function_parameter_count

    // MARK: - Private Helpers

    /// Create an `.rgba8Snorm` texture for G-buffer 1 (normals + AO).
    /// `MetalContext.makeSharedTexture` doesn't expose snorm formats directly,
    /// so we build the descriptor manually.
    private func makeSnormTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Snorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.storageMode = .shared
        desc.usage = [.renderTarget, .shaderRead]
        return context.device.makeTexture(descriptor: desc)
    }
}

// MARK: - Errors

/// Errors thrown by `RayMarchPipeline.init`.
public enum RayMarchPipelineError: Error, Sendable {
    /// A required Metal shader function was not found in the library.
    case functionNotFound(String)
    /// `MTLDevice.makeSamplerState` returned nil.
    case samplerCreationFailed
}
