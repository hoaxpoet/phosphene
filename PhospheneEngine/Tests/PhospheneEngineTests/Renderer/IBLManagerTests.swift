// IBLManagerTests — Tests for the Increment 3.16 IBL pipeline.
//
// Nine tests verify IBL texture dimensions, formats, storage mode, content validity,
// mip chain population, BRDF LUT range, correct binding indices, and generation
// performance under 1 second.
//
// All tests require a Metal device and use XCTest (not swift-testing) to allow
// XCTest.measure {} performance baselines.

import XCTest
import Metal
@testable import Renderer
@testable import Shared

// MARK: - IBLManagerTests

final class IBLManagerTests: XCTestCase {

    private var context: MetalContext!
    private var library: ShaderLibrary!
    private var manager: IBLManager!

    override func setUpWithError() throws {
        context = try MetalContext()
        library = try ShaderLibrary(context: context)
        manager = try IBLManager(context: context, shaderLibrary: library)
    }

    // MARK: - 1. irradianceMap — correct dimensions

    /// `irradianceMap` must be a cubemap with 32×32 faces and one mip level.
    func test_init_createsIrradianceMap() throws {
        let tex = manager.irradianceMap
        XCTAssertEqual(tex.textureType,     .typeCube, "irradianceMap must be a cubemap")
        XCTAssertEqual(tex.width,           IBLManager.irradianceFaceSize,
                       "irradianceMap face width must be \(IBLManager.irradianceFaceSize)")
        XCTAssertEqual(tex.height,          IBLManager.irradianceFaceSize,
                       "irradianceMap face height must be \(IBLManager.irradianceFaceSize)")
        XCTAssertEqual(tex.pixelFormat,     .rgba16Float, "irradianceMap must be .rgba16Float")
        XCTAssertEqual(tex.mipmapLevelCount, 1, "irradianceMap must have exactly 1 mip level")
    }

    // MARK: - 2. prefilteredEnvMap — correct dimensions and mip count

    /// `prefilteredEnvMap` must be a cubemap with 128×128 faces and 5 mip levels.
    func test_init_createsPrefilteredEnvMap() throws {
        let tex = manager.prefilteredEnvMap
        XCTAssertEqual(tex.textureType,      .typeCube, "prefilteredEnvMap must be a cubemap")
        XCTAssertEqual(tex.width,            IBLManager.prefilteredFaceSize,
                       "prefilteredEnvMap face width must be \(IBLManager.prefilteredFaceSize)")
        XCTAssertEqual(tex.height,           IBLManager.prefilteredFaceSize,
                       "prefilteredEnvMap face height must be \(IBLManager.prefilteredFaceSize)")
        XCTAssertEqual(tex.pixelFormat,      .rgba16Float, "prefilteredEnvMap must be .rgba16Float")
        XCTAssertEqual(tex.mipmapLevelCount, IBLManager.prefilteredMipCount,
                       "prefilteredEnvMap must have \(IBLManager.prefilteredMipCount) mip levels")
    }

    // MARK: - 3. brdfLUT — correct dimensions and format

    /// `brdfLUT` must be 512×512 `.rg16Float` (x = scale, y = bias).
    func test_init_createsBRDFLUT() throws {
        let tex = manager.brdfLUT
        XCTAssertEqual(tex.textureType,  .type2D,      "brdfLUT must be a 2D texture")
        XCTAssertEqual(tex.width,        IBLManager.brdfLUTSize, "brdfLUT width must be 512")
        XCTAssertEqual(tex.height,       IBLManager.brdfLUTSize, "brdfLUT height must be 512")
        XCTAssertEqual(tex.pixelFormat,  .rg16Float,   "brdfLUT must be .rg16Float")
    }

    // MARK: - 4. All textures use shared storage (UMA)

    /// Every IBL texture must be `.storageModeShared` for UMA zero-copy on Apple Silicon.
    func test_allTextures_storageModeShared() throws {
        let textures: [(MTLTexture, String)] = [
            (manager.irradianceMap,    "irradianceMap"),
            (manager.prefilteredEnvMap, "prefilteredEnvMap"),
            (manager.brdfLUT,          "brdfLUT"),
        ]
        for (tex, name) in textures {
            XCTAssertEqual(tex.storageMode, .shared,
                           "\(name) must use .storageModeShared (UMA)")
        }
    }

    // MARK: - 5. Irradiance map contains non-black values

