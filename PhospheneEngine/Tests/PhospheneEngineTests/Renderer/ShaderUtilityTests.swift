// ShaderUtilityTests — Tests for the ShaderUtilities.metal function library.
// Verifies that utility functions compile correctly, produce expected outputs,
// and integrate seamlessly with the PresetLoader preamble.

import Testing
import Foundation
import Metal
@testable import Presets
@testable import Shared

// MARK: - Preamble Integration

@Test func test_preambleIncludesShaderUtilities() throws {
    let preamble = PresetLoader.shaderPreamble
    // Verify the preamble contains ShaderUtilities content (not just structs).
    #expect(preamble.contains("sdSphere"), "Preamble should include SDF primitives from ShaderUtilities")
    #expect(preamble.contains("perlin2D"), "Preamble should include noise functions from ShaderUtilities")
    #expect(preamble.contains("cookTorranceBRDF"), "Preamble should include PBR functions from ShaderUtilities")
    #expect(preamble.contains("uvKaleidoscope"), "Preamble should include UV transforms from ShaderUtilities")
    #expect(preamble.contains("toneMapACES"), "Preamble should include tone mapping from ShaderUtilities")
    #expect(preamble.contains("palette"), "Preamble should include cosine palette from ShaderUtilities")
}

@Test func test_preambleIncludesV1UtilityTrees() {
    let preamble = PresetLoader.shaderPreamble
    // V.1 Noise utility tree (snake_case — distinct from legacy camelCase ShaderUtilities names)
    #expect(preamble.contains("perlin2d"), "Preamble should include V.1 Perlin noise (perlin2d)")
    #expect(preamble.contains("perlin3d"), "Preamble should include V.1 Perlin noise (perlin3d)")
    #expect(preamble.contains("simplex3d"), "Preamble should include V.1 simplex noise")
    #expect(preamble.contains("fbm4"), "Preamble should include V.1 fbm4")
    #expect(preamble.contains("fbm8"), "Preamble should include V.1 fbm8")
    #expect(preamble.contains("fbm12"), "Preamble should include V.1 fbm12")
    #expect(preamble.contains("ridged_mf"), "Preamble should include V.1 ridged multifractal")
    #expect(preamble.contains("warped_fbm"), "Preamble should include V.1 domain warp")
    #expect(preamble.contains("curl_noise"), "Preamble should include V.1 curl noise")
    #expect(preamble.contains("ign"), "Preamble should include V.1 IGN blue noise")
    // V.1 PBR utility tree
    #expect(preamble.contains("fresnel_schlick"), "Preamble should include V.1 Fresnel")
    #expect(preamble.contains("ggx_d"), "Preamble should include V.1 GGX NDF")
    #expect(preamble.contains("brdf_ggx"), "Preamble should include V.1 GGX BRDF")
    #expect(preamble.contains("brdf_lambert"), "Preamble should include V.1 Lambert")
    #expect(preamble.contains("brdf_oren_nayar"), "Preamble should include V.1 Oren-Nayar")
    #expect(preamble.contains("decode_normal_map"), "Preamble should include V.1 normal mapping")
    #expect(preamble.contains("combine_normals_udn"), "Preamble should include V.1 detail normals")
    #expect(preamble.contains("triplanar_blend_weights"), "Preamble should include V.1 triplanar")
    #expect(preamble.contains("sss_backlit"), "Preamble should include V.1 SSS")
    #expect(preamble.contains("fiber_marschner_lite"), "Preamble should include V.1 fiber BRDF")
    #expect(preamble.contains("thinfilm_rgb"), "Preamble should include V.1 thin-film")
}

