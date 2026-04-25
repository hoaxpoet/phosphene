// PostProcessChain — HDR post-process pipeline for Increment 3.4.
//
// Owns three intermediate textures and four compiled pipeline states that
// implement a bloom + ACES tone-mapping chain:
//
//   sceneTexture  (.rgba16Float, full-res) — preset renders here first
//   bloomTexA     (.rgba16Float, half-res) — bright pass output, blur ping
//   bloomTexB     (.rgba16Float, half-res) — blur pong
//
// Render path (all on a single command buffer):
//   1. runScenePass   — scene preset → sceneTexture
//   2. runBrightPass  — sceneTexture → bloomTexA (luminance > 0.9 threshold)
//   3. runBlurH       — bloomTexA → bloomTexB (9-tap Gaussian, horizontal)
//   4. runBlurV       — bloomTexB → bloomTexA (9-tap Gaussian, vertical)
//   5. runComposite   — (sceneTexture + bloomTexA) → outputTexture (ACES SDR)

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "PostProcessChain")

// MARK: - PostProcessChain

/// HDR post-process chain: bloom extraction, separable Gaussian blur, and ACES tone mapping.
///
/// Textures are lazily allocated at drawable size via `allocateTextures(width:height:)`.
/// Pipeline states are compiled once at init from the provided `ShaderLibrary`.
public final class PostProcessChain: @unchecked Sendable {

    // MARK: - Intermediate Textures

    /// Full-resolution HDR scene texture (.rgba16Float).
    /// The preset fragment shader renders into this texture before post-processing.
    public private(set) var sceneTexture: MTLTexture?

    /// Half-resolution bloom texture A (.rgba16Float).
    /// Receives the bright-pass output; also the final bloom result after blur.
    public private(set) var bloomTexA: MTLTexture?

    /// Half-resolution bloom texture B (.rgba16Float).
    /// Receives the horizontal blur output; input to the vertical blur pass.
    public private(set) var bloomTexB: MTLTexture?

    // MARK: - Pipeline States

    /// Bright pass: full-res scene → half-res bloom (luminance threshold 0.9).
    let brightPassPipeline: MTLRenderPipelineState
    /// Horizontal Gaussian blur: bloomTexA → bloomTexB.
    let blurHPipeline: MTLRenderPipelineState
    /// Vertical Gaussian blur: bloomTexB → bloomTexA.
    let blurVPipeline: MTLRenderPipelineState
    /// ACES composite: (scene + bloom) → SDR output (.bgra8Unorm_srgb drawable).
    let compositePipeline: MTLRenderPipelineState

    // MARK: - Frame Budget Governor Gate (D-057)

    /// When `false`, the bright-pass and Gaussian blur passes are skipped and the
    /// ACES composite is run directly on the scene texture without bloom.
    /// Set by `RenderPipeline.applyQualityLevel(_:)` at QualityLevel >= .noBloom.
    /// The post-process pass still runs — bloom is suppressed, not the whole chain.
    public var bloomEnabled: Bool = true

    // MARK: - Sampler

    /// Bilinear, clamp-to-edge sampler shared across all passes.
    let sampler: MTLSamplerState

    // MARK: - Metal

    let context: MetalContext

    // MARK: - Init

    /// Create the post-process chain from a compiled shader library.
    ///
    /// Pipeline states are compiled immediately; textures are allocated lazily
    /// via `allocateTextures(width:height:)` or `ensureAllocated(width:height:)`.
    ///
    /// - Parameters:
    ///   - context: Shared Metal context (device, pixel format).
    ///   - shaderLibrary: Compiled library containing the `pp_*` fragment functions.
    /// - Throws: `ShaderLibraryError` if any shader function is missing, or
    ///   `PostProcessError` if sampler creation fails.
    public init(context: MetalContext, shaderLibrary: ShaderLibrary) throws {
        self.context = context
        let device = context.device

        // Bright pass renders to .rgba16Float (bloom texture format).
        brightPassPipeline = try shaderLibrary.renderPipelineState(
            named: "pp_bright_pass",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "pp_bright_pass_fragment",
            pixelFormat: .rgba16Float,
            device: device
        )

        // Horizontal blur — same half-res target format.
        blurHPipeline = try shaderLibrary.renderPipelineState(
            named: "pp_blur_h",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "pp_blur_h_fragment",
            pixelFormat: .rgba16Float,
            device: device
        )

        // Vertical blur — same half-res target format.
        blurVPipeline = try shaderLibrary.renderPipelineState(
            named: "pp_blur_v",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "pp_blur_v_fragment",
            pixelFormat: .rgba16Float,
            device: device
        )

        // Composite renders to the drawable pixel format (.bgra8Unorm_srgb).
        compositePipeline = try shaderLibrary.renderPipelineState(
            named: "pp_composite",
            vertexFunction: "fullscreen_vertex",
            fragmentFunction: "pp_composite_fragment",
            pixelFormat: context.pixelFormat,
            device: device
        )

        // Bilinear, clamp-to-edge sampler for all post-process texture reads.
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        guard let samp = device.makeSamplerState(descriptor: samplerDesc) else {
            throw PostProcessError.samplerCreationFailed
        }
        self.sampler = samp

        logger.info("PostProcessChain initialized")
    }

