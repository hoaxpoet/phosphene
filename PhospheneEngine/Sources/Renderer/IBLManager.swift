// IBLManager — IBL texture generation and management (Increment 3.16).
//
// Generates three Image-Based Lighting textures at init time via Metal compute kernels
// defined in IBL.metal, then makes them available at fixed fragment texture indices 9–11.
//
// Texture layout (matches preamble documentation):
//   texture(9)  irradianceMap     — texturecube, 32² per face, .rgba16Float
//                                   Cosine-weighted irradiance for diffuse ambient.
//   texture(10) prefilteredEnvMap — texturecube, 128² per face, 5 mip levels, .rgba16Float
//                                   GGX prefiltered specular, roughness encoded in LOD.
//   texture(11) brdfLUT           — texture2d, 512², .rg16Float
//                                   Split-sum BRDF integration: x=scale, y=bias.
//
// Source environment: procedural gradient sky (matches rm_skyColor in RayMarch.metal).
// All textures are `.storageModeShared` (UMA zero-copy).
// Prefiltered env map mip levels are computed explicitly (NOT via generateMipmaps)
// because each level encodes a distinct roughness, not a downsample of mip 0.

import Metal
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "IBLManager")

// MARK: - IBLManager

/// Generates and manages IBL textures for physically accurate ambient lighting and
/// specular reflections in all ray march presets.
///
/// Create one instance at app startup on a background queue and pass it to
/// `RenderPipeline.setIBLManager(_:)`.  The pipeline calls `bindTextures(to:)` on
/// every render encoder for the ray march lighting pass.
public final class IBLManager: @unchecked Sendable {

    // MARK: - Textures

    /// Irradiance cubemap: cosine-weighted hemisphere integral per face direction.
    /// 32×32 per face, `.rgba16Float`.  Sampled by the lighting pass for diffuse ambient.
    public let irradianceMap: MTLTexture

    /// Prefiltered specular environment cubemap with 5 mip levels.
    /// 128×128 per face at mip 0 (halving to 8×8 at mip 4), `.rgba16Float`.
    /// Each mip level is pre-integrated with roughness = mip / 4.0.
    public let prefilteredEnvMap: MTLTexture

    /// Split-sum BRDF integration LUT: x = Fresnel scale, y = Fresnel bias.
    /// 512×512, `.rg16Float`.  Axes: x = NdotV [0,1], y = roughness [0,1].
    public let brdfLUT: MTLTexture

    // MARK: - Constants

    /// Face size of the irradiance cubemap (32 pixels per edge).
    public static let irradianceFaceSize: Int = 32

    /// Face size of the prefiltered env map at mip 0 (128 pixels per edge).
    public static let prefilteredFaceSize: Int = 128

    /// Number of mip levels in the prefiltered env map (roughness 0, 0.25, 0.5, 0.75, 1.0).
    public static let prefilteredMipCount: Int = 5

    /// Edge size of the BRDF LUT (512×512).
    public static let brdfLUTSize: Int = 512

    // MARK: - Init

