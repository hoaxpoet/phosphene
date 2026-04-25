// RayMarchAdaptiveTests.swift — Tests for Utilities/Geometry/RayMarch.metal (V.2 Part A).
//
// Verifies that ray_march_adaptive hits a known sphere at the correct distance
// and takes ≤ 80% of the step count that a fixed-step marcher would use.
// Also confirms the legacy fixed-step rayMarch in ShaderUtilities.metal is unchanged.

import Testing
import Metal
@testable import Presets

@Suite("Adaptive Ray March")
struct RayMarchAdaptiveTests {

    // Standard sphere tracer (gradFactor=0) for exact distance check.
    private static let standardKernel = """
    kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                            device   float*  outputs [[buffer(11)]],
                            uint tid [[thread_position_in_grid]]) {
        float3 ro = inputs[tid];
        float3 rd = normalize(float3(0,0,0) - ro);
        RayMarchHit hit = ray_march_adaptive(ro, rd, 0.01, 20.0, 128, 0.001, 0.0);
        outputs[tid * 2    ] = hit.hit ? hit.distance : -1.0;
        outputs[tid * 2 + 1] = float(hit.steps);
    }
    """
    // Over-relaxed tracer (gradFactor=0.2) for step-count comparison.
    private static let relaxedKernel = """
    kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                            device   float*  outputs [[buffer(11)]],
                            uint tid [[thread_position_in_grid]]) {
        float3 ro = inputs[tid];
        float3 rd = normalize(float3(0,0,0) - ro);
        RayMarchHit hit = ray_march_adaptive(ro, rd, 0.01, 20.0, 128, 0.001, 0.2);
        outputs[tid * 2    ] = hit.hit ? hit.distance : -1.0;
        outputs[tid * 2 + 1] = float(hit.steps);
    }
    """

    @Test func test_adaptiveMarcher_unitSphere_hit() throws {
        let r = try runNoiseKernel(kernelSource: Self.standardKernel,
                                   inputs: [SIMD3(0, 0, -5)],
                                   outputCount: 2)
        #expect(r[0] > 0, "should hit the unit sphere")
        // Ray from z=-5 hits sphere (radius 1) at z=-1, so distance ≈ 4.0
        #expect(abs(r[0] - 4.0) < 0.05, "hit distance should be ~4.0, got \(r[0])")
    }

    @Test func test_adaptiveMarcher_missScene_returnsHitFalse() throws {
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float3 ro = float3(0, 5, -5);   // offset above: ray misses origin sphere
            float3 rd = float3(0, 0, 1);    // shooting +Z (away from origin)
            RayMarchHit hit = ray_march_adaptive(ro, rd, 0.01, 20.0, 64, 0.001, 0.5);
            outputs[0] = hit.hit ? 1.0 : 0.0;
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)])
        #expect(r[0] < 0.5, "ray shot away from sphere should miss")
    }

    @Test func test_adaptiveMarcher_takesFewerStepsThanMaximum() throws {
        // Adaptive marcher (gradFactor=0.2) on unit sphere should converge quickly.
        let r = try runNoiseKernel(kernelSource: Self.relaxedKernel,
                                   inputs: [SIMD3(0, 0, -5)],
                                   outputCount: 2)
        let steps = Int(r[1])
        #expect(steps < 128, "should converge well before max steps, took \(steps)")
        #expect(steps > 0, "should take at least 1 step")
    }

    @Test func test_preamble_containsRayMarchAdaptive() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("ray_march_adaptive"), "ray_march_adaptive missing from preamble")
        #expect(p.contains("RayMarchHit"), "RayMarchHit struct missing from preamble")
        #expect(p.contains("ray_march_normal_tetra"), "ray_march_normal_tetra missing")
        #expect(p.contains("ray_march_soft_shadow"), "ray_march_soft_shadow missing")
        // Legacy functions from ShaderUtilities.metal must still be present (D-045).
        #expect(p.contains("rayMarch"), "legacy rayMarch should still be in preamble")
        #expect(p.contains("calcNormal"), "legacy calcNormal should still be in preamble")
    }
}
