// GlassBrutalistTests.swift — G-buffer and lit-texture regression tests for the Glass Brutalist preset.
//
// PURPOSE: Two specific failure modes have caused GlassBrutalist to render incorrectly.
// Each test is designed to catch exactly one failure mode via CPU-readable G-buffer texture
// readback (.storageModeShared, zero-copy), rather than visual inspection.
//
// Failure mode 1 — Geometry not hit:
//   sceneSDF returns a diagnostic constant (return -1.0f stub) or otherwise never hits.
//   Symptom: all G-buffer depth pixels ≈ 1.0 (ray-march far-plane = sky/no-hit).
//   Caught by: test_hitsGeometry_atCorridorCenter
//
// Failure mode 2 — Blue-sky IBL environment applied to indoor scene:
//   ibl_proc_env returned a blue-sky gradient, making glass reflect medium blue and
//   concrete appear sky-blue regardless of actual geometry or lighting.
//   Symptom: litTexture hit-pixels have R/B < 0.5 (blue dominates strongly).
//   Caught by: test_litTexture_isNotBlueSky
//
// Test infrastructure mirrors RayMarchPipelineTests exactly. The key difference:
// these tests load the *actual* GlassBrutalist.metal source from disk via #file
// navigation, so the tests always compile the live shader — not an inlined copy.
// A regression in the preset source file will fail these tests immediately.

import XCTest
import Metal
import simd
@testable import Renderer
@testable import Presets
@testable import Shared

final class GlassBrutalistTests: XCTestCase {

    private var context: MetalContext!
    private var shaderLibrary: ShaderLibrary!
    private var pipeline: RayMarchPipeline!
    private var gbufferPipeline: MTLRenderPipelineState?

    override func setUpWithError() throws {
        context       = try MetalContext()
        shaderLibrary = try ShaderLibrary(context: context)
        pipeline      = try RayMarchPipeline(context: context, shaderLibrary: shaderLibrary)
        gbufferPipeline = try makeGlassBrutalistGBufferPipeline()
    }

    // MARK: - Test 1: Shader compilation succeeds

    /// Basic sanity check: GlassBrutalist.metal must compile without errors against
    /// the full preamble (ShaderUtilities + SceneUniforms + raymarch_gbuffer_fragment).
    /// If this fails, all subsequent tests are meaningless — fix the syntax error first.
    func test_glassBrutalist_shaderCompiles() throws {
        XCTAssertNotNil(gbufferPipeline,
            "GlassBrutalist G-buffer pipeline must compile. Check Xcode console for MSL error.")
    }

    // MARK: - Test 2: Corridor geometry covers most of the frame

    /// Renders one frame with the GlassBrutalist test camera and reads back the
    /// G-buffer depth texture. The Option-A redesign (fins-not-panels) makes the
    /// corridor centreline open air — the exact centre pixel may intentionally
    /// miss near geometry and fade into fog. This test therefore checks frame
    /// coverage (≥ 20% hit) plus an off-centre pillar hit, rather than the
    /// centre pixel specifically.
    ///
    /// Regression: catches any sceneSDF stub (return -1.0f diagnostic, return 1e10, etc.)
    /// that prevents geometry from being hit anywhere.
    func test_hitsGeometry_atCorridorCenter() throws {
        let w = 128, h = 128
        pipeline.allocateTextures(width: w, height: h)
        applyGlassBrutalistCamera(width: w, height: h)

        let gbuf = try XCTUnwrap(gbufferPipeline,
            "G-buffer pipeline failed to compile — cannot run geometry test")
        try runRender(gbuf: gbuf, width: w, height: h)

        let g0    = try XCTUnwrap(pipeline.gbuffer0)
        let depth = readFloat16Pixels(g0, width: w, height: h, channelsPerPixel: 2)

        // Off-centre pixel at x = 3/4 of the frame must hit a glass fin or pillar —
        // fins sit at screen quarter-points from a centreline camera.
        let offsetIdx   = (h / 2 * w + (3 * w / 4)) * 2
        let offsetDepth = depth[offsetIdx]
        XCTAssertLessThan(offsetDepth, 0.99,
            "Off-centre pixel depth must be < 0.99 (fin/pillar hit), got \(offsetDepth). "
            + "If depth ≈ 1.0, sceneSDF is not hitting geometry for any ray. "
            + "Check for diagnostic stubs (e.g. `return -1.0f`) left in sceneSDF.")

        // At least 20% of pixels must hit something — the open corridor centreline
        // is expected to fade to fog, but fins, pillars, walls, floor, and ceiling
        // should still cover the majority of the frame.
        var hitCount = 0
        for i in stride(from: 0, to: w * h * 2, by: 2) where depth[i] < 0.99 { hitCount += 1 }
        let hitFraction = Double(hitCount) / Double(w * h)
        XCTAssertGreaterThan(hitFraction, 0.20,
            "At least 20%% of pixels must hit corridor geometry, got \(Int(hitFraction * 100))%%. "
            + "Camera may be mis-positioned, the corridor SDF may be broken, or nearPlane/farPlane "
            + "may exclude valid hit distances.")
    }

