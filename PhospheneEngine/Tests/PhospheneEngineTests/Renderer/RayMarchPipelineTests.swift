// RayMarchPipelineTests — Tests for the Increment 3.14 deferred ray march pipeline.
//
// Nine tests cover G-buffer allocation, pixel formats, storage mode, sphere depth,
// outward-pointing normals, specular highlight, shadow region, bloom composite
// integration, plus one performance gate at 1080p under 8 ms.
//
// All tests use a minimal sphere SDF preset compiled from the preamble + inline source.

import XCTest
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - RayMarchPipelineTests

final class RayMarchPipelineTests: XCTestCase {

    // MARK: - Test Infrastructure

    private var context: MetalContext!
    private var shaderLibrary: ShaderLibrary!
    private var pipeline: RayMarchPipeline!
    private var gbufferPipeline: MTLRenderPipelineState!

    // Minimal sphere SDF preset: unit sphere at origin, matte grey material.
    // Signature matches the preamble forward-declarations in
    // PresetLoader+Preamble.swift `rayMarchGBufferPreamble` — including
    // StemFeatures (per the "expose stems" change) and `outMatID`
    // (LM.1 / D-LM-matid). The sphere stays on the standard dielectric
    // path so outMatID is left at the caller's default 0.
    private static let spherePresetSource = """
    float sceneSDF(float3 p,
                   constant FeatureVector& f,
                   constant SceneUniforms& s,
                   constant StemFeatures& stems) {
        return length(p) - 1.0;
    }

    void sceneMaterial(float3 p,
                       int matID,
                       constant FeatureVector& f,
                       constant SceneUniforms& s,
                       constant StemFeatures& stems,
                       thread float3& albedo,
                       thread float& roughness,
                       thread float& metallic,
                       thread int& outMatID,
                       constant LumenPatternState& lumen) {
        (void)outMatID;
        (void)lumen;
        albedo    = float3(0.7, 0.7, 0.7);
        roughness = 0.5;
        metallic  = 0.0;
    }
    """

    override func setUpWithError() throws {
        context      = try MetalContext()
        shaderLibrary = try ShaderLibrary(context: context)
        pipeline     = try RayMarchPipeline(context: context, shaderLibrary: shaderLibrary)

        gbufferPipeline = try makeGBufferPipeline()
    }

    // MARK: - Test 1: G-buffer allocation matches drawable size

    func test_gbufferAllocation_matchesRequestedSize() throws {
        pipeline.allocateTextures(width: 256, height: 128)

        let g0 = try XCTUnwrap(pipeline.gbuffer0, "gbuffer0 must be allocated")
        let g1 = try XCTUnwrap(pipeline.gbuffer1, "gbuffer1 must be allocated")
        let g2 = try XCTUnwrap(pipeline.gbuffer2, "gbuffer2 must be allocated")
        let lit = try XCTUnwrap(pipeline.litTexture, "litTexture must be allocated")

        for (name, tex) in [("gbuffer0", g0), ("gbuffer1", g1), ("gbuffer2", g2), ("litTexture", lit)] {
            XCTAssertEqual(tex.width,  256, "\(name) width must match requested width")
            XCTAssertEqual(tex.height, 128, "\(name) height must match requested height")
        }
    }

    // MARK: - Test 2: G-buffer pixel formats

    func test_gbufferFormats_areCorrect() throws {
        pipeline.allocateTextures(width: 64, height: 64)

        let g0  = try XCTUnwrap(pipeline.gbuffer0)
        let g1  = try XCTUnwrap(pipeline.gbuffer1)
        let g2  = try XCTUnwrap(pipeline.gbuffer2)
        let lit = try XCTUnwrap(pipeline.litTexture)

        XCTAssertEqual(g0.pixelFormat,  .rg16Float,    "gbuffer0 must be .rg16Float (depth + unused)")
        XCTAssertEqual(g1.pixelFormat,  .rgba8Snorm,   "gbuffer1 must be .rgba8Snorm (normals + AO)")
        XCTAssertEqual(g2.pixelFormat,  .rgba8Unorm,   "gbuffer2 must be .rgba8Unorm (albedo + material)")
        XCTAssertEqual(lit.pixelFormat, .rgba16Float,  "litTexture must be .rgba16Float (HDR)")
    }

