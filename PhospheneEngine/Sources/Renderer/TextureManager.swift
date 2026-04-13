// TextureManager — Pre-computed noise textures for all preset shaders (Increment 3.13).
//
// Generates five tileable noise textures via Metal compute kernels at init time,
// then makes them available at fixed fragment texture indices 4–8.
//
// Texture layout (matches preamble declarations):
//   texture(4) noiseLQ     — 256²  .r8Unorm   tileable Perlin-like FBM
//   texture(5) noiseHQ     — 1024² .r8Unorm   tileable Perlin-like FBM (high detail)
//   texture(6) noiseVolume — 64³   .r8Unorm   tileable 3D FBM (volumetric clouds, fog)
//   texture(7) noiseFBM    — 1024² .rgba8Unorm R=Perlin, G=shifted, B=Worley, A=curl
//   texture(8) blueNoise   — 256²  .r8Unorm   IGN dither (removes banding)
//
// All textures are `.storageModeShared` (UMA zero-copy) and deterministic —
// identical textures are generated on every launch from the same compute code.
// 2D textures have mipmaps for free hardware filtering.

import Metal
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "TextureManager")

// MARK: - TextureManager

/// Generates and manages pre-computed noise textures for all preset shaders.
///
/// Create one instance at app startup and call `setTextureManager` on the
/// `RenderPipeline`.  The pipeline calls `bindTextures(to:)` on every render
/// encoder that draws a preset shader.
public final class TextureManager: @unchecked Sendable {

    // MARK: - Textures

    /// 256×256 tileable Perlin-like FBM, `.r8Unorm`. Cheap noise lookups.
    public let noiseLQ: MTLTexture

    /// 1024×1024 tileable Perlin-like FBM, `.r8Unorm`. High-detail surfaces.
    public let noiseHQ: MTLTexture

    /// 64×64×64 tileable 3D FBM, `.r8Unorm`. Volumetric clouds and fog.
    public let noiseVolume: MTLTexture

    /// 1024×1024 RGBA noise, `.rgba8Unorm`.
    /// R=Perlin, G=shifted Perlin, B=inverted Worley, A=curl magnitude.
    public let noiseFBM: MTLTexture

    /// 256×256 Interleaved Gradient Noise, `.r8Unorm`. Dithering / banding removal.
    public let blueNoise: MTLTexture

    // MARK: - Init