@Test func test_presetCompilation_withUtilityFunctions_succeeds() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw ShaderUtilityTestError.noMetalDevice
    }

    // A test preset that calls at least one function from each utility domain.
    let presetSource = """
    // Define map() for ray marching utilities.
    float map(float3 p) { return sdSphere(p, 1.0); }

    fragment float4 preset_fragment(VertexOut in [[stage_in]],
                                    constant FeatureVector& features [[buffer(0)]],
                                    constant float* fftMagnitudes [[buffer(1)]],
                                    constant float* waveformData [[buffer(2)]]) {
        float2 uv = in.uv;
        float t = features.time;

        // Noise domain
        float n = fbm2D(uv * 4.0 + t, 4);

        // SDF + operations domain
        float3 p = float3(uv * 2.0 - 1.0, 0.0);
        float d = opSmoothUnion(sdSphere(p, 0.5), sdBox(p, float3(0.3)), 0.1);

        // Ray marching domain
        float3 ro = float3(0, 0, -3);
        float3 rd = normalize(float3(uv * 2.0 - 1.0, 1.5));
        float hit = rayMarch(ro, rd, 0.1, 20.0, 64);

        // PBR domain
        float3 N = float3(0, 1, 0);
        float3 V = float3(0, 0, 1);
        float3 L = normalize(float3(1, 1, 1));
        float3 brdf = cookTorranceBRDF(N, V, L, float3(0.8), 0.0, 0.5);

        // UV transform domain
        float2 polar = uvPolar(uv, float2(0.5));

        // Color/atmosphere domain
        float3 col = palette(n + polar.x, float3(0.5), float3(0.5),
                             float3(1.0, 1.0, 1.0), float3(0.0, 0.33, 0.67));
        col = toneMapACES(col * 2.0);

        return float4(col, 1.0);
    }
    """

    let fullSource = PresetLoader.shaderPreamble + "\n\n" + presetSource
    let options = MTLCompileOptions()
    options.fastMathEnabled = true
    options.languageVersion = .version3_1

    let library = try device.makeLibrary(source: fullSource, options: options)
    let fragmentFn = library.makeFunction(name: "preset_fragment")
    #expect(fragmentFn != nil, "Fragment function using all utility domains should compile")
}

// MARK: - GPU Compute Verification Tests

@Test func test_noiseOutput_deterministic_sameInputSameOutput() throws {
    let (device, result) = try runComputeKernel(
        source: """
        kernel void testKernel(device float* output [[buffer(0)]],
                               uint tid [[thread_position_in_grid]]) {
            // Evaluate perlin2D at two known points, twice each.
            float a1 = perlin2D(float2(1.23, 4.56));
            float a2 = perlin2D(float2(1.23, 4.56));
            float b1 = perlin2D(float2(7.89, 0.12));
            float b2 = perlin2D(float2(7.89, 0.12));
            output[0] = a1;
            output[1] = a2;
            output[2] = b1;
            output[3] = b2;
            // Also check output is in [0, 1] range for this hash-based noise.
            output[4] = (a1 >= 0.0 && a1 <= 1.0) ? 1.0 : 0.0;
            output[5] = (b1 >= 0.0 && b1 <= 1.0) ? 1.0 : 0.0;
        }
        """,
        outputCount: 6
    )

    #expect(result[0] == result[1], "perlin2D should be deterministic: same input → same output")
    #expect(result[2] == result[3], "perlin2D should be deterministic for different point")
    #expect(result[0] != result[2], "Different inputs should produce different outputs")
    #expect(result[4] == 1.0, "Noise output should be in [0, 1] range")
    #expect(result[5] == 1.0, "Noise output should be in [0, 1] range")
}

@Test func test_sdfSphere_knownDistance_matchesAnalytic() throws {
    let (device, result) = try runComputeKernel(
        source: """
        kernel void testKernel(device float* output [[buffer(0)]],
                               uint tid [[thread_position_in_grid]]) {
            // Point at (1, 0, 0), sphere radius 0.5 → distance should be 0.5
            output[0] = sdSphere(float3(1.0, 0.0, 0.0), 0.5);
            // Point at origin → distance should be -0.5 (inside)
            output[1] = sdSphere(float3(0.0, 0.0, 0.0), 0.5);
            // Point on surface → distance should be 0.0
            output[2] = sdSphere(float3(0.5, 0.0, 0.0), 0.5);
            // sdBox at (2, 0, 0) with half-extents (1, 1, 1) → distance 1.0
            output[3] = sdBox(float3(2.0, 0.0, 0.0), float3(1.0));
        }
        """,
        outputCount: 4
    )

    #expect(abs(result[0] - 0.5) < 0.001, "sdSphere(1,0,0, r=0.5) should be 0.5, got \(result[0])")
    #expect(abs(result[1] - (-0.5)) < 0.001, "sdSphere(0,0,0, r=0.5) should be -0.5, got \(result[1])")
    #expect(abs(result[2]) < 0.001, "sdSphere on surface should be ~0.0, got \(result[2])")
    #expect(abs(result[3] - 1.0) < 0.001, "sdBox(2,0,0, b=1) should be 1.0, got \(result[3])")
}