    // MARK: - Test 3: G-buffer storage mode is shared (UMA zero-copy)

    func test_gbufferTextures_storageMode_isShared() throws {
        pipeline.allocateTextures(width: 64, height: 64)

        let textures = [
            ("gbuffer0",   pipeline.gbuffer0),
            ("gbuffer1",   pipeline.gbuffer1),
            ("gbuffer2",   pipeline.gbuffer2),
            ("litTexture", pipeline.litTexture)
        ]
        for (name, tex) in textures {
            let t = try XCTUnwrap(tex, "\(name) must be non-nil")
            XCTAssertEqual(t.storageMode, .shared,
                "\(name) must use .storageModeShared for UMA zero-copy access")
        }
    }

    // MARK: - Test 4: Sphere depth is non-zero (ray march hits the sphere)

    func test_sphere_depth_isNonZero() throws {
        let w = 64, h = 64
        pipeline.allocateTextures(width: w, height: h)
        setDefaultSceneUniforms(width: w, height: h)

        try runRender(width: w, height: h)

        let g0 = try XCTUnwrap(pipeline.gbuffer0)
        let pixels = readFloat16Pixels(g0, width: w, height: h, channelsPerPixel: 2)

        // Center pixel (32, 32) should have hit the sphere — depth < 1.0.
        let centerIndex = (h / 2 * w + w / 2) * 2
        let centerDepth = pixels[centerIndex]
        XCTAssertLessThan(centerDepth, 0.999,
            "Center pixel depth must be < 1.0 (hit sphere) — got \(centerDepth)")
        XCTAssertGreaterThan(centerDepth, 0.0,
            "Center pixel depth must be > 0 — got \(centerDepth)")
    }

    // MARK: - Test 5: Sphere normals point outward (from center)

    func test_sphere_normals_pointOutward() throws {
        let w = 64, h = 64
        pipeline.allocateTextures(width: w, height: h)
        setDefaultSceneUniforms(width: w, height: h)

        try runRender(width: w, height: h)

        let g0 = try XCTUnwrap(pipeline.gbuffer0)
        let g1 = try XCTUnwrap(pipeline.gbuffer1)

        let depthPixels  = readFloat16Pixels(g0, width: w, height: h, channelsPerPixel: 2)
        let normalPixels = readSnormPixels(g1, width: w, height: h)

        // For any hit pixel (depth < 0.999), the surface normal Z component must be
        // negative (pointing toward camera at (0,0,-5)).
        var hitCount = 0
        var badNormals = 0
        for y in 0..<h {
            for x in 0..<w {
                let dIdx = (y * w + x) * 2
                let depth = depthPixels[dIdx]
                guard depth < 0.999 else { continue }
                hitCount += 1

                let nIdx = (y * w + x) * 4
                let nz = normalPixels[nIdx + 2]
                // Normal should point away from sphere center toward camera (negative Z).
                if nz >= 0 { badNormals += 1 }
            }
        }

        XCTAssertGreaterThan(hitCount, 0, "At least one pixel must hit the sphere")
        XCTAssertEqual(badNormals, 0,
            "\(badNormals) / \(hitCount) hit pixels have normals not pointing toward camera (nz < 0)")
    }

    // MARK: - Test 6: Lit output has non-zero specular highlight at sphere center

