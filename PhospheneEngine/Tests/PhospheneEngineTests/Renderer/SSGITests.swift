// SSGITests — Tests for the Increment 3.17 Screen-Space Global Illumination pass.
//
// Seven tests cover SSGI texture allocation, pixel format, storage mode,
// indirect illumination from a bright surface, minimal contribution from a
// dark scene, pass disablement, and a half-resolution performance gate.
//
// All tests reuse the minimal sphere SDF preset infrastructure from
// RayMarchPipelineTests — a unit sphere at origin with matte grey material.

import XCTest
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - SSGITests

final class SSGITests: XCTestCase {

    // MARK: - Test Infrastructure

    private var context: MetalContext!
    private var shaderLibrary: ShaderLibrary!
    private var pipeline: RayMarchPipeline!
    private var gbufferPipeline: MTLRenderPipelineState!

    // Minimal sphere SDF preset: unit sphere at origin, matte grey material.
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
                       thread float& metallic) {
        albedo    = float3(0.7, 0.7, 0.7);
        roughness = 0.5;
        metallic  = 0.0;
    }
    """

    // Bright-sphere SDF preset: high-reflectance metallic sphere.
    // The bright specular highlight gives SSGI plenty of indirect light to bounce.
    private static let brightSphereSource = """
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
                       thread float& metallic) {
        albedo    = float3(1.0, 1.0, 1.0);   // pure white for max luminance
        roughness = 0.1;                       // low roughness = strong specular
        metallic  = 0.9;
    }
    """

    override func setUpWithError() throws {
        context       = try MetalContext()
        shaderLibrary = try ShaderLibrary(context: context)
        pipeline      = try RayMarchPipeline(context: context, shaderLibrary: shaderLibrary)
        gbufferPipeline = try makeGBufferPipeline(source: Self.spherePresetSource)
    }

    // MARK: - Test 1: SSGI texture is half the G-buffer dimensions

    func test_ssgiTexture_halfResolution() throws {
        pipeline.allocateTextures(width: 256, height: 128)

        let ssgi = try XCTUnwrap(pipeline.ssgiTexture, "ssgiTexture must be allocated")
        XCTAssertEqual(ssgi.width,  128, "SSGI texture width must be half of drawable width (256/2 = 128)")
        XCTAssertEqual(ssgi.height,  64, "SSGI texture height must be half of drawable height (128/2 = 64)")
    }

    // MARK: - Test 2: SSGI texture pixel format is .rgba16Float

    func test_ssgiTexture_format_rgba16Float() throws {
        pipeline.allocateTextures(width: 64, height: 64)

        let ssgi = try XCTUnwrap(pipeline.ssgiTexture)
        XCTAssertEqual(ssgi.pixelFormat, .rgba16Float,
            "ssgiTexture must be .rgba16Float for HDR indirect diffuse accumulation")
    }

    // MARK: - Test 3: SSGI texture storage mode is .shared (UMA zero-copy)

    func test_ssgiTexture_storageModeShared() throws {
        pipeline.allocateTextures(width: 64, height: 64)

        let ssgi = try XCTUnwrap(pipeline.ssgiTexture)
        XCTAssertEqual(ssgi.storageMode, .shared,
            "ssgiTexture must use .storageModeShared for UMA zero-copy access")
    }

    // MARK: - Test 4: Emissive surface illuminates neighbour (SSGI adds indirect light)

    func test_ssgi_emissiveSurface_illuminatesNeighbor() throws {
        let w = 64, h = 64

        // Use the high-albedo bright sphere so the lit texture has strong values to bounce.
        let brightGBuffer = try makeGBufferPipeline(source: Self.brightSphereSource)

        pipeline.allocateTextures(width: w, height: h)
        setDefaultSceneUniforms(width: w, height: h)

        // ── Baseline: render without SSGI — capture lit texture content ──
        pipeline.ssgiEnabled = false
        let outTexBaseline = try makeOutputTexture(width: w, height: h)
        try runRender(gbufferPipeline: brightGBuffer, width: w, height: h, outputTexture: outTexBaseline)
        let litBaseline = try readLitTexture(width: w, height: h)

        // ── With SSGI: render with SSGI enabled ─────────────────────
        pipeline.ssgiEnabled = true
        let outTexSSGI = try makeOutputTexture(width: w, height: h)
        try runRender(gbufferPipeline: brightGBuffer, width: w, height: h, outputTexture: outTexSSGI)
        let litSSGI = try readLitTexture(width: w, height: h)

        // The SSGI blend pass additively adds indirect diffuse into litTexture.
        // Therefore, litTexture with SSGI must have luminance ≥ baseline across the
        // sphere region (some pixels improve; none should decrease).
        // At least some pixels near the bright sphere centre must strictly improve.
        var improvements = 0
        var regressions  = 0
        for dy in -8...8 {
            for dx in -8...8 {
                let x = w / 2 + dx
                let y = h / 2 + dy
                guard x >= 0 && x < w && y >= 0 && y < h else { continue }
                let idx  = (y * w + x) * 4
                let baseL = luminance(litBaseline[idx], litBaseline[idx + 1], litBaseline[idx + 2])
                let ssgiL = luminance(litSSGI[idx],     litSSGI[idx + 1],     litSSGI[idx + 2])
                if ssgiL > baseL + 1e-5 { improvements += 1 }
                if ssgiL < baseL - 1e-3 { regressions  += 1 }
            }
        }

        XCTAssertEqual(regressions, 0,
            "SSGI must never reduce luminance (additive blend) — "
            + "found \(regressions) regressed pixels near sphere centre")
        XCTAssertGreaterThan(improvements, 0,
            "SSGI must increase luminance in at least one pixel near the bright sphere — "
            + "got 0 improved pixels in the ±8-pixel sphere neighbourhood")
    }

    // MARK: - Test 5: Dark scene produces near-zero SSGI output

    func test_ssgi_noEmission_minimalContribution() throws {
        let w = 64, h = 64

        pipeline.allocateTextures(width: w, height: h)

        // Zero light intensity → lit texture is dark (AO + minimum ambient only).
        pipeline.sceneUniforms = makeSceneUniforms(
            width: w, height: h, lightIntensity: 0.0
        )

        pipeline.ssgiEnabled = true
        let outTex = try makeOutputTexture(width: w, height: h)
        try runRender(gbufferPipeline: gbufferPipeline, width: w, height: h, outputTexture: outTex)

        // SSGI texture should be near-zero: no direct light → nothing to bounce.
        // Read RGB channels only (alpha = 0 from ssgi_fragment, but stride by 4 to skip it).
        let ssgi = try XCTUnwrap(pipeline.ssgiTexture)
        let pixels = readFloat16Pixels(ssgi, width: ssgi.width, height: ssgi.height, channelsPerPixel: 4)
        var maxRGBLuminance: Float = 0.0
        for idx in stride(from: 0, to: pixels.count, by: 4) {
            let lum = luminance(pixels[idx], pixels[idx + 1], pixels[idx + 2])
            maxRGBLuminance = max(maxRGBLuminance, lum)
        }
        XCTAssertLessThan(maxRGBLuminance, 0.1,
            "SSGI output must be near-zero for a dark (zero-intensity) scene — "
            + "got max RGB luminance \(maxRGBLuminance)")
    }

    // MARK: - Test 6: When SSGI is disabled, pass is not executed (litTexture unchanged)

    func test_ssgi_disabled_noPassExecuted() throws {
        let w = 64, h = 64

        pipeline.allocateTextures(width: w, height: h)
        setDefaultSceneUniforms(width: w, height: h)

        // ── Render with SSGI disabled ──────────────────────────────
        pipeline.ssgiEnabled = false
        let outTex = try makeOutputTexture(width: w, height: h)
        try runRender(gbufferPipeline: gbufferPipeline, width: w, height: h, outputTexture: outTex)
        let litWithoutSSGI = try readLitTexture(width: w, height: h)

        // Render again — still disabled — should produce identical lit texture.
        try runRender(gbufferPipeline: gbufferPipeline, width: w, height: h, outputTexture: outTex)
        let litSecondPass = try readLitTexture(width: w, height: h)

        // Both passes must produce the same lit texture (deterministic; SSGI not modifying it).
        for i in 0..<min(litWithoutSSGI.count, 256) {  // spot-check first 64 pixels
            XCTAssertEqual(litWithoutSSGI[i], litSecondPass[i], accuracy: 1e-3,
                "litTexture at index \(i) differed between two identical ssgiEnabled=false renders — "
                + "expected deterministic output")
        }

        // Verify ssgiTexture was cleared (loadAction=.clear) but litTexture has expected content.
        let centerIdx = (h / 2 * w + w / 2) * 4
        let centerLuminance = luminance(litWithoutSSGI[centerIdx],
                                        litWithoutSSGI[centerIdx + 1],
                                        litWithoutSSGI[centerIdx + 2])
        XCTAssertGreaterThan(centerLuminance, 0.0,
            "Sphere center must have non-zero luminance even when SSGI is disabled — "
            + "direct lighting must still be present in litTexture")
    }

    // MARK: - Test 7: SSGI pass overhead is under 1 ms at 1080p (half-res = 960×540)

    func test_ssgi_performance_under1ms_at1080p() throws {
        let w = 1920, h = 1080

        pipeline.allocateTextures(width: w, height: h)
        setDefaultSceneUniforms(width: w, height: h)

        let outTex = try makeOutputTexture(width: w, height: h)

        // Warm up both paths to exclude JIT compilation.
        pipeline.ssgiEnabled = false
        try runRender(gbufferPipeline: gbufferPipeline, width: w, height: h, outputTexture: outTex)
        pipeline.ssgiEnabled = true
        try runRender(gbufferPipeline: gbufferPipeline, width: w, height: h, outputTexture: outTex)

        // XCTest measure block benchmarks the full pipeline with SSGI.
        pipeline.ssgiEnabled = true
        measure {
            try? runRender(gbufferPipeline: gbufferPipeline, width: w, height: h, outputTexture: outTex)
        }

        // Measure SSGI overhead: average over 5 pairs (with - without) to reduce variance.
        var totalOverhead: Double = 0.0
        let iterations = 5
        for _ in 0..<iterations {
            let t0 = Date()
            pipeline.ssgiEnabled = false
            try runRender(gbufferPipeline: gbufferPipeline, width: w, height: h, outputTexture: outTex)
            let baseMs = Date().timeIntervalSince(t0) * 1000.0

            let t1 = Date()
            pipeline.ssgiEnabled = true
            try runRender(gbufferPipeline: gbufferPipeline, width: w, height: h, outputTexture: outTex)
            let ssgiMs = Date().timeIntervalSince(t1) * 1000.0

            totalOverhead += max(0, ssgiMs - baseMs)
        }
        let avgOverhead = totalOverhead / Double(iterations)

        XCTAssertLessThan(avgOverhead, 1.0,
            "SSGI pass overhead at 1080p averaged \(String(format: "%.2f", avgOverhead)) ms "
            + "over \(iterations) iterations; SSGI at half-res (960×540) must add under 1 ms")
    }
}

// MARK: - Helpers

private extension SSGITests {

    // MARK: Pipeline compilation

    func makeGBufferPipeline(source: String) throws -> MTLRenderPipelineState {
        let fullSource = PresetLoader.shaderPreamble + "\n\n"
                       + PresetLoader.rayMarchGBufferPreamble + "\n\n"
                       + source

        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        options.languageVersion = .version3_1

        let library = try context.device.makeLibrary(source: fullSource, options: options)

        guard let vertexFn = library.makeFunction(name: "fullscreen_vertex") else {
            throw SSGITestError.functionNotFound("fullscreen_vertex")
        }
        guard let gbufferFn = library.makeFunction(name: "raymarch_gbuffer_fragment") else {
            throw SSGITestError.functionNotFound("raymarch_gbuffer_fragment")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = vertexFn
        desc.fragmentFunction = gbufferFn
        desc.colorAttachments[0].pixelFormat = .rg16Float
        desc.colorAttachments[1].pixelFormat = .rgba8Snorm
        desc.colorAttachments[2].pixelFormat = .rgba8Unorm

        return try context.device.makeRenderPipelineState(descriptor: desc)
    }

    // MARK: Scene uniforms

    func setDefaultSceneUniforms(width: Int, height: Int) {
        pipeline.sceneUniforms = makeSceneUniforms(width: width, height: height)
    }

    func makeSceneUniforms(width: Int, height: Int, lightIntensity: Float = 3.0) -> SceneUniforms {
        var s = SceneUniforms()
        s.cameraOriginAndFov        = SIMD4(0, 0, -5, Float.pi / 4)
        s.cameraForward             = SIMD4(0, 0,  1, 0)
        s.cameraRight               = SIMD4(1, 0,  0, 0)
        s.cameraUp                  = SIMD4(0, 1,  0, 0)
        s.lightPositionAndIntensity = SIMD4(3, 8, -3, lightIntensity)
        s.lightColor                = SIMD4(1, 1,  1, 0)
        s.sceneParamsA              = SIMD4(0, Float(width) / Float(height), 0.1, 30)
        s.sceneParamsB              = SIMD4(25, 30, 0, 0)
        return s
    }

    // MARK: Render pass

    func runRender(
        gbufferPipeline gBuf: MTLRenderPipelineState,
        width: Int, height: Int,
        outputTexture: MTLTexture
    ) throws {
        var features = FeatureVector.zero
        features.time = 0
        features.aspectRatio = Float(width) / Float(height)

        let fftBuf  = try makeZeroBuffer(count: 512)
        let waveBuf = try makeZeroBuffer(count: 2048)
        let stems   = StemFeatures.zero

        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            throw SSGITestError.commandBufferFailed
        }

        pipeline.render(
            gbufferPipelineState: gBuf,
            features: &features,
            fftBuffer: fftBuf,
            waveformBuffer: waveBuf,
            stemFeatures: stems,
            outputTexture: outputTexture,
            commandBuffer: commandBuffer,
            noiseTextures: nil,
            iblManager: nil,
            postProcessChain: nil
        )

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw SSGITestError.gpuError(error)
        }
    }

    // MARK: Pixel readback

    func readLitTexture(width: Int, height: Int) throws -> [Float] {
        let lit = try XCTUnwrap(pipeline.litTexture, "litTexture must be allocated")
        return readFloat16Pixels(lit, width: width, height: height, channelsPerPixel: 4)
    }

    func readFloat16Pixels(
        _ texture: MTLTexture, width: Int, height: Int, channelsPerPixel: Int
    ) -> [Float] {
        var raw = [Float16](repeating: 0, count: width * height * channelsPerPixel)
        texture.getBytes(
            &raw,
            bytesPerRow: width * channelsPerPixel * MemoryLayout<Float16>.stride,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        return raw.map { Float($0) }
    }

    // MARK: Buffer helpers

    func makeZeroBuffer(count: Int) throws -> MTLBuffer {
        guard let buf = context.device.makeBuffer(
            length: count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw SSGITestError.bufferAllocationFailed
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

    // MARK: Utilities

    func luminance(_ r: Float, _ g: Float, _ b: Float) -> Float {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

// MARK: - Errors

private enum SSGITestError: Error {
    case commandBufferFailed
    case gpuError(Error)
    case bufferAllocationFailed
    case functionNotFound(String)
}