    // MARK: - Test 3: Lit texture is not sky-blue

    /// Renders one frame and reads back the litTexture (rgba16Float, after PBR lighting).
    ///
    /// For hit pixels, checks that the red channel is not dramatically below blue.
    /// A sky-blue IBL environment produces R≈0.45, B≈0.90 (ratio R/B ≈ 0.5) on all
    /// surfaces — making the concrete corridor appear indistinguishable from open sky.
    ///
    /// Regression: catches ibl_proc_env returning an outdoor sky gradient for directions
    /// that glass panels reflect into (horizontal, dir.y ≈ 0).
    func test_litTexture_isNotBlueSky() throws {
        let w = 128, h = 128
        pipeline.allocateTextures(width: w, height: h)
        applyGlassBrutalistCamera(width: w, height: h)

        let gbuf   = try XCTUnwrap(gbufferPipeline)
        let outTex = try makeOutputTexture(width: w, height: h)
        try runRender(gbuf: gbuf, width: w, height: h, outputTexture: outTex)

        let g0     = try XCTUnwrap(pipeline.gbuffer0)
        let lit    = try XCTUnwrap(pipeline.litTexture)
        let depth  = readFloat16Pixels(g0,  width: w, height: h, channelsPerPixel: 2)
        let pixels = readFloat16Pixels(lit, width: w, height: h, channelsPerPixel: 4)

        var hitCount       = 0
        var blueSkySkyCount = 0

        for i in 0..<w * h {
            guard depth[i * 2] < 0.99 else { continue }
            hitCount += 1
            let r = pixels[i * 4], b = pixels[i * 4 + 2]
            // Flag pixels with strongly blue-dominant colour (sky-blue signature: R/B < 0.5).
            if b > 0.05 && r / b < 0.5 { blueSkySkyCount += 1 }
        }

        guard hitCount > 0 else {
            XCTFail("No geometry hit in lit texture test — run test_hitsGeometry_atCorridorCenter first")
            return
        }

        let blueSkyfraction = Double(blueSkySkyCount) / Double(hitCount)
        // Threshold at 0.70 rather than 0.50: the Option-A glass material is
        // intentionally a strong blue-biased reflector (metallic 0.55, cool-cyan
        // albedo), so around half of the visible blue-flagged pixels ARE the
        // glass fins reflecting the IBL environment — exactly what the material
        // is supposed to do. The original sky-bug failure mode produced ~100%
        // blue-sky hit pixels (all surfaces indistinguishable from sky), which
        // this threshold still catches.
        XCTAssertLessThan(blueSkyfraction, 0.70,
            "\(Int(blueSkyfraction * 100))%% of hit pixels have sky-blue coloring (R/B < 0.5). "
            + "IBL environment is producing outdoor sky radiance for an interior scene. "
            + "Check ibl_proc_env in IBL.metal — for horizontal directions (dir.y ≈ 0) it "
            + "should return a neutral grey wall colour, not the blue-sky gradient.")
    }

    // MARK: - Test 4: Regression — zero farPlane causes all-sky G-buffer

    /// Regression test for Increment 3.5.3: when SceneUniforms.sceneParamsA.w (farPlane) is
    /// 0, the G-buffer ray march loop condition `t < farPlane` is `0 < 0` — false on the
    /// first iteration — so no ray ever steps forward and every pixel returns sky depth (1.0).
    ///
    /// Root cause: `SceneUniforms()` zero-initialises all fields; `makeSceneUniforms(from:)` in
    /// VisualizerEngine+Presets.swift only sets camera + light + fog, leaving sceneParamsA.z/.w
    /// at 0. `drawWithRayMarch` only overwrites .x (audioTime) and .y (aspectRatio) each frame.
    ///
    /// Fix: `makeSceneUniforms` now explicitly sets `sceneParamsA = SIMD4(0, 16/9, 0.1, 30)`.
    /// This test confirms that farPlane = 0 produces all-sky and will fail if the
    /// G-buffer shader is changed to handle zero farPlane differently.
    func test_gbuffer_allSkyWhenFarPlaneIsZero() throws {
        let w = 64, h = 64
        pipeline.allocateTextures(width: w, height: h)

        // Apply correct camera/light but force farPlane = 0 (the bug state).
        applyGlassBrutalistCamera(width: w, height: h)
        var broken = pipeline.sceneUniforms
        broken.sceneParamsA.w = 0   // farPlane = 0 → march loop never executes
        pipeline.sceneUniforms = broken

        let gbuf = try XCTUnwrap(gbufferPipeline)
        try runRender(gbuf: gbuf, width: w, height: h)

        let g0    = try XCTUnwrap(pipeline.gbuffer0)
        let depth = readFloat16Pixels(g0, width: w, height: h, channelsPerPixel: 2)

        var skyCount = 0
        for i in stride(from: 0, to: w * h * 2, by: 2) where depth[i] >= 0.99 { skyCount += 1 }
        let skyFraction = Double(skyCount) / Double(w * h)

        XCTAssertEqual(skyFraction, 1.0, accuracy: 0.01,
            "farPlane=0 must cause 100%% sky pixels (\(Int(skyFraction * 100))%% sky). "
            + "If this fails, the march loop no longer exits immediately at farPlane=0. "
            + "See VisualizerEngine+Presets.swift makeSceneUniforms for the fix.")
    }
}

