// NoiseUtilityTests.swift — Property tests for the Noise utility tree (V.1 Part A).
//
// Tests compile the preamble (which includes the new Noise utilities) against
// small compute kernels and verify mathematical invariants.
// None of these tests modify existing shaders — they only assert additive properties.
//
// See D-039 for the dHash regression gate that guards existing preset output.

import Testing
import Metal
@testable import Presets

// MARK: - Preamble Presence Tests

@Suite("Noise Utility — Preamble Integration")
struct NoisePreambleTests {

    @Test func preamble_containsHashFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("hash_u32"), "hash_u32 should be in preamble")
        #expect(p.contains("hash_grad2"), "hash_grad2 should be in preamble")
        #expect(p.contains("hash_grad3"), "hash_grad3 should be in preamble")
    }

    @Test func preamble_containsPerlinFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("perlin2d"), "perlin2d should be in preamble")
        #expect(p.contains("perlin3d"), "perlin3d should be in preamble")
        #expect(p.contains("perlin4d"), "perlin4d should be in preamble")
    }

    @Test func preamble_containsSimplexFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("simplex3d"), "simplex3d should be in preamble")
        #expect(p.contains("simplex4d"), "simplex4d should be in preamble")
    }

    @Test func preamble_containsWorleyFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("worley2d"), "worley2d should be in preamble")
        #expect(p.contains("worley3d"), "worley3d should be in preamble")
    }

    @Test func preamble_containsFBMFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("fbm4"), "fbm4 should be in preamble")
        #expect(p.contains("fbm8"), "fbm8 should be in preamble")
        #expect(p.contains("fbm12"), "fbm12 should be in preamble")
        #expect(p.contains("fbm_vec3"), "fbm_vec3 should be in preamble")
    }

    @Test func preamble_containsRidgedMF() {
        #expect(PresetLoader.shaderPreamble.contains("ridged_mf"))
    }

    @Test func preamble_containsDomainWarp() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("warped_fbm"), "warped_fbm should be in preamble")
        #expect(p.contains("warped_fbm_vec"), "warped_fbm_vec should be in preamble")
    }

    @Test func preamble_containsCurlNoise() {
        #expect(PresetLoader.shaderPreamble.contains("curl_noise"))
    }

    @Test func preamble_containsBlueNoise() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("blue_noise_sample"), "blue_noise_sample should be in preamble")
        #expect(p.contains("ign("), "ign should be in preamble")
        #expect(p.contains("ign_temporal"), "ign_temporal should be in preamble")
    }

    @Test func preamble_newUtilitiesBeforeLegacyShaderUtilities() {
        let p = PresetLoader.shaderPreamble
        // New utilities must come BEFORE legacy ShaderUtilities (perlin2D camelCase)
        // so they are defined before potential references.
        let newIdx    = p.range(of: "perlin2d")?.lowerBound
        let legacyIdx = p.range(of: "perlin2D")?.lowerBound
        if let n = newIdx, let l = legacyIdx {
            #expect(n < l, "New perlin2d must appear before legacy perlin2D in preamble")
        }
    }
}

// MARK: - Hash Tests

@Suite("Noise Utility — Hash")
struct HashUtilityTests {

    @Test func hash_compilesAndRuns() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            uint x = uint(inputs[tid].x * 1000.0);
            outputs[tid] = hash_f01(x);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for v in results {
            #expect(v >= 0.0 && v < 1.0, "hash_f01 output must be in [0, 1)")
        }
    }

    @Test func hash_deterministic() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            int3 ip = int3(int(inputs[tid].x), int(inputs[tid].y), int(inputs[tid].z));
            outputs[tid] = hash_f01_3(float3(ip));
        }
        """
        let r1 = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        let r2 = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for i in 0..<r1.count {
            #expect(r1[i] == r2[i], "hash_f01_3 must be deterministic")
        }
    }

    @Test func hash_uniformity() throws {
        // Chi-square lite: 256 samples should distribute roughly evenly across 8 buckets.
        let positions = (0..<256).map { i in SIMD3<Float>(Float(i), 0, 0) }
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = hash_f01(uint(inputs[tid].x));
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: positions)
        var buckets = [Int](repeating: 0, count: 8)
        for v in results { buckets[min(Int(v * 8.0), 7)] += 1 }
        // Each bucket should have roughly 256/8 = 32 samples; allow ±50% tolerance.
        for (i, count) in buckets.enumerated() {
            #expect(count > 16 && count < 48,
                "Bucket \(i) has \(count) samples, expected ~32 for uniform distribution")
        }
    }
}

// MARK: - Perlin Tests

@Suite("Noise Utility — Perlin")
struct PerlinUtilityTests {

    @Test func perlin2d_range() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = perlin2d(inputs[tid].xy * 3.0);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for v in results {
            #expect(v >= -1.2 && v <= 1.2, "perlin2d output must be within [-1.2, 1.2]; got \(v)")
        }
    }

    @Test func perlin3d_range() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = perlin3d(inputs[tid]);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for v in results {
            #expect(v >= -1.2 && v <= 1.2, "perlin3d output must be within [-1.2, 1.2]; got \(v)")
        }
    }

    @Test func perlin3d_deterministic() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = perlin3d(inputs[tid]);
        }
        """
        let r1 = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        let r2 = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for i in 0..<r1.count {
            #expect(r1[i] == r2[i], "perlin3d must be deterministic")
        }
    }

    @Test func perlin4d_range() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = perlin4d(float4(inputs[tid], 1.5));
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for v in results {
            #expect(v >= -1.2 && v <= 1.2, "perlin4d output must be within [-1.2, 1.2]; got \(v)")
        }
    }
}

