// MatIDDispatchTests — focused unit tests for the matID dispatch in
// `raymarch_lighting_fragment` (LM.1.2 / D-LM-matid).
//
// The matID == 1 emission-dominated path lands in LM.1 and is otherwise
// exercised only through `PresetRegressionTests`'s 64×64 dHash, which
// can't validate the actual lit RGB expression. These tests build a
// synthetic G-buffer (depth + matID + normal/AO + albedo/material)
// directly via `MTLTexture.replace(...)`, run `runLightingPass(...)`
// in isolation, read back the litTexture central pixel, and assert
// the dispatch took the expected branch.
//
// Three branches under test:
//   1. matID == 0: standard Cook-Torrance + IBL ambient fallback.
//      Asserted as "non-zero AND distinct from the matID == 1 output"
//      — the BRDF math depends on view/light geometry that's painful
//      to reproduce in test, so we only validate the dispatch took a
//      different path, not the exact RGB.
//   2. matID == 1, depth < 1.0: emission-dominated.
//      Asserted as albedo × kLumenEmissionGain + irradiance ×
//      kLumenIBLFloor × ao. With `iblManager: nil` the IBL textures
//      return zero (documented unbound behaviour), so the expected
//      value is exactly albedo × 4.0.
//   3. matID == 1, depth = 1.0: sky early-return.
//      Asserted as the procedural sky output (NOT albedo × 4), which
//      regression-locks the documented "Sky path returns before this"
//      invariant inside the matID dispatch.
//
// `runLightingPass` is internal in the Renderer module; reachable here
// via `@testable import Renderer`. If a future visibility narrowing
// breaks this test, surface as a discovery — the fix is to either
// widen visibility (consistent with `runGBufferPass`) or route through
// `pipeline.render(...)` with a no-op G-buffer pipeline.

import Testing
import Metal
import simd
@testable import Renderer
@testable import Shared

// MARK: - Suite

@Suite("MatIDDispatch")
struct MatIDDispatchTests {

    // 32×32 is enough — we only sample the central pixel. Smaller textures
    // make the synthetic-buffer pre-population cheaper without losing
    // coverage of the lighting fragment's central-pixel arithmetic.
    private static let width  = 32
    private static let height = 32

    // Tone-map gate: `kLumenEmissionGain = 4.0` from RayMarch.metal.
    // Duplicated as a Swift constant because the .metal scope isn't
    // visible from Swift; keep the two in sync if either changes.
    private static let kLumenEmissionGain: Float = 4.0

    // MARK: - Test 1 — matID == 0 standard dielectric

    @Test("matID == 0 → standard Cook-Torrance path (non-zero, ≠ matID 1 output)")
    func test_matID0_runsCookTorrancePath() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        pipeline.allocateTextures(width: Self.width, height: Self.height)
        Self.installSyntheticUniforms(into: pipeline)

        // Synthetic G-buffer: solid hit, matID 0, mid-grey albedo,
        // facing the camera, full AO.
        try Self.populateGBuffer(pipeline: pipeline,
                                 depth: 0.5,
                                 matID: 0,
                                 normal: SIMD3<Float>(0, 0, -1),
                                 ao: 1.0,
                                 albedo: SIMD3<Float>(0.5, 0.5, 0.5),
                                 roughness: 0.5,
                                 metallic: 0.0)

        var features = FeatureVector(time: 0.0, deltaTime: 1.0 / 60.0)
        let lit = try Self.runLightingAndReadCentre(pipeline: pipeline,
                                                     context: ctx,
                                                     features: &features)

