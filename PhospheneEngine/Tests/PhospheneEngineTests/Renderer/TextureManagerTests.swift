// TextureManagerTests — Tests for the Increment 3.13 noise texture manager.
//
// Nine tests verify texture dimensions, formats, storage mode, determinism,
// correct binding indices, and generation performance.
//
// All tests require a Metal device.  They are XCTest (not swift-testing) because
// some tests use XCTest.measure {} for performance baselines.

import XCTest
import Metal
@testable import Renderer
@testable import Shared

// MARK: - TextureManagerTests

final class TextureManagerTests: XCTestCase {

    private var context: MetalContext!
    private var library: ShaderLibrary!
    private var manager: TextureManager!

    override func setUpWithError() throws {
        context = try MetalContext()
        library = try ShaderLibrary(context: context)
        manager = try TextureManager(context: context, shaderLibrary: library)
    }

    // MARK: - 1. All five textures created

    /// `TextureManager.init` must produce five non-nil `MTLTexture` objects.
    func test_init_createsAllFiveTextures() throws {
        XCTAssertNotNil(manager.noiseLQ,     "noiseLQ must be non-nil after init")
        XCTAssertNotNil(manager.noiseHQ,     "noiseHQ must be non-nil after init")
        XCTAssertNotNil(manager.noiseVolume, "noiseVolume must be non-nil after init")
        XCTAssertNotNil(manager.noiseFBM,    "noiseFBM must be non-nil after init")
        XCTAssertNotNil(manager.blueNoise,   "blueNoise must be non-nil after init")
    }

    // MARK: - 2. noiseLQ dimensions and format

    /// `noiseLQ` must be 256×256 `.r8Unorm`.
    func test_noiseLQ_dimensions_256x256() throws {
        let tex = manager.noiseLQ
        XCTAssertEqual(tex.width,       256,       "noiseLQ width must be 256")
        XCTAssertEqual(tex.height,      256,       "noiseLQ height must be 256")
        XCTAssertEqual(tex.pixelFormat, .r8Unorm,  "noiseLQ must be .r8Unorm")
        XCTAssertEqual(tex.textureType, .type2D,   "noiseLQ must be a 2D texture")
    }

    // MARK: - 3. noiseHQ dimensions and format

    /// `noiseHQ` must be 1024×1024 `.r8Unorm`.
    func test_noiseHQ_dimensions_1024x1024() throws {
        let tex = manager.noiseHQ
        XCTAssertEqual(tex.width,       1024,      "noiseHQ width must be 1024")
        XCTAssertEqual(tex.height,      1024,      "noiseHQ height must be 1024")
        XCTAssertEqual(tex.pixelFormat, .r8Unorm,  "noiseHQ must be .r8Unorm")
        XCTAssertEqual(tex.textureType, .type2D,   "noiseHQ must be a 2D texture")
    }

    // MARK: - 4. noiseVolume dimensions, format, and type

    /// `noiseVolume` must be 64×64×64 `.r8Unorm` and typed `.type3D`.
    func test_noiseVolume_dimensions_64x64x64_type3D() throws {
        let tex = manager.noiseVolume
        XCTAssertEqual(tex.textureType, .type3D,  "noiseVolume must be a 3D texture")
        XCTAssertEqual(tex.width,       64,        "noiseVolume width must be 64")
        XCTAssertEqual(tex.height,      64,        "noiseVolume height must be 64")
        XCTAssertEqual(tex.depth,       64,        "noiseVolume depth must be 64")
        XCTAssertEqual(tex.pixelFormat, .r8Unorm,  "noiseVolume must be .r8Unorm")
    }

    // MARK: - 5. noiseFBM pixel format

    /// `noiseFBM` must be `.rgba8Unorm` — it carries 4 independent noise channels.
    func test_noiseFBM_pixelFormat_rgba8Unorm() throws {
        let tex = manager.noiseFBM
        XCTAssertEqual(tex.pixelFormat, .rgba8Unorm,
            "noiseFBM must be .rgba8Unorm (RGBA channels for multi-type noise)")
    }

    // MARK: - 6. All textures use shared storage (UMA)

    /// Every texture must be `.storageModeShared` for UMA zero-copy on Apple Silicon.
    func test_allTextures_storageModeShared() throws {
        let textures: [(MTLTexture, String)] = [
            (manager.noiseLQ,     "noiseLQ"),
            (manager.noiseHQ,     "noiseHQ"),
            (manager.noiseVolume, "noiseVolume"),
            (manager.noiseFBM,    "noiseFBM"),
            (manager.blueNoise,   "blueNoise"),
        ]
        for (tex, name) in textures {
            XCTAssertEqual(tex.storageMode, .shared,
                "\(name) must use .storageModeShared (UMA)")
        }
    }

    // MARK: - 7. Generation is deterministic

