// GrungeTests.swift — Tests for Utilities/Texture/Grunge.metal (V.2 Part C).

import Testing
import Metal
@testable import Presets

@Suite("Grunge")
struct GrungeTests {

    @Test func test_preamble_containsGrungeFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("grunge_scratches"),    "grunge_scratches missing")
        #expect(p.contains("grunge_rust"),         "grunge_rust missing")
        #expect(p.contains("grunge_edge_wear"),    "grunge_edge_wear missing")
        #expect(p.contains("grunge_dust"),         "grunge_dust missing")
        #expect(p.contains("grunge_crack"),        "grunge_crack missing")
        #expect(p.contains("GrungeResult"),        "GrungeResult struct missing")
        #expect(p.contains("grunge_composite"),    "grunge_composite missing")
    }

    @Test func test_grungeScratches_inRange() throws {
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = inputs[tid].xy;
            outputs[tid] = grunge_scratches(uv, float2(1,0), 12.0, 8.0);
        }
        """
        var pts: [SIMD3<Float>] = []
        for i in 0..<16 { for j in 0..<16 {
            pts.append(SIMD3(Float(i) / 16.0, Float(j) / 16.0, 0))
        }}
        let results = try runNoiseKernel(kernelSource: src, inputs: pts)
        for (i, v) in results.enumerated() {
            #expect(v >= -0.001 && v <= 1.001,
                    "grunge_scratches out of [0,1] at index \(i): \(v)")
        }
    }

    @Test func test_grungeRust_moreCoverageGivesMoreRust() throws {
        // With coverage=0, rust=0; with coverage=1, rust>0.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = float2(0.5, 0.5);
            outputs[0] = grunge_rust(uv, 3.0, 0.0);    // no rust
            outputs[1] = grunge_rust(uv, 3.0, 1.0);    // full rust
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 2)
        #expect(r[0] < 0.001, "grunge_rust at coverage=0 should be ~0, got \(r[0])")
        #expect(r[1] >= 0.0,  "grunge_rust at coverage=1 should be non-negative, got \(r[1])")
    }

    @Test func test_grungeDirtMask_moreDirtyAtLowAO() throws {
        // Dirt mask: more dirt (higher value) at low AO (occluded area).
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            outputs[0] = grunge_dirt_mask(0.0, 1.0);   // fully occluded
            outputs[1] = grunge_dirt_mask(1.0, 1.0);   // fully lit
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 2)
        #expect(r[0] > r[1], "Dirt mask should be heavier in occluded areas: \(r[0]) vs \(r[1])")
    }

    @Test func test_grungeComposite_roughnessDeltaInRange() throws {
        // GrungeResult.roughnessDelta should be non-negative and bounded.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = inputs[tid].xy;
            float3 p  = float3(uv, 0.0);
            GrungeResult g = grunge_composite(uv, p, 0.5, 0.5, 0.5, 0.5, 0.3);
            outputs[tid * 2    ] = g.roughnessDelta;
            outputs[tid * 2 + 1] = g.albedoTint.x;
        }
        """
        var pts: [SIMD3<Float>] = []
        for i in 0..<16 { pts.append(SIMD3(Float(i) / 16.0, Float(i % 4) / 16.0, 0)) }
        let results = try runNoiseKernel(kernelSource: src, inputs: pts, outputCount: pts.count * 2)
        for i in 0..<pts.count {
            let delta = results[i * 2]
            let tint  = results[i * 2 + 1]
            #expect(delta >= -0.001, "roughnessDelta should be ≥ 0 at index \(i): \(delta)")
            #expect(delta <= 0.5,   "roughnessDelta should be bounded at index \(i): \(delta)")
            #expect(tint >= 0.0 && tint <= 1.0,
                    "albedoTint.x should be in [0,1] at index \(i): \(tint)")
        }
    }

    @Test func test_grungeCrack_inRange() throws {
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = inputs[tid].xy;
            outputs[tid] = grunge_crack(uv, 5.0, 0.04);
        }
        """
        var pts: [SIMD3<Float>] = []
        for i in 0..<16 { for j in 0..<16 {
            pts.append(SIMD3(Float(i) / 16.0 + 0.02, Float(j) / 16.0 + 0.02, 0))
        }}
        let results = try runNoiseKernel(kernelSource: src, inputs: pts)
        for (i, v) in results.enumerated() {
            #expect(v >= -0.001 && v <= 1.001,
                    "grunge_crack out of [0,1] at index \(i): \(v)")
        }
    }
}