        // matID == 0 path: Cook-Torrance + IBL fallback. With `iblManager: nil`
        // the IBL ambient floor is `albedo × 0.04 × ao = (0.02, 0.02, 0.02)`
        // — so the lit RGB must clear that floor. Direct lighting + fog tint
        // add on top.
        let minimumAmbient: Float = 0.02 * 0.99   // 1% slack for fp16 round-trip
        #expect(lit.x >= minimumAmbient,
                "matID 0 ambient floor: r=\(lit.x) below \(minimumAmbient)")
        #expect(lit.y >= minimumAmbient,
                "matID 0 ambient floor: g=\(lit.y) below \(minimumAmbient)")
        #expect(lit.z >= minimumAmbient,
                "matID 0 ambient floor: b=\(lit.z) below \(minimumAmbient)")

        // matID 0 must NOT equal albedo × 4.0 (the matID 1 emission path).
        // Distance from (2, 2, 2) of at least 1.0 confirms a different
        // branch was taken.
        let matID1Expected = SIMD3<Float>(0.5, 0.5, 0.5) * Self.kLumenEmissionGain
        let distance = simd_length(lit - matID1Expected)
        #expect(distance > 1.0,
                "matID 0 lit RGB \(lit) too close to matID 1 expected \(matID1Expected) — dispatch may not have branched correctly (distance \(distance))")
    }

    // MARK: - Test 2 — matID == 1 emission-dominated

    @Test("matID == 1 → emission path: lit ≈ albedo × kLumenEmissionGain")
    func test_matID1_emissionPath_albedoTimes4() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        pipeline.allocateTextures(width: Self.width, height: Self.height)
        Self.installSyntheticUniforms(into: pipeline)

        // Synthetic G-buffer: solid hit, matID 1, mid-grey albedo.
        let albedo = SIMD3<Float>(0.5, 0.5, 0.5)
        try Self.populateGBuffer(pipeline: pipeline,
                                 depth: 0.5,
                                 matID: 1,
                                 normal: SIMD3<Float>(0, 0, -1),
                                 ao: 1.0,
                                 albedo: albedo,
                                 roughness: 0.5,
                                 metallic: 0.0)

        var features = FeatureVector(time: 0.0, deltaTime: 1.0 / 60.0)
        let lit = try Self.runLightingAndReadCentre(pipeline: pipeline,
                                                     context: ctx,
                                                     features: &features)

        // With iblManager nil → irradiance = 0 → ambientFloor = 0.
        // Expected: albedo × kLumenEmissionGain = (2.0, 2.0, 2.0).
        // Tolerance 1e-2 covers fp16 round-trip + rgba8Unorm albedo
        // 8-bit quantization (1/255 ≈ 0.004 per channel × 4× gain ≈ 0.016).
        let expected = albedo * Self.kLumenEmissionGain
        let tolerance: Float = 0.02
        #expect(abs(lit.x - expected.x) < tolerance,
                "matID 1 r: \(lit.x) ≠ expected \(expected.x) ± \(tolerance)")
        #expect(abs(lit.y - expected.y) < tolerance,
                "matID 1 g: \(lit.y) ≠ expected \(expected.y) ± \(tolerance)")
        #expect(abs(lit.z - expected.z) < tolerance,
                "matID 1 b: \(lit.z) ≠ expected \(expected.z) ± \(tolerance)")
    }

    // MARK: - Test 3 — matID == 1 sky short-circuit

    @Test("matID == 1 + depth ≥ 0.999 → sky path (NOT emission)")
    func test_matID1_skyShortCircuit() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        pipeline.allocateTextures(width: Self.width, height: Self.height)
        Self.installSyntheticUniforms(into: pipeline)

        // Synthetic G-buffer: depth = 1.0 (sky), matID = 1 (would-be
        // emission if not short-circuited), bright-red albedo so the
        // emission path's result would be unmistakable (4 × red = 4.0).
        let albedo = SIMD3<Float>(1.0, 0.0, 0.0)
        try Self.populateGBuffer(pipeline: pipeline,
                                 depth: 1.0,
                                 matID: 1,
                                 normal: SIMD3<Float>(0, 0, -1),
                                 ao: 1.0,
                                 albedo: albedo,
                                 roughness: 0.5,
                                 metallic: 0.0)

        var features = FeatureVector(time: 0.0, deltaTime: 1.0 / 60.0)
        let lit = try Self.runLightingAndReadCentre(pipeline: pipeline,
                                                     context: ctx,
                                                     features: &features)

        // Sky path: `rm_skyColor(rayDir)` at the central pixel.
        // sceneUniforms cameraForward = (0, 0, 1), so central uv = 0.5
        // produces ndc = (0, 0) → rayDir = (0, 0, 1) → rayDir.y = 0
        // → t = 0.5 → mix(horizon, zenith, 0.5)
        //   = mix((0.85, 0.90, 1.0), (0.10, 0.30, 0.8), 0.5)
        //   = (0.475, 0.6, 0.9).
        // Fog disabled (sceneParamsB.y = 1e6 > 1e5) so the path applies
        // `sky * scene.lightColor.rgb`. With lightColor = (1, 1, 1)
        // the expected sky is (0.475, 0.6, 0.9).
        let expectedSky = SIMD3<Float>(0.475, 0.6, 0.9)
        let tolerance: Float = 0.02

        #expect(abs(lit.x - expectedSky.x) < tolerance,
                "sky r: \(lit.x) ≠ expected \(expectedSky.x) ± \(tolerance)")
        #expect(abs(lit.y - expectedSky.y) < tolerance,
                "sky g: \(lit.y) ≠ expected \(expectedSky.y) ± \(tolerance)")
        #expect(abs(lit.z - expectedSky.z) < tolerance,
                "sky b: \(lit.z) ≠ expected \(expectedSky.z) ± \(tolerance)")

        // Negative assertion: if the sky short-circuit accidentally
        // breaks and the emission path runs instead, lit.x would be
        // 1.0 × 4.0 = 4.0 (red-channel-only). Catch that explicitly.
        #expect(lit.x < 1.0,
                "sky r=\(lit.x) ≥ 1.0 — emission path may have run instead of sky short-circuit")
    }

    // MARK: - Test infrastructure

    /// Install a minimal SceneUniforms suitable for the matID dispatch tests:
    /// camera at (0, 0, -3) looking at origin, fov 60° vertical, aspect 1.0,
    /// near 0.1 / far 8.0, fog DISABLED (fogFar = 1e6), light at (0, 0, 0)
    /// intensity 1.0, lightColor white.
    private static func installSyntheticUniforms(into pipeline: RayMarchPipeline) {
        var su = SceneUniforms()
        su.cameraOriginAndFov = SIMD4<Float>(0, 0, -3, .pi / 3)   // 60° vertical
        su.cameraForward      = SIMD4<Float>(0, 0, 1, 0)
        su.cameraRight        = SIMD4<Float>(1, 0, 0, 0)
        su.cameraUp           = SIMD4<Float>(0, 1, 0, 0)
        su.lightPositionAndIntensity = SIMD4<Float>(0, 0, 0, 1.0)
        su.lightColor         = SIMD4<Float>(1, 1, 1, 0)
        su.sceneParamsA       = SIMD4<Float>(0, 1.0, 0.1, 8.0)    // audioTime / aspect / near / far
        su.sceneParamsB       = SIMD4<Float>(0, 1_000_000, 0, 0) // fog disabled per the no-fog sentinel
        pipeline.sceneUniforms = su
    }

    /// Populate the three G-buffer textures with a per-pixel-uniform
    /// synthetic G-buffer. Writes via `MTLTexture.replace(...)`; the
    /// textures must be `.shared` storage, which `RayMarchPipeline.allocateTextures`
    /// ensures.
    private static func populateGBuffer(
        pipeline: RayMarchPipeline,
        depth: Float,
        matID: Int,
        normal: SIMD3<Float>,
        ao: Float,
        albedo: SIMD3<Float>,
        roughness: Float,
        metallic: Float
    ) throws {
        guard let g0 = pipeline.gbuffer0,
              let g1 = pipeline.gbuffer1,
              let g2 = pipeline.gbuffer2 else {
            Issue.record("G-buffer textures not allocated")
            return
        }

        let pixels = Self.width * Self.height

        // gbuffer0 .rg16Float: (depth, matID) per pixel as Float16 pair.
        var rg16: [UInt16] = .init(repeating: 0, count: pixels * 2)
        let depthH  = Float16(depth).bitPattern
        let matIDH  = Float16(Float(matID)).bitPattern
        for i in 0..<pixels {
            rg16[i * 2 + 0] = depthH
            rg16[i * 2 + 1] = matIDH
        }
        rg16.withUnsafeBytes { buf in
            g0.replace(region: MTLRegionMake2D(0, 0, Self.width, Self.height),
                       mipmapLevel: 0,
                       withBytes: buf.baseAddress!,
                       bytesPerRow: Self.width * 4)
        }

        // gbuffer1 .rgba8Snorm: (normal.xyz [-1,1], ao [0,1]) per pixel.
        // snorm packing: byte = round(x * 127), clamped to [-127, 127].
        var rgba8s: [Int8] = .init(repeating: 0, count: pixels * 4)
        let nx = Self.snormByte(normal.x)
        let ny = Self.snormByte(normal.y)
        let nz = Self.snormByte(normal.z)
        let aoB = Self.snormByte(ao)
        for i in 0..<pixels {
            rgba8s[i * 4 + 0] = nx
            rgba8s[i * 4 + 1] = ny
            rgba8s[i * 4 + 2] = nz
            rgba8s[i * 4 + 3] = aoB
        }
        rgba8s.withUnsafeBytes { buf in
            g1.replace(region: MTLRegionMake2D(0, 0, Self.width, Self.height),
                       mipmapLevel: 0,
                       withBytes: buf.baseAddress!,
                       bytesPerRow: Self.width * 4)
        }

        // gbuffer2 .rgba8Unorm: (albedo.rgb, packed roughness/metallic).
        // Pack matches the preamble's gbuffer fragment exactly.
        var rgba8u: [UInt8] = .init(repeating: 0, count: pixels * 4)
        let r = Self.unormByte(albedo.x)
        let g = Self.unormByte(albedo.y)
        let b = Self.unormByte(albedo.z)
        let rByte = Int(simd_clamp(roughness, 0.0, 1.0) * 15.0 + 0.5)
        let mByte = Int(simd_clamp(metallic,  0.0, 1.0) * 15.0 + 0.5)
        let packed = UInt8((rByte << 4) | mByte)
        for i in 0..<pixels {
            rgba8u[i * 4 + 0] = r
            rgba8u[i * 4 + 1] = g
            rgba8u[i * 4 + 2] = b
            rgba8u[i * 4 + 3] = packed
        }
        rgba8u.withUnsafeBytes { buf in
            g2.replace(region: MTLRegionMake2D(0, 0, Self.width, Self.height),
                       mipmapLevel: 0,
                       withBytes: buf.baseAddress!,
                       bytesPerRow: Self.width * 4)
        }
    }

    /// Run `runLightingPass` and return the central pixel of `litTexture` as RGB.
    private static func runLightingAndReadCentre(
        pipeline: RayMarchPipeline,
        context: MetalContext,
        features: inout FeatureVector
    ) throws -> SIMD3<Float> {
        guard let cmd = context.commandQueue.makeCommandBuffer() else {
            Issue.record("Failed to create command buffer")
            return .zero
        }
        pipeline.runLightingPass(commandBuffer: cmd,
                                 features: &features,
                                 noiseTextures: nil,
                                 iblManager: nil,
                                 presetFragmentBuffer3: nil)
        cmd.commit()
        cmd.waitUntilCompleted()

        guard cmd.status == .completed else {
            Issue.record("Lighting pass command buffer failed: \(cmd.status)")
            return .zero
        }

        guard let lit = pipeline.litTexture else {
            Issue.record("litTexture nil after runLightingPass")
            return .zero
        }

        let pixels = Self.width * Self.height
        var rgba16: [UInt16] = .init(repeating: 0, count: pixels * 4)
        rgba16.withUnsafeMutableBytes { buf in
            lit.getBytes(buf.baseAddress!,
                         bytesPerRow: Self.width * 8,
                         from: MTLRegionMake2D(0, 0, Self.width, Self.height),
                         mipmapLevel: 0)
        }

        let cx = Self.width / 2
        let cy = Self.height / 2
        let idx = (cy * Self.width + cx) * 4
        return SIMD3<Float>(
            Float(Float16(bitPattern: rgba16[idx + 0])),
            Float(Float16(bitPattern: rgba16[idx + 1])),
            Float(Float16(bitPattern: rgba16[idx + 2]))
        )
    }

    private static func snormByte(_ x: Float) -> Int8 {
        let clamped = simd_clamp(x, -1.0, 1.0)
        return Int8(clamping: Int((clamped * 127.0).rounded()))
    }

    private static func unormByte(_ x: Float) -> UInt8 {
        let clamped = simd_clamp(x, 0.0, 1.0)
        return UInt8(clamping: Int((clamped * 255.0).rounded()))
    }
}