    /// Two independent `TextureManager` instances must produce byte-identical
    /// textures — the compute kernels use only thread position as input.
    func test_noiseGeneration_deterministic_sameOutputEachInit() throws {
        let mgr2 = try TextureManager(context: context, shaderLibrary: library)

        // Compare the base mip level of noiseLQ (256×256 × 1 byte = 65 536 bytes).
        let pixels1 = readR8Pixels(manager.noiseLQ, size: 256)
        let pixels2 = readR8Pixels(mgr2.noiseLQ, size: 256)

        XCTAssertEqual(pixels1, pixels2,
            "noiseLQ must be byte-identical across two independent TextureManager inits")

        // Spot-check blueNoise (different algorithm).
        let blue1 = readR8Pixels(manager.blueNoise, size: 256)
        let blue2 = readR8Pixels(mgr2.blueNoise, size: 256)

        XCTAssertEqual(blue1, blue2,
            "blueNoise must be byte-identical across two independent TextureManager inits")
    }

    // MARK: - 8. bindTextures sets correct fragment texture indices

    /// After calling `bindTextures(to:)`, a fragment shader that declares
    /// `noiseLQ [[texture(4)]]` must receive non-zero values — confirming
    /// that the texture was bound at index 4 (not some other index).
    func test_bindTextures_setsCorrectIndices() throws {
        // Compile a minimal self-contained shader: fullscreen_vertex + a fragment that
        // samples from [[texture(4)]] and writes the value to the output colour.
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut { float4 position [[position]]; float2 uv; };

        vertex VertexOut noise_test_vertex(uint vid [[vertex_id]]) {
            VertexOut o;
            o.uv = float2((vid << 1) & 2, vid & 2);
            o.position = float4(o.uv * 2.0 - 1.0, 0.0, 1.0);
            return o;
        }

        // Samples noiseLQ at [[texture(4)]].
        // If TextureManager binds at the correct index, the output will be non-zero.
        fragment float4 noise_test_fragment(
            VertexOut in [[stage_in]],
            texture2d<float> noiseLQ [[texture(4)]])
        {
            constexpr sampler s(filter::nearest, address::repeat);
            float v = noiseLQ.sample(s, float2(0.5, 0.5)).r;
            return float4(v, v, v, 1.0);
        }
        """

        let device = context.device
        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        options.languageVersion = .version3_1

        let lib = try device.makeLibrary(source: shaderSource, options: options)

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.vertexFunction   = lib.makeFunction(name: "noise_test_vertex")
        pipeDesc.fragmentFunction = lib.makeFunction(name: "noise_test_fragment")
        pipeDesc.colorAttachments[0].pixelFormat = .rgba8Unorm
        let pipeState = try device.makeRenderPipelineState(descriptor: pipeDesc)

        // Offscreen render target.
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false
        )
        texDesc.storageMode = .shared
        texDesc.usage = [.renderTarget, .shaderRead]
        let outTex = try XCTUnwrap(device.makeTexture(descriptor: texDesc),
            "Failed to allocate 4×4 offscreen render target")

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture    = outTex
        passDesc.colorAttachments[0].loadAction  = .clear
        passDesc.colorAttachments[0].clearColor  = MTLClearColorMake(0, 0, 0, 1)
        passDesc.colorAttachments[0].storeAction = .store

        guard let cmdBuf  = context.commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            XCTFail("Failed to create command buffer or encoder")
            return
        }

        encoder.setRenderPipelineState(pipeState)
        // Bind noise textures — noiseLQ should land at index 4.
        manager.bindTextures(to: encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        if let err = cmdBuf.error {
            XCTFail("GPU error during binding test: \(err)")
            return
        }

        // Read back the centre pixel (1 RGBA pixel from the 4×4 texture).
        var rgba = [UInt8](repeating: 0, count: 4 * 4 * 4)
        outTex.getBytes(&rgba, bytesPerRow: 4 * 4,
                        from: MTLRegionMake2D(0, 0, 4, 4),
                        mipmapLevel: 0)

        // The R channel of any pixel should be non-zero if noiseLQ was bound at slot 4.
        let hasNonZero = rgba.enumerated().filter { $0.offset % 4 == 0 }.contains { $0.element > 0 }
        XCTAssertTrue(hasNonZero,
            "Fragment output is all-zero — noiseLQ was not bound at [[texture(4)]]")
    }

    // MARK: - 9. Performance gate: total generation under 500 ms

    /// All five noise textures must be generated in under 500 ms on Apple Silicon.
    func test_init_textureGeneration_under500ms() throws {
        // Warm up — excludes JIT compilation from the timed window.
        _ = try TextureManager(context: context, shaderLibrary: library)

        let start = Date()
        _ = try TextureManager(context: context, shaderLibrary: library)
        let elapsed = Date().timeIntervalSince(start) * 1000.0

        XCTAssertLessThan(elapsed, 500.0,
            "TextureManager generation took \(String(format: "%.1f", elapsed)) ms; must be < 500 ms")
    }
}

// MARK: - Helpers

private extension TextureManagerTests {

    /// Read back the base mip level of an `.r8Unorm` 2D texture as `[UInt8]`.
    func readR8Pixels(_ texture: MTLTexture, size: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size * size)
        texture.getBytes(
            &bytes,
            bytesPerRow: size,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        return bytes
    }
}