    /// Generate all three IBL textures synchronously via Metal compute kernels.
    ///
    /// Blocks the calling thread until GPU generation completes.  Call from a
    /// background queue; the resulting textures are safe to read from any thread.
    ///
    /// - Parameters:
    ///   - context: Shared Metal context (device + command queue).
    ///   - shaderLibrary: Compiled library containing `ibl_gen_irradiance`,
    ///     `ibl_gen_prefiltered_env`, and `ibl_gen_brdf_lut` kernels.
    /// - Throws: `IBLManagerError` if texture allocation, kernel lookup, or GPU
    ///   generation fails.
    public init(context: MetalContext, shaderLibrary: ShaderLibrary) throws {
        let device = context.device
        let lib    = shaderLibrary.library

        // ── 1. Allocate textures ─────────────────────────────────────────────

        guard let irrMap = IBLManager.makeCube(
            device: device,
            size: IBLManager.irradianceFaceSize,
            mipLevels: 1
        ) else {
            throw IBLManagerError.textureAllocationFailed("irradianceMap")
        }
        guard let prefMap = IBLManager.makeCube(
            device: device,
            size: IBLManager.prefilteredFaceSize,
            mipLevels: IBLManager.prefilteredMipCount
        ) else {
            throw IBLManagerError.textureAllocationFailed("prefilteredEnvMap")
        }
        guard let lutTex = IBLManager.makeLUT(
            device: device,
            size: IBLManager.brdfLUTSize
        ) else {
            throw IBLManagerError.textureAllocationFailed("brdfLUT")
        }

        self.irradianceMap    = irrMap
        self.prefilteredEnvMap = prefMap
        self.brdfLUT          = lutTex

        // ── 2. Look up compute kernel functions ─────────────────────────────

        let pipes = try IBLManager.makeComputePipelines(from: lib, device: device)

        // ── 3. Dispatch generation on one command buffer ─────────────────────

        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else {
            throw IBLManagerError.commandBufferFailed
        }

        // Irradiance: (32, 32, 6) — z axis = face index.
        IBLManager.dispatchIrradiance(
            commandBuffer: cmdBuf,
            pipeline: pipes.irradiance,
            texture: irrMap,
            faceSize: IBLManager.irradianceFaceSize
        )

        // Prefiltered env: one dispatch per mip level (roughness increases with LOD).
        IBLManager.dispatchPrefilteredEnv(
            commandBuffer: cmdBuf,
            pipeline: pipes.prefilteredEnv,
            texture: prefMap
        )

        // BRDF LUT: (512, 512, 1).
        IBLManager.dispatchBRDFLUT(
            commandBuffer: cmdBuf,
            pipeline: pipes.brdfLUT,
            texture: lutTex,
            size: IBLManager.brdfLUTSize
        )

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        if let err = cmdBuf.error {
            throw IBLManagerError.gpuGenerationFailed(err)
        }

        logger.info("IBLManager: IBL textures generated (irradiance 32², prefilteredEnv 128² ×5 mips, brdfLUT 512²)")
    }

    // MARK: - Binding

    /// Bind all three IBL textures to fragment texture slots 9–11.
    ///
    /// Call this on every `MTLRenderCommandEncoder` used for the ray march lighting pass.
    /// Shaders that don't sample IBL pay no cost — unused texture slots are free in Metal.
    public func bindTextures(to encoder: MTLRenderCommandEncoder) {
        encoder.setFragmentTexture(irradianceMap, index: 9)
        encoder.setFragmentTexture(prefilteredEnvMap, index: 10)
        encoder.setFragmentTexture(brdfLUT, index: 11)
    }

    // MARK: - Private Pipeline Creation

    private struct IBLPipelines {
        let irradiance: MTLComputePipelineState
        let prefilteredEnv: MTLComputePipelineState
        let brdfLUT: MTLComputePipelineState
    }

    /// Look up the three IBL compute kernel functions and build pipeline states.
    private static func makeComputePipelines(
        from lib: MTLLibrary,
        device: MTLDevice
    ) throws -> IBLPipelines {
        guard let fnIrr = lib.makeFunction(name: "ibl_gen_irradiance") else {
            throw IBLManagerError.missingKernel("ibl_gen_irradiance")
        }
        guard let fnPref = lib.makeFunction(name: "ibl_gen_prefiltered_env") else {
            throw IBLManagerError.missingKernel("ibl_gen_prefiltered_env")
        }
        guard let fnLUT = lib.makeFunction(name: "ibl_gen_brdf_lut") else {
            throw IBLManagerError.missingKernel("ibl_gen_brdf_lut")
        }
        return IBLPipelines(
            irradiance: try device.makeComputePipelineState(function: fnIrr),
            prefilteredEnv: try device.makeComputePipelineState(function: fnPref),
            brdfLUT: try device.makeComputePipelineState(function: fnLUT)
        )
    }

