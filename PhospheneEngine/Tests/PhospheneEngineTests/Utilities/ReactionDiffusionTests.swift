// ReactionDiffusionTests.swift — Tests for Utilities/Texture/ReactionDiffusion.metal (V.2 Part C).

import Testing
import Metal
@testable import Presets

@Suite("Reaction Diffusion")
struct ReactionDiffusionTests {

    @Test func test_preamble_containsRDFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("rd_pattern_approx"), "rd_pattern_approx missing")
        #expect(p.contains("rd_spots"),          "rd_spots missing")
        #expect(p.contains("rd_stripes"),        "rd_stripes missing")
        #expect(p.contains("rd_worms"),          "rd_worms missing")
        #expect(p.contains("rd_step"),           "rd_step missing")
        #expect(p.contains("rd_colorize"),       "rd_colorize missing")
    }

    @Test func test_rdPatternApprox_inRange() throws {
        // Pattern approximation must stay in [0,1].
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = inputs[tid].xy;
            outputs[tid] = rd_pattern_approx(uv, 3.0, 0.037, 0.060);
        }
        """
        var pts: [SIMD3<Float>] = []
        for i in 0..<16 { for j in 0..<16 {
            pts.append(SIMD3(Float(i) / 16.0, Float(j) / 16.0, 0))
        }}
        let results = try runNoiseKernel(kernelSource: src, inputs: pts)
        for (i, v) in results.enumerated() {
            #expect(v >= -0.001 && v <= 1.001,
                    "rd_pattern_approx out of [0,1] at index \(i): \(v)")
        }
    }

    @Test func test_rdStep_clampsOutput() throws {
        // rd_step must clamp A and B to [0,1] even with extreme Laplacians.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 ab  = float2(1.0, 0.5);
            float  lapA = 100.0, lapB = -100.0;   // extreme values
            float2 next = rd_step(ab, lapA, lapB, 1.0, 0.037, 0.060);
            outputs[0]  = next.x;
            outputs[1]  = next.y;
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 2)
        #expect(r[0] >= 0.0 && r[0] <= 1.0, "rd_step A must be in [0,1], got \(r[0])")
        #expect(r[1] >= 0.0 && r[1] <= 1.0, "rd_step B must be in [0,1], got \(r[1])")
    }

    @Test func test_rdColorize_blendsBetweenColors() throws {
        // At b=0 should return colorA, at b=1 should return colorB.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float3 cA = float3(0.1, 0.2, 0.3);
            float3 cB = float3(0.7, 0.8, 0.9);
            float3 at0 = rd_colorize(0.0, cA, cB);
            float3 at1 = rd_colorize(1.0, cA, cB);
            outputs[0] = at0.x; outputs[1] = at0.y; outputs[2] = at0.z;
            outputs[3] = at1.x; outputs[4] = at1.y; outputs[5] = at1.z;
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 6)
        #expect(abs(r[0] - 0.1) < 0.01, "At b=0, color.x should be colorA.x=0.1, got \(r[0])")
        #expect(abs(r[3] - 0.7) < 0.01, "At b=1, color.x should be colorB.x=0.7, got \(r[3])")
    }

    @Test func test_rdAnimated_variesWithTime() throws {
        // rd_pattern_animated at t=0 and t=30 should produce different patterns
        // because the time-based UV drift moves through the noise field.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = inputs[tid].xy;
            // Use low threshold params so coverage is broad and changes are detectable.
            outputs[tid * 2    ] = rd_pattern_animated(uv, 1.0, 0.0,  0.037, 0.060, 0.0);
            outputs[tid * 2 + 1] = rd_pattern_animated(uv, 1.0, 30.0, 0.037, 0.060, 0.0);
        }
        """
        var pts: [SIMD3<Float>] = []
        for i in 0..<8 { for j in 0..<8 {
            pts.append(SIMD3(Float(i) * 0.7 + 0.2, Float(j) * 0.6 + 0.2, 0))
        }}
        let results = try runNoiseKernel(kernelSource: src, inputs: pts, outputCount: pts.count * 2)
        var anyDiff = false
        for i in 0..<pts.count {
            if abs(results[i * 2] - results[i * 2 + 1]) > 0.01 { anyDiff = true; break }
        }
        #expect(anyDiff, "rd_pattern_animated should produce different results at t=0 vs t=30")
    }
}