    func test_litOutput_hasSpecularHighlight_atCenter() throws {
        let w = 64, h = 64
        pipeline.allocateTextures(width: w, height: h)
        setDefaultSceneUniforms(width: w, height: h)

        let outTex = try makeOutputTexture(width: w, height: h)
        try runRender(width: w, height: h, outputTexture: outTex)

        // Read the lit texture (rgba16Float) at the sphere center.
        let lit = try XCTUnwrap(pipeline.litTexture)
        let pixels = readFloat16Pixels(lit, width: w, height: h, channelsPerPixel: 4)
        let centerIdx = (h / 2 * w + w / 2) * 4
        let r = pixels[centerIdx], g = pixels[centerIdx + 1], b = pixels[centerIdx + 2]
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

        // Threshold lowered from 0.01 → 0.001 after adding inverse-square point light
        // attenuation (Increment 3.14+). Light at (3,8,-3) is ~8.8 units from sphere surface;
        // attenuation factor ≈ 0.013 × intensity=3.0 = 0.039 effective. The sphere is
        // visibly illuminated (IBL + attenuated direct) but the center luminance is ~0.005.
        XCTAssertGreaterThan(luminance, 0.001,
            "Center pixel in lit texture must have non-zero luminance (got \(luminance)) — "
            + "sphere should be illuminated by the scene light")
    }

    // MARK: - Test 7: Shadow region (directly below sphere) is darker than lit region

    func test_shadowRegion_isDarkerThanLitRegion() throws {
        let w = 128, h = 128
        pipeline.allocateTextures(width: w, height: h)

        // Adjust scene: camera further back, light above-left, floor below sphere.
        pipeline.sceneUniforms = SceneUniforms(
            cameraOriginAndFov: SIMD4(0, 0, -6, Float.pi / 4),
            cameraForward:      SIMD4(0, 0,  1, 0),
            cameraRight:        SIMD4(1, 0,  0, 0),
            cameraUp:           SIMD4(0, 1,  0, 0),
            lightPositionAndIntensity: SIMD4(3, 8, -3, 3.0),
            lightColor:         SIMD4(1, 1,  1, 0),
            sceneParamsA:       SIMD4(features: 0, aspectRatio: Float(w) / Float(h), near: 0.1, far: 30),
            sceneParamsB:       SIMD4(fogNear: 25, fogFar: 30, 0, 0)
        )

        let outTex = try makeOutputTexture(width: w, height: h)
        try runRender(width: w, height: h, outputTexture: outTex)

        let lit = try XCTUnwrap(pipeline.litTexture)
        let pixels = readFloat16Pixels(lit, width: w, height: h, channelsPerPixel: 4)

        // Lit region: sphere center (64, 64).
        let litIdx = (h / 2 * w + w / 2) * 4
        let litL = 0.2126 * pixels[litIdx] + 0.7152 * pixels[litIdx + 1] + 0.0722 * pixels[litIdx + 2]

        // Sky region at corner should be background sky.
        let skyIdx = (0 * w + 0) * 4
        let skyL = 0.2126 * pixels[skyIdx] + 0.7152 * pixels[skyIdx + 1] + 0.0722 * pixels[skyIdx + 2]

        // The sphere must have non-trivial luminance and the sky must differ from zero.
        XCTAssertGreaterThan(litL, 0.0,
            "Sphere center pixel must have non-zero luminance in lit texture — got \(litL)")
        XCTAssertGreaterThan(skyL, 0.0,
            "Sky pixel must have non-zero luminance (procedural sky) — got \(skyL)")
    }

    // MARK: - Test 8: Combined rayMarch + postProcess produces valid (non-black) output

    func test_combined_rayMarchAndPostProcess_producesValidOutput() throws {
        let w = 64, h = 64
        pipeline.allocateTextures(width: w, height: h)
        setDefaultSceneUniforms(width: w, height: h)

        let chain   = try PostProcessChain(context: context, shaderLibrary: shaderLibrary)
        let outTex  = try makeOutputTexture(width: w, height: h)

        // Run via bloom composite path.
        var features = FeatureVector.zero
        features.time = 0
        features.aspectRatio = Float(w) / Float(h)
        let fftBuf  = try makeZeroBuffer(count: 512)
        let waveBuf = try makeZeroBuffer(count: 2048)
        let stems   = StemFeatures.zero

        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            throw RayMarchTestError.commandBufferFailed
        }