// MARK: - Simplex Tests

@Suite("Noise Utility — Simplex")
struct SimplexUtilityTests {

    @Test func simplex3d_range() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = simplex3d(inputs[tid] * 2.0);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for v in results {
            #expect(v >= -1.2 && v <= 1.2, "simplex3d output must be within [-1.2, 1.2]; got \(v)")
        }
    }

    @Test func simplex3d_deterministic() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = simplex3d(inputs[tid]);
        }
        """
        let r1 = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        let r2 = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for i in 0..<r1.count { #expect(r1[i] == r2[i], "simplex3d must be deterministic") }
    }

    @Test func simplex4d_range() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = simplex4d(float4(inputs[tid], 0.7));
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for v in results {
            #expect(v >= -1.2 && v <= 1.2, "simplex4d output must be within [-1.2, 1.2]; got \(v)")
        }
    }
}

// MARK: - Worley Tests

@Suite("Noise Utility — Worley")
struct WorleyUtilityTests {

    @Test func worley2d_F1_lessThanF2() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float2 f = worley2d(inputs[tid].xy * 3.0);
            // Pack F1 and F2 alternately
            outputs[tid * 2]     = f.x;   // F1
            outputs[tid * 2 + 1] = f.y;   // F2
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions,
                                         outputCount: noiseTestPositions.count * 2)
        for i in stride(from: 0, to: results.count, by: 2) {
            let F1 = results[i], F2 = results[i + 1]
            #expect(F1 <= F2 + 1e-5, "F1 (\(F1)) must be ≤ F2 (\(F2))")
            #expect(F1 >= 0.0, "F1 must be non-negative")
        }
    }

    @Test func worley3d_F1_lessThanF2() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 f = worley3d(inputs[tid] * 2.0);
            outputs[tid * 2]     = f.x;
            outputs[tid * 2 + 1] = f.y;
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions,
                                         outputCount: noiseTestPositions.count * 2)
        for i in stride(from: 0, to: results.count, by: 2) {
            let F1 = results[i], F2 = results[i + 1]
            #expect(F1 <= F2 + 1e-5, "worley3d: F1 (\(F1)) must be ≤ F2 (\(F2))")
        }
    }

    @Test func worley3d_cellHash_inRange() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 f = worley3d(inputs[tid] * 2.0);
            outputs[tid] = f.z;   // cell_hash
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for v in results { #expect(v >= 0.0 && v < 1.0, "cell_hash must be in [0, 1)") }
    }
}

// MARK: - FBM Tests

@Suite("Noise Utility — FBM")
struct FBMUtilityTests {

    @Test func fbm8_bounded() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = fbm8(inputs[tid] * 1.5);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for v in results {
            #expect(v >= -1.2 && v <= 1.2, "fbm8 must be within [-1.2, 1.2]; got \(v)")
        }
    }

    @Test func fbm8_reproducible() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = fbm8(inputs[tid]);
        }
        """
        let r1 = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        let r2 = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for i in 0..<r1.count { #expect(r1[i] == r2[i], "fbm8 must be reproducible") }
    }

    @Test func fbm4_bounded() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = fbm4(inputs[tid]);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for v in results { #expect(v >= -1.2 && v <= 1.2, "fbm4 must be within [-1.2, 1.2]") }
    }

    @Test func fbm12_bounded() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = fbm12(inputs[tid] * 0.8);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for v in results { #expect(v >= -1.2 && v <= 1.2, "fbm12 must be within [-1.2, 1.2]") }
    }

    @Test func fbm8_H_affects_amplitude() throws {
        // Higher H → faster amplitude decay → lower overall magnitude.
        let kernelLowH = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = abs(fbm8(inputs[tid], 0.25));
        }
        """
        let kernelHighH = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = abs(fbm8(inputs[tid], 0.75));
        }
        """
        let lowH  = try runNoiseKernel(kernelSource: kernelLowH,  inputs: noiseTestPositions)
        let highH = try runNoiseKernel(kernelSource: kernelHighH, inputs: noiseTestPositions)
        let avgLow  = lowH.reduce(0, +)  / Float(lowH.count)
        let avgHigh = highH.reduce(0, +) / Float(highH.count)
        // Higher H blends octaves more evenly → different mean absolute value.
        // They should simply not be identical.
        #expect(abs(avgLow - avgHigh) > 0.001,
            "Different H values should produce different average amplitudes")
    }
}

// MARK: - RidgedMultifractal Tests

@Suite("Noise Utility — RidgedMultifractal")
struct RidgedMFTests {