@Test func test_rayMarch_sphereScene_hitsAtExpectedDistance() throws {
    let (device, result) = try runComputeKernel(
        source: """
        // Scene: unit sphere at origin.
        float map(float3 p) { return sdSphere(p, 1.0); }

        kernel void testKernel(device float* output [[buffer(0)]],
                               uint tid [[thread_position_in_grid]]) {
            // Ray from (0, 0, -3) toward origin should hit sphere at distance ~2.0
            float t = rayMarch(float3(0.0, 0.0, -3.0), float3(0.0, 0.0, 1.0),
                               0.1, 100.0, 256);
            output[0] = t;
            // Ray pointing away should miss (return -1.0)
            float miss = rayMarch(float3(0.0, 0.0, -3.0), float3(0.0, 0.0, -1.0),
                                  0.1, 100.0, 256);
            output[1] = miss;
        }
        """,
        outputCount: 2
    )

    #expect(abs(result[0] - 2.0) < 0.01,
            "Ray from z=-3 toward unit sphere should hit at ~2.0, got \(result[0])")
    #expect(result[1] < 0.0,
            "Ray pointing away should miss (return -1.0), got \(result[1])")
}

@Test func test_cookTorrance_energyConservation_outputLEInput() throws {
    let (device, result) = try runComputeKernel(
        source: """
        kernel void testKernel(device float* output [[buffer(0)]],
                               uint tid [[thread_position_in_grid]]) {
            float3 N = float3(0, 1, 0);
            float3 V = float3(0, 1, 0);
            float3 L = float3(0, 1, 0);
            float3 albedo = float3(1.0);

            // Dielectric (non-metal), smooth surface — maximum specular case.
            float3 brdf = cookTorranceBRDF(N, V, L, albedo, 0.0, 0.1);
            float luminance = dot(brdf, float3(0.2126, 0.7152, 0.0722));
            output[0] = luminance;

            // Metal, rough surface.
            float3 brdfMetal = cookTorranceBRDF(N, V, L, albedo, 1.0, 0.9);
            float lumMetal = dot(brdfMetal, float3(0.2126, 0.7152, 0.0722));
            output[1] = lumMetal;

            // Input light energy (NdotL = 1.0 for these vectors).
            output[2] = 1.0;
        }
        """,
        outputCount: 3
    )

    #expect(result[0] <= result[2] + 0.01,
            "BRDF output luminance (\(result[0])) should not exceed input energy (\(result[2]))")
    #expect(result[1] <= result[2] + 0.01,
            "Metal BRDF output (\(result[1])) should not exceed input energy (\(result[2]))")
    #expect(result[0] > 0.0, "BRDF should produce non-zero output for aligned N/V/L")
}

@Test func test_uvKaleidoscope_symmetry_nFinsProducesNFoldSymmetry() throws {
    let (device, result) = try runComputeKernel(
        source: """
        kernel void testKernel(device float* output [[buffer(0)]],
                               uint tid [[thread_position_in_grid]]) {
            float2 center = float2(0.5);
            int n = 6;

            // Two points that should map to the same kaleidoscope UV
            // when reflected through the 6-fold symmetry.
            float angle1 = 0.1;
            float angle2 = 0.1 + 2.0 * M_PI_F / 6.0; // One segment apart.
            float r = 0.3;

            float2 p1 = center + r * float2(cos(angle1), sin(angle1));
            float2 p2 = center + r * float2(cos(angle2), sin(angle2));

            float2 k1 = uvKaleidoscope(p1, center, n);
            float2 k2 = uvKaleidoscope(p2, center, n);

            // After folding, both should map to the same UV (within tolerance).
            output[0] = length(k1 - k2);
            // Verify radius is preserved.
            output[1] = length(k1);
            output[2] = r;
        }
        """,
        outputCount: 3
    )

    #expect(result[0] < 0.01,
            "6-fold kaleidoscope: points one segment apart should map to same UV, diff = \(result[0])")
    #expect(abs(result[1] - result[2]) < 0.01,
            "Kaleidoscope should preserve radius: got \(result[1]), expected \(result[2])")
}

