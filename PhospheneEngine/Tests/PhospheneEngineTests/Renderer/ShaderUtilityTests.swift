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
    #expect(preamble.contains("sd_sphere"), "Preamble should include V.1+V.2 SDF primitives")
    // RECON.16 retired the unreachable 38 of ShaderUtilities' 42 functions; these
    // four remain because they still have consumers (VolumetricLithograph, Nimbus).
    #expect(preamble.contains("hash21"), "Preamble should include legacy hash21 (perlin3D dependency)")
    #expect(preamble.contains("perlin3D"), "Preamble should include legacy value noise (fbm3D dependency)")
    #expect(preamble.contains("fbm3D"), "Preamble should include legacy fbm3D (VolumetricLithograph)")
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

    // A test preset that calls at least one function from each utility domain
    // that survives: legacy noise/tonemap keepers + the V.1–V.3 canonical tree.
    let presetSource = """
    fragment float4 preset_fragment(VertexOut in [[stage_in]],
                                    constant FeatureVector& features [[buffer(0)]],
                                    constant float* fftMagnitudes [[buffer(1)]],
                                    constant float* waveformData [[buffer(2)]]) {
        float2 uv = in.uv;
        float t = features.time;

        // Noise domain (legacy keeper — VolumetricLithograph's algorithm)
        float n = fbm3D(float3(uv * 4.0 + t, 0.5), 4);

        // SDF + operations domain
        float3 p = float3(uv * 2.0 - 1.0, 0.0);
        float d = op_smooth_union(sd_sphere(p, 0.5), sd_box(p, float3(0.3)), 0.1);

        // PBR domain (V.1 canonical)
        float3 N = float3(0, 1, 0);
        float3 V = float3(0, 0, 1);
        float3 L = normalize(float3(1, 1, 1));
        float3 brdf = brdf_cook_torrance(N, V, L, float3(0.8), 0.5, 0.0, float3(0.04));

        // Color domain
        float3 col = palette(n + d + brdf.x, float3(0.5), float3(0.5),
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
            // Evaluate perlin3D at two known points, twice each.
            float a1 = perlin3D(float3(1.23, 4.56, 0.5));
            float a2 = perlin3D(float3(1.23, 4.56, 0.5));
            float b1 = perlin3D(float3(7.89, 0.12, 0.5));
            float b2 = perlin3D(float3(7.89, 0.12, 0.5));
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

    #expect(result[0] == result[1], "perlin3D should be deterministic: same input → same output")
    #expect(result[2] == result[3], "perlin3D should be deterministic for different point")
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
            output[0] = sd_sphere(float3(1.0, 0.0, 0.0), 0.5);
            // Point at origin → distance should be -0.5 (inside)
            output[1] = sd_sphere(float3(0.0, 0.0, 0.0), 0.5);
            // Point on surface → distance should be 0.0
            output[2] = sd_sphere(float3(0.5, 0.0, 0.0), 0.5);
            // sd_box at (2, 0, 0) with half-extents (1, 1, 1) → distance 1.0
            output[3] = sd_box(float3(2.0, 0.0, 0.0), float3(1.0));
        }
        """,
        outputCount: 4
    )

    #expect(abs(result[0] - 0.5) < 0.001, "sd_sphere(1,0,0, r=0.5) should be 0.5, got \(result[0])")
    #expect(abs(result[1] - (-0.5)) < 0.001, "sd_sphere(0,0,0, r=0.5) should be -0.5, got \(result[1])")

    #expect(abs(result[2]) < 0.001, "sd_sphere on surface should be ~0.0, got \(result[2])")
    #expect(abs(result[3] - 1.0) < 0.001, "sd_box(2,0,0, b=1) should be 1.0, got \(result[3])")
}