    // MARK: - Texture Allocation

    /// Allocate (or reallocate) the HDR scene and bloom textures for the given size.
    ///
    /// Bloom textures are half the scene dimensions (minimum 1×1).
    /// Called from `mtkView(_:drawableSizeWillChange:)` and lazily from
    /// `ensureAllocated(width:height:)` when the first frame is drawn.
    ///
    /// - Parameters:
    ///   - width: Full-resolution width in pixels (drawable width).
    ///   - height: Full-resolution height in pixels (drawable height).
    public func allocateTextures(width: Int, height: Int) {
        let texWidth  = max(width, 1)
        let texHeight = max(height, 1)
        let bloomW    = max(texWidth / 2, 1)
        let bloomH    = max(texHeight / 2, 1)

        sceneTexture = context.makeSharedTexture(
            width: texWidth, height: texHeight, pixelFormat: .rgba16Float
        )
        bloomTexA = context.makeSharedTexture(
            width: bloomW, height: bloomH, pixelFormat: .rgba16Float
        )
        bloomTexB = context.makeSharedTexture(
            width: bloomW, height: bloomH, pixelFormat: .rgba16Float
        )

        logger.info("PostProcessChain textures allocated: scene \(texWidth)×\(texHeight), bloom \(bloomW)×\(bloomH)")
    }

    /// Lazy allocator — no-op if textures are already allocated.
    func ensureAllocated(width: Int, height: Int) {
        guard sceneTexture == nil else { return }
        allocateTextures(width: width, height: height)
    }

    // MARK: - Render Entry Point

    // swiftlint:disable function_parameter_count
    // `render` takes 7 parameters and `runScenePass` takes 6 — the minimal sets
    // needed to encode a full preset draw call plus audio buffer context.

    /// Run the full 5-step HDR post-process chain on the given command buffer.
    ///
    /// Step 1 renders the scene preset into `sceneTexture`.
    /// Steps 2–4 compute and blur the bloom.
    /// Step 5 composites the scene + bloom with ACES tone mapping into `outputTexture`.
    ///
    /// - Parameters:
    ///   - scenePipelineState: Compiled pipeline for the active scene preset.
    ///   - features: Audio feature vector (bound at fragment buffer 0).
    ///   - fftBuffer: FFT magnitudes (512 floats, buffer 1).
    ///   - waveformBuffer: PCM waveform (2048 floats, buffer 2).
    ///   - stemFeatures: Per-stem features (buffer 3).
    ///   - outputTexture: Final SDR render target (drawable texture, `.bgra8Unorm_srgb`).
    ///   - commandBuffer: All render passes are encoded into this buffer.
    ///   - noiseTextures: Optional TextureManager — binds noise textures at slots 4–8
    ///     in the scene pass so preset shaders can sample them.  Defaults to `nil`.
    public func render(
        scenePipelineState: MTLRenderPipelineState,
        features: inout FeatureVector,
        fftBuffer: MTLBuffer,
        waveformBuffer: MTLBuffer,
        stemFeatures: StemFeatures,
        outputTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        noiseTextures: TextureManager? = nil
    ) {
        guard sceneTexture != nil, bloomTexA != nil, bloomTexB != nil else {
            logger.error("PostProcessChain.render called before textures allocated — skipping")
            return
        }

        runScenePass(
            commandBuffer: commandBuffer,
            scenePipelineState: scenePipelineState,
            features: &features,
            fftBuffer: fftBuffer,
            waveformBuffer: waveformBuffer,
            stemFeatures: stemFeatures,
            noiseTextures: noiseTextures
        )
        if bloomEnabled {
            runBrightPass(commandBuffer: commandBuffer)
            runBlurH(commandBuffer: commandBuffer)
            runBlurV(commandBuffer: commandBuffer)
        }
        runComposite(commandBuffer: commandBuffer, outputTexture: outputTexture)
    }

    // MARK: - Ray March Integration