@Test func test_palette_sweepT_producesSmoothGradient() throws {
    let (device, result) = try runComputeKernel(
        source: """
        kernel void testKernel(device float* output [[buffer(0)]],
                               uint tid [[thread_position_in_grid]]) {
            // Sweep t from 0 to 1 in 10 steps, measure max jump between consecutive colors.
            float maxJump = 0.0;
            float3 prev = palette(0.0, float3(0.5), float3(0.5),
                                  float3(1.0, 1.0, 1.0), float3(0.0, 0.33, 0.67));
            for (int i = 1; i <= 10; i++) {
                float t = float(i) / 10.0;
                float3 cur = palette(t, float3(0.5), float3(0.5),
                                     float3(1.0, 1.0, 1.0), float3(0.0, 0.33, 0.67));
                maxJump = max(maxJump, length(cur - prev));
                prev = cur;
            }
            output[0] = maxJump;
            // Verify output is in valid color range.
            float3 c = palette(0.5, float3(0.5), float3(0.5),
                               float3(1.0, 1.0, 1.0), float3(0.0, 0.33, 0.67));
            output[1] = (c.x >= 0.0 && c.x <= 1.0 && c.y >= 0.0 && c.y <= 1.0 &&
                         c.z >= 0.0 && c.z <= 1.0) ? 1.0 : 0.0;
        }
        """,
        outputCount: 2
    )

    #expect(result[0] < 0.5,
            "Cosine palette should produce smooth gradients, max jump = \(result[0])")
    #expect(result[1] == 1.0,
            "Palette output should be in [0, 1] range for standard parameters")
}

@Test func test_acesToneMap_hdrInput_outputInSDRRange() throws {
    let (device, result) = try runComputeKernel(
        source: """
        kernel void testKernel(device float* output [[buffer(0)]],
                               uint tid [[thread_position_in_grid]]) {
            // HDR input values > 1.0
            float3 hdr = float3(5.0, 10.0, 2.0);
            float3 sdr = toneMapACES(hdr);
            output[0] = sdr.x;
            output[1] = sdr.y;
            output[2] = sdr.z;
            // All outputs should be in (0, 1].
            output[3] = (sdr.x > 0.0 && sdr.x <= 1.0 &&
                         sdr.y > 0.0 && sdr.y <= 1.0 &&
                         sdr.z > 0.0 && sdr.z <= 1.0) ? 1.0 : 0.0;
            // Black in should give black out.
            float3 black = toneMapACES(float3(0.0));
            output[4] = length(black);
        }
        """,
        outputCount: 5
    )

    #expect(result[3] == 1.0,
            "ACES tone map of HDR input should produce SDR output in (0, 1], got (\(result[0]), \(result[1]), \(result[2]))")
    #expect(result[4] < 0.01,
            "ACES tone map of black should be ~black, got length \(result[4])")
}

@Test func test_fog_zeroDistance_noEffect() throws {
    let (device, result) = try runComputeKernel(
        source: """
        kernel void testKernel(device float* output [[buffer(0)]],
                               uint tid [[thread_position_in_grid]]) {
            float3 original = float3(1.0, 0.5, 0.2);
            float3 fogColor = float3(0.7, 0.7, 0.8);

            // Zero distance → no fog effect.
            float3 noFog = fog(original, fogColor, 0.0, 1.0);
            output[0] = length(noFog - original);

            // Large distance → fully fogged.
            float3 fullFog = fog(original, fogColor, 100.0, 1.0);
            output[1] = length(fullFog - fogColor);
        }
        """,
        outputCount: 2
    )

    #expect(result[0] < 0.001,
            "Fog at zero distance should have no effect, diff = \(result[0])")
    #expect(result[1] < 0.01,
            "Fog at large distance should converge to fog color, diff = \(result[1])")
}