    /// Sampling the centre of each face must yield non-zero values — the procedural sky
    /// provides non-zero radiance in all directions.
    func test_irradiance_nonBlack() throws {
        let faceSize = IBLManager.irradianceFaceSize
        // Check all 6 faces.
        for face in 0..<6 {
            let pixels = readCubeFloat16(manager.irradianceMap, face: face,
                                         faceSize: faceSize, mipLevel: 0, channels: 4)
            // Sample the centre pixel (faceSize/2, faceSize/2).
            let center = (faceSize / 2 * faceSize + faceSize / 2) * 4
            let r = pixels[center], g = pixels[center + 1], b = pixels[center + 2]
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            XCTAssertGreaterThan(lum, 0.001,
                "Face \(face) centre pixel must have non-zero luminance (got \(lum))")
        }
    }

    // MARK: - 6. Prefiltered env map mip levels are populated

    /// All 5 mip levels of the prefiltered env map must contain non-zero content.
    /// Each level corresponds to a different roughness (0, 0.25, 0.5, 0.75, 1.0).
    func test_prefilteredEnv_mipLevelsExist() throws {
        let baseSize = IBLManager.prefilteredFaceSize
        for mip in 0..<IBLManager.prefilteredMipCount {
            let faceSize = max(1, baseSize >> mip)  // 128, 64, 32, 16, 8
            let pixels   = readCubeFloat16(manager.prefilteredEnvMap, face: 0,
                                           faceSize: faceSize, mipLevel: mip, channels: 4)
            guard pixels.count >= 4 else {
                XCTFail("Mip \(mip): could not read pixels (faceSize=\(faceSize))")
                continue
            }
            // Centre pixel (or pixel [0] for very small faces).
            let pixIdx = min((faceSize / 2 * faceSize + faceSize / 2) * 4, pixels.count - 4)
            let r = pixels[pixIdx], g = pixels[pixIdx + 1], b = pixels[pixIdx + 2]
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            XCTAssertGreaterThan(lum, 0.001,
                "Prefiltered env mip \(mip) centre pixel must be non-zero (lum=\(lum))")
        }
    }

    // MARK: - 7. BRDF LUT values are in [0, 1]

    /// Sampling corners and the centre of the BRDF LUT must return values in [0, 1].
    /// The split-sum integration produces values bounded by the energy-conserving BRDF.
    func test_brdfLUT_range() throws {
        let size = IBLManager.brdfLUTSize
        // Sample at corners and centre; read full texture as Float16.
        let pixels = readLUTFloat16(manager.brdfLUT, size: size)

        // Check that no value exceeds 1.0 or goes below 0 in the sampled set.
        // We check (0,0), (size/2, size/2), and (size-1, size-1).
        let sampleCoords = [
            (0, 0),
            (size / 2, size / 2),
            (size - 1, size - 1),
        ]
        for (x, y) in sampleCoords {
            let idx = (y * size + x) * 2   // 2 channels: scale (R) + bias (G)
            let scale = pixels[idx]
            let bias  = pixels[idx + 1]
            XCTAssertGreaterThanOrEqual(scale, -0.001,
                "BRDF LUT scale at (\(x),\(y)) must be ≥ 0 (got \(scale))")
            XCTAssertLessThanOrEqual(scale, 1.001,
                "BRDF LUT scale at (\(x),\(y)) must be ≤ 1 (got \(scale))")
            XCTAssertGreaterThanOrEqual(bias, -0.001,
                "BRDF LUT bias at (\(x),\(y)) must be ≥ 0 (got \(bias))")
            XCTAssertLessThanOrEqual(bias, 1.001,
                "BRDF LUT bias at (\(x),\(y)) must be ≤ 1 (got \(bias))")
        }
    }

    // MARK: - 8. bindTextures sets correct fragment texture indices (9–11)

