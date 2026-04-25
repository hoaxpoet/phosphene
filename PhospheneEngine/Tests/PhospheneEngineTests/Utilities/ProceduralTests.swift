// ProceduralTests.swift — Tests for Utilities/Texture/Procedural.metal (V.2 Part C).

import Testing
import Metal
@testable import Presets

@Suite("Procedural Patterns")
struct ProceduralTests {

    @Test func test_preamble_containsProceduralFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("proc_stripes"),     "proc_stripes missing")
        #expect(p.contains("proc_checker"),     "proc_checker missing")
        #expect(p.contains("proc_grid"),        "proc_grid missing")
        #expect(p.contains("proc_hex_grid"),    "proc_hex_grid missing")
        #expect(p.contains("proc_dots"),        "proc_dots missing")
        #expect(p.contains("proc_brick"),       "proc_brick missing")
        #expect(p.contains("proc_wood"),        "proc_wood missing")
    }

    @Test func test_procStripes_binary() throws {
        // proc_stripes should return 0 or 1 (sharp step).
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            outputs[tid] = proc_stripes(inputs[tid].x, 4.0, 0.5);
        }
        """
        let xs: [Float] = [0, 0.05, 0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95]
        let inputs = xs.map { SIMD3<Float>($0, 0, 0) }
        let results = try runNoiseKernel(kernelSource: src, inputs: inputs)
        for (i, v) in results.enumerated() {
            let isZero = abs(v) < 0.001
            let isOne  = abs(v - 1.0) < 0.001
            #expect(isZero || isOne, "proc_stripes should be 0 or 1 at x=\(xs[i]), got \(v)")
        }
    }

    @Test func test_procChecker_alternates() throws {
        // Adjacent cells in checkerboard should be different.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            outputs[0] = proc_checker(float2(0.1, 0.1), 2.0);
            outputs[1] = proc_checker(float2(0.6, 0.1), 2.0);
            outputs[2] = proc_checker(float2(0.1, 0.6), 2.0);
            outputs[3] = proc_checker(float2(0.6, 0.6), 2.0);
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 4)
        // Checker: (0,0) and (1,1) same; (0,0) and (1,0) different.
        #expect(abs(r[0] - r[3]) < 0.001, "Diagonal checker cells should match")
        #expect(abs(r[0] - r[1]) > 0.5,   "Adjacent checker cells should differ")
    }

    @Test func test_procGrid_returnsOneOnLines() throws {
        // At the center of a grid cell, result should be 0 (not on a line).
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            // scale=2: cells are 0.5 wide. Centre of first cell is at (0.25, 0.25).
            outputs[0] = proc_grid(float2(0.25, 0.25), 2.0, 0.05);  // cell centre
            outputs[1] = proc_grid(float2(0.0,  0.25), 2.0, 0.05);  // on line
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 2)
        #expect(r[0] < 0.1, "proc_grid at cell centre should be 0 (not on line), got \(r[0])")
        #expect(r[1] > 0.5, "proc_grid at x=0 should be on a grid line, got \(r[1])")
    }

    @Test func test_procDots_centreVsEdge() throws {
        // At dot centre (0.5, 0.5 within cell) should be 1; at corner should be 0.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            // scale=1: cell size = 1.0. Centre of cell at (0.5,0.5), corner at (0,0).
            outputs[0] = proc_dots(float2(0.5, 0.5), 1.0, 0.3);   // inside dot
            outputs[1] = proc_dots(float2(0.0, 0.0), 1.0, 0.3);   // at corner, outside
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 2)
        #expect(r[0] > 0.5, "proc_dots at cell centre should be inside dot, got \(r[0])")
        #expect(r[1] < 0.5, "proc_dots at corner should be outside dot, got \(r[1])")
    }

    @Test func test_procWood_inRange() throws {
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            outputs[tid] = proc_wood(inputs[tid], 5.0, 2.0, 0.3);
        }
        """
        let pts = (0..<20).map { i in SIMD3<Float>(Float(i) * 0.3, 0, Float(i) * 0.2) }
        let results = try runNoiseKernel(kernelSource: src, inputs: pts)
        for (i, v) in results.enumerated() {
            #expect(v >= -0.001 && v <= 1.001,
                    "proc_wood out of [0,1] at index \(i): \(v)")
        }
    }
}