// MARK: - Private Helpers

private extension GlassBrutalistTests {

    // MARK: Camera (matches GlassBrutalist.json scene_camera)

    /// Apply scene uniforms matching the current GlassBrutalist.json:
    ///   position (0.8, 1.8, -1.0) → target (-0.3, 1.6, 12.0), fov 65° → 1.1345 rad.
    ///   light at (0, 4.5, 2), intensity 3.0, fog 0.015, ambient 0.08.
    ///
    /// Cross product convention (matches PresetDescriptor.makeSceneUniforms):
    ///   right = normalize(cross(worldUp, fwd))  — gives +X for +Z-forward camera
    ///   up    = cross(fwd, right)                — gives +Y for a level camera
    func applyGlassBrutalistCamera(width: Int, height: Int) {
        let pos    = SIMD3<Float>(0.0, 1.8, 0.5)
        let target = SIMD3<Float>(0.0, 1.5, 18.0)
        let fov    = Float(65.0 * .pi / 180.0)   // degrees → radians, once

        let fwd     = normalize(target - pos)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right   = normalize(cross(worldUp, fwd))   // +X for +Z-forward camera
        let up      = cross(fwd, right)                // +Y for level camera

        var s = SceneUniforms()
        s.cameraOriginAndFov        = SIMD4(pos.x, pos.y, pos.z, fov)
        s.cameraForward             = SIMD4(fwd.x,   fwd.y,   fwd.z,   0)
        s.cameraRight               = SIMD4(right.x, right.y, right.z, 0)
        s.cameraUp                  = SIMD4(up.x,    up.y,    up.z,    0)
        s.lightPositionAndIntensity = SIMD4(0, 4.5, 2, 3.0)
        s.lightColor                = SIMD4(1, 0.95, 0.9, 0)
        s.sceneParamsA              = SIMD4(0, Float(width) / Float(height), 0.1, 30)
        s.sceneParamsB              = SIMD4(0, 1.0 / 0.015, 0.08, 0)   // fogFar ≈ 66.7
        pipeline.sceneUniforms = s
    }

    // MARK: Shader loading via PresetLoader

    /// Obtain the G-buffer pipeline state for GlassBrutalist by creating a PresetLoader
    /// and extracting `LoadedPreset.rayMarchPipelineState`.
    ///
    /// This reuses the exact same compilation path as the app at runtime:
    ///   PresetLoader → Bundle.module (Presets bundle) → compileRayMarchShader → G-buffer pipeline.
    /// No manual file loading, no CWD dependency — works identically under `swift test` and Xcode.
    func makeGlassBrutalistGBufferPipeline() throws -> MTLRenderPipelineState? {
        let loader = PresetLoader(device: context.device, pixelFormat: context.pixelFormat)

        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Glass Brutalist" }) else {
            XCTFail("Glass Brutalist preset not found in PresetLoader. "
                + "Check that GlassBrutalist.metal and GlassBrutalist.json exist "
                + "in Sources/Presets/Shaders/ and that the JSON name field is 'Glass Brutalist'.")
            return nil
        }

        guard let gbufferState = preset.rayMarchPipelineState else {
            XCTFail("Glass Brutalist LoadedPreset.rayMarchPipelineState is nil — "
                + "the shader likely failed to compile. Check logs for MSL errors.")
            return nil
        }

        return gbufferState
    }

    // MARK: Render pass

    func runRender(
        gbuf: MTLRenderPipelineState,
        width: Int, height: Int,
        outputTexture: MTLTexture? = nil
    ) throws {
        let outTex = try outputTexture ?? makeOutputTexture(width: width, height: height)

        var features = FeatureVector.zero
        features.aspectRatio = Float(width) / Float(height)

        let fftBuf  = try makeZeroBuffer(count: 512)
        let waveBuf = try makeZeroBuffer(count: 2048)
        let stems   = StemFeatures.zero

        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            throw GlassBrutalistTestError.commandBufferFailed
        }

        pipeline.render(
            gbufferPipelineState: gbuf,
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

        if let gpuError = commandBuffer.error {
            throw GlassBrutalistTestError.gpuError(gpuError)
        }
    }

    // MARK: Buffer / texture helpers (mirrors RayMarchPipelineTests)

    func makeZeroBuffer(count: Int) throws -> MTLBuffer {
        guard let buf = context.device.makeBuffer(
            length: count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else { throw GlassBrutalistTestError.allocationFailed }
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

    /// Read a Float16-encoded texture back to `[Float]`.  Supports `.rg16Float` (2 channels)
    /// and `.rgba16Float` (4 channels) — pass the channel count explicitly.
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
}

// MARK: - Errors

private enum GlassBrutalistTestError: Error {
    case shaderFileNotFound(String)
    case functionNotFound
    case commandBufferFailed
    case gpuError(Error)
    case allocationFailed
}
