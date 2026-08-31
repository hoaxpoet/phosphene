// HexTileTests.swift — Tests for Utilities/Geometry/HexTile.metal (V.2 Part A).

import Testing
import Metal
@testable import Presets

@Suite("Hex Tiling")
struct HexTileTests {

    @Test func test_hexTile_weightsSumToOne() throws {
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = inputs[tid].xy;
            HexTileResult h = hex_tile_uv(uv, 3.0, 0.4);
            outputs[tid] = h.weightA + h.weightB + h.weightC;
        }
        """
        var pts: [SIMD3<Float>] = []
        for i in 0..<16 {
            for j in 0..<16 {
                pts.append(SIMD3(Float(i) / 16.0, Float(j) / 16.0, 0))
            }
        }
        let sums = try runNoiseKernel(kernelSource: src, inputs: pts)
        for (i, s) in sums.enumerated() {
            #expect(abs(s - 1.0) < 0.001, "weights don't sum to 1 at UV[\(i)]: \(s)")
        }
    }

    @Test func test_hexTile_weightsNonNegative() throws {
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = inputs[tid].xy;
            HexTileResult h = hex_tile_uv(uv, 4.0, 0.3);
            // outputs: min of the three weights (should be ≥ 0)
            outputs[tid] = min(h.weightA, min(h.weightB, h.weightC));
        }
        """
        let pts = (0..<32).map { i in SIMD3<Float>(Float(i) * 0.083, Float(i) * 0.059, 0) }
        let mins = try runNoiseKernel(kernelSource: src, inputs: pts)
        for m in mins {
            #expect(m >= -0.001, "negative blend weight found: \(m)")
        }
    }

    @Test func test_hexTile_uvDistinctForDifferentCells() throws {
        // At two UV positions far apart (different hex cells), uvA should differ.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            HexTileResult h = hex_tile_uv(inputs[tid].xy, 5.0, 0.4);
            outputs[tid * 2    ] = h.uvA.x;
            outputs[tid * 2 + 1] = h.uvA.y;
        }
        """
        let r = try runNoiseKernel(kernelSource: src,
                                   inputs: [SIMD3(0.1, 0.1, 0), SIMD3(0.9, 0.9, 0)],
                                   outputCount: 4)
        let uvA0 = SIMD2<Float>(r[0], r[1])
        let uvA1 = SIMD2<Float>(r[2], r[3])
        let delta = uvA1 - uvA0
        let diff = sqrt(delta.x * delta.x + delta.y * delta.y)
        #expect(diff > 0.01, "uvA should differ across cells: diff=\(diff)")
    }

    @Test func test_preamble_containsHexTileFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("HexTileResult"), "HexTileResult struct missing")
        #expect(p.contains("hex_tile_uv"), "hex_tile_uv missing from preamble")
        #expect(p.contains("hex_tile_weights"), "hex_tile_weights missing from preamble")
    }
}
