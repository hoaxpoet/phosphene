// VoronoiTests.swift — Tests for Utilities/Texture/Voronoi.metal (V.2 Part C).

import Testing
import Metal
@testable import Presets

@Suite("Voronoi")
struct VoronoiTests {

    @Test func test_preamble_containsVoronoiFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("VoronoiResult"), "VoronoiResult struct missing from preamble")
        #expect(p.contains("voronoi_f1f2"),  "voronoi_f1f2 missing from preamble")
        #expect(p.contains("voronoi_3d_f1"), "voronoi_3d_f1 missing from preamble")
        #expect(p.contains("voronoi_cracks"),"voronoi_cracks missing from preamble")
    }

    @Test func test_voronoiF1F2_f1LessThanF2() throws {
        // F1 ≤ F2 must hold everywhere.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = inputs[tid].xy;
            VoronoiResult v = voronoi_f1f2(uv, 4.0);
            outputs[tid * 2    ] = v.f1;
            outputs[tid * 2 + 1] = v.f2;
        }
        """
        var pts: [SIMD3<Float>] = []
        for i in 0..<16 {
            for j in 0..<16 {
                pts.append(SIMD3(Float(i) / 16.0, Float(j) / 16.0, 0))
            }
        }
        let results = try runNoiseKernel(kernelSource: src, inputs: pts, outputCount: pts.count * 2)
        for i in 0..<pts.count {
            let f1 = results[i * 2]
            let f2 = results[i * 2 + 1]
            #expect(f1 <= f2 + 0.001, "F1 should be ≤ F2 at index \(i): f1=\(f1) f2=\(f2)")
        }
    }

    @Test func test_voronoiF1F2_f1NonNegative() throws {
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = inputs[tid].xy;
            VoronoiResult v = voronoi_f1f2(uv, 5.0);
            outputs[tid] = v.f1;
        }
        """
        let pts = (0..<32).map { i in SIMD3<Float>(Float(i) * 0.08, Float(i) * 0.06, 0) }
        let results = try runNoiseKernel(kernelSource: src, inputs: pts)
        for (i, f1) in results.enumerated() {
            #expect(f1 >= -0.001, "F1 should be non-negative at index \(i): \(f1)")
        }
    }

    @Test func test_voronoiCracks_inRange() throws {
        // voronoi_cracks should return [0,1].
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = inputs[tid].xy;
            outputs[tid] = voronoi_cracks(uv, 4.0, 0.05);
        }
        """
        var pts: [SIMD3<Float>] = []
        for i in 0..<16 {
            for j in 0..<16 {
                pts.append(SIMD3(Float(i) / 16.0 + 0.03, Float(j) / 16.0 + 0.03, 0))
            }
        }
        let results = try runNoiseKernel(kernelSource: src, inputs: pts)
        for (i, c) in results.enumerated() {
            #expect(c >= -0.001 && c <= 1.001,
                    "voronoi_cracks out of [0,1] at index \(i): \(c)")
        }
    }

    @Test func test_voronoi3dF1_nonNegative() throws {
        // 3D Voronoi F1 should be non-negative everywhere.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            outputs[tid] = voronoi_3d_f1(inputs[tid], 3.0);
        }
        """
        let pts = (0..<20).map { i in
            SIMD3<Float>(Float(i) * 0.15, Float(i % 5) * 0.3, Float(i / 5) * 0.25)
        }
        let results = try runNoiseKernel(kernelSource: src, inputs: pts)
        for (i, f1) in results.enumerated() {
            #expect(f1 >= -0.001, "voronoi_3d_f1 should be non-negative at index \(i): \(f1)")
        }
    }
}