    /// Generate all five noise textures synchronously via Metal compute kernels.
    ///
    /// Blocks the calling thread until GPU generation completes (~5–50 ms on
    /// Apple Silicon).  Call from a background thread if needed; the resulting
    /// textures are safe to read from any thread once init returns.
    ///
    /// - Parameters:
    ///   - context: Shared Metal context (device + command queue).
    ///   - shaderLibrary: Compiled library containing the `gen_perlin_2d`,
    ///     `gen_perlin_3d`, `gen_fbm_rgba`, and `gen_blue_noise` compute kernels.
    /// - Throws: `TextureManagerError` if any texture or pipeline state cannot
    ///   be created, or if the GPU reports an error during generation.
    public init(context: MetalContext, shaderLibrary: ShaderLibrary) throws {
        let device = context.device
        let lib    = shaderLibrary.library

        // ── 1. Allocate textures ────────────────────────────────────────────
        guard
            let lq = TextureManager.make2D(device: device, size: 256, format: .r8Unorm),
            let hq = TextureManager.make2D(device: device, size: 1024, format: .r8Unorm),
            let vol = TextureManager.make3D(device: device, size: 64, format: .r8Unorm),
            let fbm = TextureManager.make2D(device: device, size: 1024, format: .rgba8Unorm),
            let blue = TextureManager.make2D(device: device, size: 256, format: .r8Unorm)
        else {
            throw TextureManagerError.textureAllocationFailed
        }

        self.noiseLQ     = lq
        self.noiseHQ     = hq
        self.noiseVolume = vol
        self.noiseFBM    = fbm
        self.blueNoise   = blue

        // ── 2. Build compute pipeline states ───────────────────────────────
        guard
            let fn2D   = lib.makeFunction(name: "gen_perlin_2d"),
            let fn3D   = lib.makeFunction(name: "gen_perlin_3d"),
            let fnFBM  = lib.makeFunction(name: "gen_fbm_rgba"),
            let fnBlue = lib.makeFunction(name: "gen_blue_noise")
        else {
            throw TextureManagerError.missingKernel
        }

        let pipe2D   = try device.makeComputePipelineState(function: fn2D)
        let pipe3D   = try device.makeComputePipelineState(function: fn3D)
        let pipeFBM  = try device.makeComputePipelineState(function: fnFBM)
        let pipeBlue = try device.makeComputePipelineState(function: fnBlue)

        // ── 3. Dispatch all generation kernels on one command buffer ────────
        guard let genBuf = context.commandQueue.makeCommandBuffer() else {
            throw TextureManagerError.commandBufferFailed
        }

        TextureManager.dispatch2D(commandBuffer: genBuf, pipeline: pipe2D, texture: lq, size: 256)
        TextureManager.dispatch2D(commandBuffer: genBuf, pipeline: pipe2D, texture: hq, size: 1024)
        TextureManager.dispatch3D(commandBuffer: genBuf, pipeline: pipe3D, texture: vol, size: 64)
        TextureManager.dispatch2D(commandBuffer: genBuf, pipeline: pipeFBM, texture: fbm, size: 1024)
        TextureManager.dispatch2D(commandBuffer: genBuf, pipeline: pipeBlue, texture: blue, size: 256)

        genBuf.commit()
        genBuf.waitUntilCompleted()

        if let err = genBuf.error {
            throw TextureManagerError.gpuGenerationFailed(err)
        }

        // ── 4. Generate mipmaps for 2D textures ─────────────────────────────
        //    noiseVolume is 3D — mipmaps not generated (rarely needed and not
        //    supported by MTLBlitCommandEncoder on 3D .storageModeShared textures).
        guard let mipBuf = context.commandQueue.makeCommandBuffer() else {
            throw TextureManagerError.commandBufferFailed
        }

        if let blit = mipBuf.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: lq)
            blit.generateMipmaps(for: hq)
            blit.generateMipmaps(for: fbm)
            blit.generateMipmaps(for: blue)
            blit.endEncoding()
        }

        mipBuf.commit()
        mipBuf.waitUntilCompleted()

        if let err = mipBuf.error {
            throw TextureManagerError.gpuGenerationFailed(err)
        }

        logger.info("""
            TextureManager: 5 noise textures generated \
            (noiseLQ 256², noiseHQ 1024², noiseVolume 64³, noiseFBM 1024², blueNoise 256²)
            """)
    }

    // MARK: - Binding

    /// Bind all five noise textures to fragment texture slots 4–8.
    ///
    /// Call this on every `MTLRenderCommandEncoder` used to draw a preset
    /// shader.  Shaders that don't sample noise textures pay no cost —
    /// unused texture slots are free in Metal.
    public func bindTextures(to encoder: MTLRenderCommandEncoder) {
        encoder.setFragmentTexture(noiseLQ, index: 4)
        encoder.setFragmentTexture(noiseHQ, index: 5)
        encoder.setFragmentTexture(noiseVolume, index: 6)
        encoder.setFragmentTexture(noiseFBM, index: 7)
        encoder.setFragmentTexture(blueNoise, index: 8)
    }

    // MARK: - Private Helpers

    /// Allocate a mipmapped 2D `.storageModeShared` texture with shaderRead + shaderWrite + renderTarget.
    /// `.renderTarget` is required by `MTLBlitCommandEncoder.generateMipmaps(for:)`.
    private static func make2D(
        device: MTLDevice,
        size: Int,
        format: MTLPixelFormat
    ) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: size,
            height: size,
            mipmapped: true
        )
        desc.storageMode = .shared
        desc.usage       = [.shaderRead, .shaderWrite, .renderTarget]
        return device.makeTexture(descriptor: desc)
    }

    /// Allocate a non-mipmapped 3D `.storageModeShared` texture.
    private static func make3D(
        device: MTLDevice,
        size: Int,
        format: MTLPixelFormat
    ) -> MTLTexture? {
        let desc = MTLTextureDescriptor()
        desc.textureType = .type3D
        desc.pixelFormat = format
        desc.width       = size
        desc.height      = size
        desc.depth       = size
        desc.storageMode = .shared
        desc.usage       = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: desc)
    }

    /// Dispatch a 2D compute kernel over an N×N grid.
    private static func dispatch2D(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLComputePipelineState,
        texture: MTLTexture,
        size: Int
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        var sz = UInt32(size)
        encoder.setBytes(&sz, length: MemoryLayout<UInt32>.stride, index: 0)

        // Choose a threadgroup size that is a power-of-two square and fits
        // within the pipeline's maxTotalThreadsPerThreadgroup.
        let maxTpg  = pipeline.maxTotalThreadsPerThreadgroup
        let tgWidth = Int(sqrt(Double(min(maxTpg, 256))))
        let tgSize = MTLSize(width: tgWidth, height: tgWidth, depth: 1)
        let grid = MTLSize(width: size, height: size, depth: 1)

        encoder.dispatchThreads(grid, threadsPerThreadgroup: tgSize)
        encoder.endEncoding()
    }

    /// Dispatch a 3D compute kernel over an N×N×N grid.
    private static func dispatch3D(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLComputePipelineState,
        texture: MTLTexture,
        size: Int
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        var sz = UInt32(size)
        encoder.setBytes(&sz, length: MemoryLayout<UInt32>.stride, index: 0)

        // 8×8×8 = 512 threads per group — fits within Apple Silicon's 1024 limit.
        let tgSize = MTLSize(width: 8, height: 8, depth: 8)
        let grid   = MTLSize(width: size, height: size, depth: size)

        encoder.dispatchThreads(grid, threadsPerThreadgroup: tgSize)
        encoder.endEncoding()
    }
}

// MARK: - TextureManagerError

/// Errors thrown by `TextureManager.init`.
public enum TextureManagerError: Error, Sendable {
    /// `MTLDevice.makeTexture` returned nil for one or more noise textures.
    case textureAllocationFailed
    /// A required compute kernel was not found in the compiled shader library.
    case missingKernel
    /// `MTLCommandQueue.makeCommandBuffer` returned nil.
    case commandBufferFailed
    /// The GPU reported an error during noise generation or mipmap creation.
    case gpuGenerationFailed(Error)
}