    /// Run bloom + ACES composite on an externally-provided HDR scene texture.
    ///
    /// Used by `RayMarchPipeline` when `useRayMarch: true` and a `PostProcessChain`
    /// is both desired (for bloom).  The ray march pipeline writes its lit scene into
    /// a `.rgba16Float` texture, then calls this method instead of `render(...)` to
    /// skip the internal scene pass and inject the external lit texture directly.
    ///
    /// Passes run: bright pass → blur H → blur V → composite (ACES).
    /// Bloom textures are allocated lazily at `from.width × from.height` if needed.
    ///
    /// - Parameters:
    ///   - externalSceneTexture: HDR `.rgba16Float` lit texture from the ray march pipeline.
    ///   - outputTexture: SDR render target (drawable texture, `.bgra8Unorm_srgb`).
    ///   - commandBuffer: All passes are encoded into this buffer.
    public func runBloomAndComposite(
        from externalSceneTexture: MTLTexture,
        to outputTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        // Treat the external texture as our scene texture for the bloom passes.
        sceneTexture = externalSceneTexture

        ensureAllocated(width: externalSceneTexture.width,
                        height: externalSceneTexture.height)

        guard bloomTexA != nil, bloomTexB != nil else {
            logger.error("runBloomAndComposite: bloom textures unavailable — skipping")
            return
        }

        if bloomEnabled {
            runBrightPass(commandBuffer: commandBuffer)
            runBlurH(commandBuffer: commandBuffer)
            runBlurV(commandBuffer: commandBuffer)
        }
        runComposite(commandBuffer: commandBuffer, outputTexture: outputTexture)
    }

    // MARK: - Internal Pass Methods

    /// Pass 1: Render the scene preset into the full-resolution HDR scene texture.
    func runScenePass(
        commandBuffer: MTLCommandBuffer,
        scenePipelineState: MTLRenderPipelineState,
        features: inout FeatureVector,
        fftBuffer: MTLBuffer,
        waveformBuffer: MTLBuffer,
        stemFeatures: StemFeatures,
        noiseTextures: TextureManager? = nil
    ) {
        guard let scene = sceneTexture else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = scene
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(scenePipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        encoder.setFragmentBuffer(fftBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
        var stems = stemFeatures
        encoder.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.stride, index: 3)
        noiseTextures?.bindTextures(to: encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // swiftlint:enable function_parameter_count

    /// Pass 2: Bright pass — `sceneTexture` → `bloomTexA`.
    /// Only pixels with Rec. 709 luminance > 0.9 survive; others are zeroed.
    func runBrightPass(commandBuffer: MTLCommandBuffer) {
        guard let scene = sceneTexture, let bloomA = bloomTexA else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = bloomA
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(brightPassPipeline)
        encoder.setFragmentTexture(scene, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Pass 3: Horizontal 9-tap Gaussian blur — `bloomTexA` → `bloomTexB`.
    func runBlurH(commandBuffer: MTLCommandBuffer) {
        guard let bloomA = bloomTexA, let bloomB = bloomTexB else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = bloomB
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        var texelSize = SIMD2<Float>(1.0 / Float(bloomA.width), 1.0 / Float(bloomA.height))
        encoder.setRenderPipelineState(blurHPipeline)
        encoder.setFragmentBytes(&texelSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        encoder.setFragmentTexture(bloomA, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Pass 4: Vertical 9-tap Gaussian blur — `bloomTexB` → `bloomTexA`.
    func runBlurV(commandBuffer: MTLCommandBuffer) {
        guard let bloomA = bloomTexA, let bloomB = bloomTexB else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = bloomA
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        var texelSize = SIMD2<Float>(1.0 / Float(bloomB.width), 1.0 / Float(bloomB.height))
        encoder.setRenderPipelineState(blurVPipeline)
        encoder.setFragmentBytes(&texelSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        encoder.setFragmentTexture(bloomB, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Pass 5: ACES composite — `(sceneTexture + bloomTexA * bloomStrength)` → `outputTexture`.
    ///
    /// Adds bloom at 0.5 strength when `bloomEnabled` is `true`; skips bloom contribution
    /// when `false` (frame-budget governor, QualityLevel >= .noBloom). ACES tone mapping
    /// always runs regardless of bloom state. D-057.
    func runComposite(commandBuffer: MTLCommandBuffer, outputTexture: MTLTexture) {
        guard let scene = sceneTexture, let bloomA = bloomTexA else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = outputTexture
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        encoder.setRenderPipelineState(compositePipeline)
        // bloomStrength: 1.0 when bloom is enabled, 0.0 when suppressed by governor.
        var strength: Float = bloomEnabled ? 1.0 : 0.0
        encoder.setFragmentBytes(&strength, length: MemoryLayout<Float>.stride, index: 0)
        encoder.setFragmentTexture(scene, index: 0)
        encoder.setFragmentTexture(bloomA, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

// MARK: - Errors

/// Errors thrown by `PostProcessChain.init`.
public enum PostProcessError: Error, Sendable {
    /// `MTLDevice.makeSamplerState` returned nil.
    case samplerCreationFailed
}