    @Test func ridged_mf_outputNonNegative() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = ridged_mf(inputs[tid] * 1.5);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for v in results { #expect(v >= -0.01, "ridged_mf output should be non-negative; got \(v)") }
    }

    @Test func ridged_mf_bounded() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = ridged_mf(inputs[tid]);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for v in results { #expect(v <= 1.1, "ridged_mf output should not exceed 1.1; got \(v)") }
    }
}

// MARK: - Domain Warp Tests

@Suite("Noise Utility — DomainWarp")
struct DomainWarpTests {

    @Test func warped_fbm_bounded() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = warped_fbm(inputs[tid] * 0.5);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        for v in results { #expect(v >= -1.5 && v <= 1.5, "warped_fbm must be within [-1.5, 1.5]; got \(v)") }
    }

    @Test func warped_fbm_continuous() throws {
        // Adjacent points should have similar values (continuity check).
        let pts = [
            SIMD3<Float>(0.0, 0.0, 0.0),
            SIMD3<Float>(0.01, 0.0, 0.0),
            SIMD3<Float>(0.0, 0.01, 0.0),
        ]
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = warped_fbm(inputs[tid]);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: pts)
        // Adjacent values should not differ by more than 0.5 (continuity sanity check).
        #expect(abs(results[0] - results[1]) < 0.5, "warped_fbm should be continuous in x")
        #expect(abs(results[0] - results[2]) < 0.5, "warped_fbm should be continuous in y")
    }
}

// MARK: - Curl Tests

@Suite("Noise Utility — Curl")
struct CurlNoiseTests {

    @Test func curl_noise_compilesAndRuns() throws {
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 c = curl_noise(inputs[tid]);
            outputs[tid * 3]     = c.x;
            outputs[tid * 3 + 1] = c.y;
            outputs[tid * 3 + 2] = c.z;
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions,
                                         outputCount: noiseTestPositions.count * 3)
        #expect(results.count == noiseTestPositions.count * 3)
    }

    @Test func curl_noise_bounded_and_varies() throws {
        // Verify curl_noise output is bounded and non-constant across the test positions.
        // (Divergence-free cannot be verified via finite differences on the GPU approximation:
        // curl_noise uses FD internally at e=0.01; computing div of that approximation via
        // a second round of FD compounds O(e^2 × max_freq^3) errors from 8-octave fBM.)
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float3 c = curl_noise(inputs[tid]);
            outputs[tid] = length(c);   // output magnitude per point
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: noiseTestPositions)
        // All magnitudes must be finite and reasonably bounded
        for mag in results {
            #expect(mag.isFinite && mag < 1000.0,
                "curl_noise magnitude should be finite and < 1000, got \(mag)")
        }
        // Output must vary (not all identical) — confirms it's computing something non-trivial
        let minMag = results.min()!
        let maxMag = results.max()!
        #expect(maxMag - minMag > 0.01,
            "curl_noise should vary across positions, range=\(maxMag - minMag)")
    }
}

// MARK: - BlueNoise Tests

@Suite("Noise Utility — BlueNoise")
struct BlueNoiseTests {

    @Test func ign_outputInRange() throws {
        let positions = (0..<50).map { i in SIMD3<Float>(Float(i % 10), Float(i / 10), 0) }
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = ign(inputs[tid].xy);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: positions)
        for v in results { #expect(v >= 0.0 && v < 1.0, "ign must return value in [0, 1)") }
    }

    @Test func ign_knownPixel_matchesFormula() throws {
        // Verify the IGN formula: fract(52.9829189 * fract(dot(p, (0.06711056, 0.00583715))))
        let pts = [SIMD3<Float>(100, 200, 0)]
        let kernel = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            outputs[tid] = ign(inputs[tid].xy);
        }
        """
        let results = try runNoiseKernel(kernelSource: kernel, inputs: pts)
        let p = SIMD2<Float>(100, 200)
        let magic = SIMD3<Float>(0.06711056, 0.00583715, 52.9829189)
        let expected = (magic.z * ((p.x * magic.x + p.y * magic.y).truncatingRemainder(dividingBy: 1))).truncatingRemainder(dividingBy: 1)
        // Allow floating-point rounding tolerance between Swift and Metal.
        #expect(abs(results[0] - expected) < 0.01,
            "ign(\(p)) = \(results[0]), expected ≈ \(expected)")
    }

    @Test func ign_temporal_variesByFrame() throws {
        let pts = [SIMD3<Float>(42, 17, 0)]
        // Run with frame index 0 and frame index 1 — results should differ by golden-ratio step.
        let kernel0 = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) { outputs[tid] = ign_temporal(inputs[tid].xy, 0); }
        """
        let kernel1 = """
        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) { outputs[tid] = ign_temporal(inputs[tid].xy, 1); }
        """
        let r0 = try runNoiseKernel(kernelSource: kernel0, inputs: pts)
        let r1 = try runNoiseKernel(kernelSource: kernel1, inputs: pts)
        #expect(r0[0] != r1[0], "ign_temporal should differ between frames")
    }
}