    // MARK: - Private Texture Allocation

    /// Allocate a `.storageModeShared` cubemap texture with `shaderRead + shaderWrite`.
    private static func makeCube(
        device: MTLDevice,
        size: Int,
        mipLevels: Int
    ) -> MTLTexture? {
        let desc = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: .rgba16Float,
            size: size,
            mipmapped: false
        )
        desc.mipmapLevelCount = mipLevels
        desc.storageMode      = .shared
        desc.usage            = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: desc)
    }

    /// Allocate a `.storageModeShared` 2D `.rg16Float` texture for the BRDF LUT.
    private static func makeLUT(device: MTLDevice, size: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg16Float,
            width: size,
            height: size,
            mipmapped: false
        )
        desc.storageMode = .shared
        desc.usage       = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: desc)
    }

    // MARK: - Private Kernel Dispatch Helpers

    /// Dispatch `ibl_gen_irradiance` over a (faceSize × faceSize × 6) grid.
    private static func dispatchIrradiance(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLComputePipelineState,
        texture: MTLTexture,
        faceSize: Int
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        var sz = UInt32(faceSize)
        encoder.setBytes(&sz, length: MemoryLayout<UInt32>.stride, index: 0)

        let tgSize = MTLSize(width: 8, height: 8, depth: 1)
        let grid   = MTLSize(width: faceSize, height: faceSize, depth: 6)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: tgSize)
        encoder.endEncoding()
    }

    /// Dispatch `ibl_gen_prefiltered_env` once per mip level (0..4).
    /// Each dispatch uses roughness = mip / (mipCount − 1) and the mip-appropriate face size.
    private static func dispatchPrefilteredEnv(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLComputePipelineState,
        texture: MTLTexture
    ) {
        let totalMips = IBLManager.prefilteredMipCount
        let baseSize  = IBLManager.prefilteredFaceSize

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)

        for mip in 0..<totalMips {
            let faceSize  = max(1, baseSize >> mip)
            var roughness = Float(mip) / Float(totalMips - 1)
            var faceSzU   = UInt32(faceSize)
            var mipU      = UInt32(mip)

            encoder.setBytes(&roughness, length: MemoryLayout<Float>.stride, index: 0)
            encoder.setBytes(&faceSzU, length: MemoryLayout<UInt32>.stride, index: 1)
            encoder.setBytes(&mipU, length: MemoryLayout<UInt32>.stride, index: 2)

            let tgSize = MTLSize(width: 8, height: 8, depth: 1)
            let grid   = MTLSize(width: faceSize, height: faceSize, depth: 6)
            encoder.dispatchThreads(grid, threadsPerThreadgroup: tgSize)
        }
        encoder.endEncoding()
    }

    /// Dispatch `ibl_gen_brdf_lut` over a (size × size × 1) grid.
    private static func dispatchBRDFLUT(
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

        let maxTpg  = pipeline.maxTotalThreadsPerThreadgroup
        let tgWidth = Int(sqrt(Double(min(maxTpg, 256))))
        let tgSize  = MTLSize(width: tgWidth, height: tgWidth, depth: 1)
        let grid    = MTLSize(width: size, height: size, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: tgSize)
        encoder.endEncoding()
    }
}

// MARK: - IBLManagerError

/// Errors thrown by `IBLManager.init`.
public enum IBLManagerError: Error, Sendable {
    /// `MTLDevice.makeTexture` returned nil for the named texture.
    case textureAllocationFailed(String)
    /// A required compute kernel was not found in the compiled shader library.
    case missingKernel(String)
    /// `MTLCommandQueue.makeCommandBuffer` returned nil.
    case commandBufferFailed
    /// The GPU reported an error during IBL generation.
    case gpuGenerationFailed(Error)
}