/// Properties of the V.1 canonical Cook-Torrance BRDF.
///
/// RECON.16 note: this replaces an `output <= input energy` assertion written
/// against the retired legacy `cookTorranceBRDF`. That premise does not transfer
/// and was not weakened to make it pass — a BRDF evaluated at the mirror
/// direction is a *density*, so at low roughness the specular lobe legitimately
/// exceeds albedo (measured ~10.3 at roughness 0.1). Energy conservation is a
/// property of the integral over the hemisphere, not of one sample. What IS true
/// pointwise, and what a broken BRDF would violate, is asserted below.
@Test func test_cookTorrance_physicalProperties() throws {
    let (device, result) = try runComputeKernel(
        source: """
        kernel void testKernel(device float* output [[buffer(0)]],
                               uint tid [[thread_position_in_grid]]) {
            float3 N = float3(0, 1, 0);
            float3 V = float3(0, 1, 0);
            float3 albedo = float3(1.0);

            // Aligned light: positive, finite response.
            float3 lit = brdf_cook_torrance(N, V, float3(0, 1, 0), albedo, 0.5, 0.0, float3(0.04));
            output[0] = dot(lit, float3(0.2126, 0.7152, 0.0722));

            // Light BELOW the surface (NdotL <= 0) must contribute nothing.
            float3 back = brdf_cook_torrance(N, V, float3(0, -1, 0), albedo, 0.5, 0.0, float3(0.04));
            output[1] = dot(back, float3(0.2126, 0.7152, 0.0722));

            // Rougher surfaces spread the lobe, so the mirror-direction peak falls.
            float3 smoothS = brdf_cook_torrance(N, V, float3(0, 1, 0), albedo, 0.15, 0.0, float3(0.04));
            float3 roughS  = brdf_cook_torrance(N, V, float3(0, 1, 0), albedo, 0.85, 0.0, float3(0.04));
            output[2] = dot(smoothS, float3(0.2126, 0.7152, 0.0722));
            output[3] = dot(roughS,  float3(0.2126, 0.7152, 0.0722));
        }
        """,
        outputCount: 4
    )

    #expect(result[0] > 0.0, "BRDF should produce positive output for aligned N/V/L")
    #expect(result[0].isFinite, "BRDF output must be finite, got \(result[0])")
    #expect(abs(result[1]) < 1e-6,
            "Light below the surface must contribute nothing, got \(result[1])")
    #expect(result[2] > result[3],
            "Smooth surface peak (\(result[2])) should exceed rough surface peak (\(result[3]))")
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

    // Measure — MINIMUM OF 8 WARM SAMPLES, budget UNCHANGED at 5 ms (FTR.16).
    //
    // This was a SINGLE-sample GPU-timestamp assertion, the most contention-fragile shape there
    // is, and it flaked 1 in 5 at 5.4 ms against the 5.0 ms budget on a machine that had been
    // rendering 1080p sequences all session. `PostProcessChainTests.test_fullChain_under2ms_at1080p`
    // is already in the KNOWN_ISSUES contention table for the same reason.
    //
    // The remedy is the one CLEAN.7.10 proved on `RayIntersectorTests.test_rayTrace_1000Rays_under2ms`
    // and it is deliberately NOT a wider budget: contention can only ADD latency to a GPU submit,
    // so the MINIMUM across samples is the clean estimate of true cost and is robust to a few
    // starved ones. A real regression still fails this — it would raise the floor, not just the
    // outliers.
    var bestGpuMs = Double.greatestFiniteMagnitude
    for _ in 0..<8 {
        guard let cmdBuf = queue.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else {
            throw ShaderUtilityTestError.metalSetupFailed
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 1920, height: 1080, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        bestGpuMs = Swift.min(bestGpuMs, (cmdBuf.gpuEndTime - cmdBuf.gpuStartTime) * 1000.0)
    }

    #expect(bestGpuMs < 5.0, """
        Full-screen fbm3D at 1080p should complete in <5ms GPU time; the fastest of 8 warm \
        samples took \(String(format: "%.2f", bestGpuMs))ms. This is a MINIMUM, so contention \
        cannot explain it — treat it as a real cost regression.
        """)
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