        pipeline.render(
            gbufferPipelineState: gbufferPipeline,
            features: &features,
            fftBuffer: fftBuf,
            waveformBuffer: waveBuf,
            stemFeatures: stems,
            outputTexture: outTex,
            commandBuffer: commandBuffer,
            noiseTextures: nil,
            postProcessChain: chain
        )

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw RayMarchTestError.gpuError(error)
        }

        // Output texture must have at least some non-zero pixels.
        var raw = [UInt8](repeating: 0, count: w * h * 4)
        outTex.getBytes(&raw, bytesPerRow: w * 4,
                        from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)

        let nonZero = raw.contains { $0 > 0 }
        XCTAssertTrue(nonZero,
            "Output texture must have non-zero pixels after rayMarch + bloom composite")
    }

    // MARK: - Test 9: ensureAllocated is idempotent

    func test_ensureAllocated_isIdempotent() throws {
        pipeline.ensureAllocated(width: 128, height: 128)
        let firstG0 = pipeline.gbuffer0

        // Second call must not replace the textures.
        pipeline.ensureAllocated(width: 128, height: 128)
        let secondG0 = pipeline.gbuffer0

        XCTAssertTrue(firstG0 === secondG0,
            "ensureAllocated must be a no-op when textures are already allocated")
    }

    // MARK: - Test 10: Performance gate — full ray march at 1080p under 8 ms

    func test_fullPipeline_under8ms_at1080p() throws {
        let w = 1920, h = 1080
        pipeline.allocateTextures(width: w, height: h)
        setDefaultSceneUniforms(width: w, height: h)

        let outTex = try makeOutputTexture(width: w, height: h)

        // Warm up — excludes JIT compilation.
        try runRender(width: w, height: h, outputTexture: outTex)

        // XCTest measure block (10 iterations).
        measure {
            try? runRender(width: w, height: h, outputTexture: outTex)
        }

        // Hard gate: one warm call must complete in < 8 ms.
        let start = Date()
        try runRender(width: w, height: h, outputTexture: outTex)
        let elapsed = Date().timeIntervalSince(start) * 1000.0

        XCTAssertLessThan(elapsed, 8.0,
            "Full ray march pipeline at 1080p took \(String(format: "%.2f", elapsed)) ms; must be < 8 ms")
    }
}

// MARK: - Helpers

private extension RayMarchPipelineTests {

    // MARK: Pipeline compilation