    /// After calling `bindTextures(to:)`, a fragment shader that samples
    /// `texturecube<float>` at [[texture(9)]] must receive the irradiance map.
    func test_bindTextures_setsCorrectIndices() throws {
        // Compile a minimal shader that samples the irradiance cubemap at [[texture(9)]]
        // and outputs the result — verifying the binding is at slot 9.
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut { float4 position [[position]]; float2 uv; };

        vertex VertexOut ibl_test_vertex(uint vid [[vertex_id]]) {
            VertexOut o;
            o.uv = float2((vid << 1) & 2, vid & 2);
            o.position = float4(o.uv * 2.0 - 1.0, 0.0, 1.0);
            return o;
        }

        // Samples irradianceMap at [[texture(9)]].
        // Outputs the +Y face direction (0,1,0) sample as colour.
        fragment float4 ibl_test_fragment(
            VertexOut            in           [[stage_in]],
            texturecube<float>   iblIrradiance [[texture(9)]])
        {
            constexpr sampler s(filter::linear, address::clamp_to_edge);
            float3 dir = normalize(float3(0.0, 1.0, 0.0));  // straight up (+Y face)
            float3 c = iblIrradiance.sample(s, dir).rgb;
            return float4(c, 1.0);
        }
        """

        let device = context.device
        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        options.languageVersion = .version3_1

        let lib = try device.makeLibrary(source: shaderSource, options: options)

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.vertexFunction   = lib.makeFunction(name: "ibl_test_vertex")
        pipeDesc.fragmentFunction = lib.makeFunction(name: "ibl_test_fragment")
        pipeDesc.colorAttachments[0].pixelFormat = .rgba16Float

        let pipeState = try device.makeRenderPipelineState(descriptor: pipeDesc)

        // Offscreen render target (.rgba16Float to hold HDR values).
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: 4, height: 4, mipmapped: false
        )
        texDesc.storageMode = .shared
        texDesc.usage = [.renderTarget, .shaderRead]
        let outTex = try XCTUnwrap(device.makeTexture(descriptor: texDesc),
                                   "Failed to allocate 4×4 offscreen render target")

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture     = outTex
        passDesc.colorAttachments[0].loadAction  = .clear
        passDesc.colorAttachments[0].clearColor  = MTLClearColorMake(0, 0, 0, 1)
        passDesc.colorAttachments[0].storeAction = .store

        guard let cmdBuf  = context.commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            XCTFail("Failed to create command buffer or encoder")
            return
        }

        encoder.setRenderPipelineState(pipeState)
        manager.bindTextures(to: encoder)   // binds irradiance at slot 9
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        if let err = cmdBuf.error {
            XCTFail("GPU error during binding test: \(err)")
            return
        }

        // Read back as Float16.
        var raw = [Float16](repeating: 0, count: 4 * 4 * 4)
        outTex.getBytes(
            &raw,
            bytesPerRow: 4 * 4 * MemoryLayout<Float16>.stride,
            from: MTLRegionMake2D(0, 0, 4, 4),
            mipmapLevel: 0
        )
        let hasNonZero = raw.contains { Float($0) > 0.001 }
        XCTAssertTrue(hasNonZero,
            "Fragment output is all-zero — irradianceMap was not bound at [[texture(9)]]")
    }

    // MARK: - 9. Performance gate: all three textures generated under 1 second

    /// All three IBL textures must be generated in under 1 second on Apple Silicon.
    func test_init_performance_under1s() throws {
        // Warm up — excludes JIT compilation from the timed window.
        _ = try IBLManager(context: context, shaderLibrary: library)

        let start = Date()
        _ = try IBLManager(context: context, shaderLibrary: library)
        let elapsed = Date().timeIntervalSince(start) * 1000.0

        XCTAssertLessThan(elapsed, 1000.0,
            "IBLManager generation took \(String(format: "%.1f", elapsed)) ms; must be < 1000 ms")
    }
}

// MARK: - Helpers

private extension IBLManagerTests {

    /// Read back the pixels of one face and one mip level of a cubemap texture as `[Float]`.
    /// The texture must be `.storageModeShared` and `.rgba16Float`.
    func readCubeFloat16(
        _ texture: MTLTexture,
        face: Int,
        faceSize: Int,
        mipLevel: Int,
        channels: Int
    ) -> [Float] {
        let pixelCount = faceSize * faceSize
        var raw = [Float16](repeating: 0, count: pixelCount * channels)
        texture.getBytes(
            &raw,
            bytesPerRow: faceSize * channels * MemoryLayout<Float16>.stride,
            bytesPerImage: faceSize * faceSize * channels * MemoryLayout<Float16>.stride,
            from: MTLRegionMake2D(0, 0, faceSize, faceSize),
            mipmapLevel: mipLevel,
            slice: face
        )
        return raw.map { Float($0) }
    }

    /// Read back the full base mip of the `.rg16Float` BRDF LUT as `[Float]`.
    func readLUTFloat16(_ texture: MTLTexture, size: Int) -> [Float] {
        var raw = [Float16](repeating: 0, count: size * size * 2)
        texture.getBytes(
            &raw,
            bytesPerRow: size * 2 * MemoryLayout<Float16>.stride,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        return raw.map { Float($0) }
    }
}