// MARK: - Performance

@Test func test_fullScreenNoise_1080p_under2ms() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw ShaderUtilityTestError.noMetalDevice
    }

    let source = PresetLoader.shaderPreamble + """

    kernel void noiseKernel(device float* output [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
        float2 uv = float2(gid) / float2(1920.0, 1080.0);
        float n = fbm3D(float3(uv * 4.0, 0.5), 5);
        output[gid.y * 1920 + gid.x] = n;
    }
    """

    let options = MTLCompileOptions()
    options.fastMathEnabled = true
    options.languageVersion = .version3_1

    let library = try device.makeLibrary(source: source, options: options)
    guard let function = library.makeFunction(name: "noiseKernel"),
          let pipeline = try? device.makeComputePipelineState(function: function),
          let queue = device.makeCommandQueue() else {
        throw ShaderUtilityTestError.metalSetupFailed
    }

    let pixelCount = 1920 * 1080
    guard let buffer = device.makeBuffer(
        length: pixelCount * MemoryLayout<Float>.stride,
        options: .storageModeShared
    ) else {
        throw ShaderUtilityTestError.metalSetupFailed
    }

    // Warm up.
    for _ in 0..<3 {
        guard let cmdBuf = queue.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else { continue }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let gridSize = MTLSize(width: 1920, height: 1080, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
    }

    // Measure.
    guard let cmdBuf = queue.makeCommandBuffer(),
          let encoder = cmdBuf.makeComputeCommandEncoder() else {
        throw ShaderUtilityTestError.metalSetupFailed
    }
    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(buffer, offset: 0, index: 0)
    let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
    let gridSize = MTLSize(width: 1920, height: 1080, depth: 1)
    encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
    encoder.endEncoding()

    let start = CFAbsoluteTimeGetCurrent()
    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()
    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

    #expect(elapsed < 2.0,
            "Full-screen fbm3D at 1080p should complete in <2ms, took \(String(format: "%.2f", elapsed))ms")
}

// MARK: - Helpers

enum ShaderUtilityTestError: Error {
    case noMetalDevice
    case metalSetupFailed
    case compilationFailed
}

/// Compile and run a compute kernel that writes Float results to buffer(0).
/// The kernel source should NOT include metal_stdlib or preamble — those are prepended automatically.
private func runComputeKernel(source: String, outputCount: Int) throws -> (MTLDevice, [Float]) {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw ShaderUtilityTestError.noMetalDevice
    }

    let fullSource = PresetLoader.shaderPreamble + "\n\n" + source

    let options = MTLCompileOptions()
    options.fastMathEnabled = true
    options.languageVersion = .version3_1

    let library: MTLLibrary
    do {
        library = try device.makeLibrary(source: fullSource, options: options)
    } catch {
        throw ShaderUtilityTestError.compilationFailed
    }

    guard let function = library.makeFunction(name: "testKernel"),
          let pipeline = try? device.makeComputePipelineState(function: function),
          let queue = device.makeCommandQueue(),
          let buffer = device.makeBuffer(
              length: outputCount * MemoryLayout<Float>.stride,
              options: .storageModeShared
          ),
          let cmdBuf = queue.makeCommandBuffer(),
          let encoder = cmdBuf.makeComputeCommandEncoder() else {
        throw ShaderUtilityTestError.metalSetupFailed
    }

    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(buffer, offset: 0, index: 0)
    encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
    encoder.endEncoding()
    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    let ptr = buffer.contents().bindMemory(to: Float.self, capacity: outputCount)
    var result: [Float] = []
    for i in 0..<outputCount {
        result.append(ptr[i])
    }
    return (device, result)
}