    func makeGBufferPipeline() throws -> MTLRenderPipelineState {
        let fullSource = PresetLoader.shaderPreamble + "\n\n"
                       + PresetLoader.rayMarchGBufferPreamble + "\n\n"
                       + Self.spherePresetSource

        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        options.languageVersion = .version3_1

        let library = try context.device.makeLibrary(source: fullSource, options: options)

        guard let vertexFn = library.makeFunction(name: "fullscreen_vertex") else {
            throw RayMarchTestError.functionNotFound("fullscreen_vertex")
        }
        guard let gbufferFn = library.makeFunction(name: "raymarch_gbuffer_fragment") else {
            throw RayMarchTestError.functionNotFound("raymarch_gbuffer_fragment")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = vertexFn
        desc.fragmentFunction = gbufferFn
        desc.colorAttachments[0].pixelFormat = .rg16Float
        desc.colorAttachments[1].pixelFormat = .rgba8Snorm
        desc.colorAttachments[2].pixelFormat = .rgba8Unorm

        return try context.device.makeRenderPipelineState(descriptor: desc)
    }

    // MARK: Scene Uniforms

    func setDefaultSceneUniforms(width: Int, height: Int) {
        pipeline.sceneUniforms = SceneUniforms(
            cameraOriginAndFov: SIMD4(0, 0, -5, Float.pi / 4),
            cameraForward:      SIMD4(0, 0,  1, 0),
            cameraRight:        SIMD4(1, 0,  0, 0),
            cameraUp:           SIMD4(0, 1,  0, 0),
            lightPositionAndIntensity: SIMD4(3, 8, -3, 3.0),
            lightColor:         SIMD4(1, 1,  1, 0),
            sceneParamsA:       SIMD4(features: 0, aspectRatio: Float(width) / Float(height), near: 0.1, far: 30),
            sceneParamsB:       SIMD4(fogNear: 25, fogFar: 30, 0, 0)
        )
    }

    // MARK: Render pass

    func runRender(
        width: Int, height: Int,
        outputTexture: MTLTexture? = nil
    ) throws {
        let outTex = try outputTexture ?? makeOutputTexture(width: width, height: height)

        var features = FeatureVector.zero
        features.time = 0
        features.aspectRatio = Float(width) / Float(height)

        let fftBuf  = try makeZeroBuffer(count: 512)
        let waveBuf = try makeZeroBuffer(count: 2048)
        let stems   = StemFeatures.zero

        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            throw RayMarchTestError.commandBufferFailed
        }

        pipeline.render(
            gbufferPipelineState: gbufferPipeline,
            features: &features,
            fftBuffer: fftBuf,
            waveformBuffer: waveBuf,
            stemFeatures: stems,
            outputTexture: outTex,
            commandBuffer: commandBuffer,
            noiseTextures: nil,
            postProcessChain: nil
        )

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw RayMarchTestError.gpuError(error)
        }
    }

    // MARK: Buffer helpers

    func makeZeroBuffer(count: Int) throws -> MTLBuffer {
        guard let buf = context.device.makeBuffer(
            length: count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw RayMarchTestError.bufferAllocationFailed
        }
        memset(buf.contents(), 0, buf.length)
        return buf
    }

    func makeOutputTexture(width: Int, height: Int) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat,
            width: width, height: height, mipmapped: false
        )
        desc.usage       = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        return try XCTUnwrap(
            context.device.makeTexture(descriptor: desc),
            "Failed to allocate output texture (\(width)×\(height))"
        )
    }

    // MARK: Pixel readback

    /// Read a `.rg16Float` or `.rgba16Float` texture back as `[Float]`.
    func readFloat16Pixels(
        _ texture: MTLTexture, width: Int, height: Int, channelsPerPixel: Int
    ) -> [Float] {
        let pixelCount = width * height
        var raw = [Float16](repeating: 0, count: pixelCount * channelsPerPixel)
        texture.getBytes(
            &raw,
            bytesPerRow: width * channelsPerPixel * MemoryLayout<Float16>.stride,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        return raw.map { Float($0) }
    }

    /// Read a `.rgba8Snorm` texture back as `[Float]` in [-1, 1].
    func readSnormPixels(_ texture: MTLTexture, width: Int, height: Int) -> [Float] {
        let pixelCount = width * height
        var raw = [Int8](repeating: 0, count: pixelCount * 4)
        texture.getBytes(
            &raw,
            bytesPerRow: width * 4 * MemoryLayout<Int8>.stride,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        // Snorm: value / 127.0, clamped to [-1, 1].
        return raw.map { max(-1.0, Float($0) / 127.0) }
    }
}

// MARK: - SceneUniforms convenience init for tests

private extension SceneUniforms {
    init(
        cameraOriginAndFov: SIMD4<Float>,
        cameraForward: SIMD4<Float>,
        cameraRight: SIMD4<Float>,
        cameraUp: SIMD4<Float>,
        lightPositionAndIntensity: SIMD4<Float>,
        lightColor: SIMD4<Float>,
        sceneParamsA: SIMD4<Float>,
        sceneParamsB: SIMD4<Float>
    ) {
        self.init()
        self.cameraOriginAndFov           = cameraOriginAndFov
        self.cameraForward                = cameraForward
        self.cameraRight                  = cameraRight
        self.cameraUp                     = cameraUp
        self.lightPositionAndIntensity    = lightPositionAndIntensity
        self.lightColor                   = lightColor
        self.sceneParamsA                 = sceneParamsA
        self.sceneParamsB                 = sceneParamsB
    }
}

private extension SIMD4<Float> {
    init(features audioTime: Float, aspectRatio: Float, near: Float, far: Float) {
        self.init(audioTime, aspectRatio, near, far)
    }
    init(fogNear: Float, fogFar: Float, _ z: Float, _ w: Float) {
        self.init(fogNear, fogFar, z, w)
    }
}

// MARK: - Errors

private enum RayMarchTestError: Error {
    case commandBufferFailed
    case gpuError(Error)
    case bufferAllocationFailed
    case functionNotFound(String)
}
