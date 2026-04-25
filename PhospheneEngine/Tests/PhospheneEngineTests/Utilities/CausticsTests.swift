// CausticsTests.swift — Tests for Utilities/Volume/Caustics.metal (V.2 Part B).

import Testing
import Metal
@testable import Presets

@Suite("Caustics")
struct CausticsTests {

    @Test func test_preamble_containsCausticFunctions() {
        let p = PresetLoader.shaderPreamble
        #expect(p.contains("caust_wave"),     "caust_wave missing from preamble")
        #expect(p.contains("caust_fbm"),      "caust_fbm missing from preamble")
        #expect(p.contains("caust_animated"), "caust_animated missing from preamble")
        #expect(p.contains("caust_audio"),    "caust_audio missing from preamble")
    }

    @Test func test_caustWave_inRange() throws {
        // caust_wave should return values in [0, 1].
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = inputs[tid].xy;
            outputs[tid] = caust_wave(uv, 3.0, 4.0);
        }
        """
        var pts: [SIMD3<Float>] = []
        for i in 0..<16 {
            for j in 0..<16 {
                pts.append(SIMD3(Float(i) / 16.0, Float(j) / 16.0, 0))
            }
        }
        let results = try runNoiseKernel(kernelSource: src, inputs: pts)
        for (i, c) in results.enumerated() {
            #expect(c >= -0.001 && c <= 1.001,
                    "caust_wave out of range [0,1] at index \(i): \(c)")
        }
    }

    @Test func test_caustAnimated_variesWithTime() throws {
        // Same UV at different times should produce different caustic patterns.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = float2(0.3, 0.4);
            outputs[0] = caust_animated(uv, 0.0);
            outputs[1] = caust_animated(uv, 5.0);
        }
        """
        let r = try runNoiseKernel(kernelSource: src, inputs: [SIMD3(0, 0, 0)], outputCount: 2)
        #expect(abs(r[0] - r[1]) > 0.01,
                "caust_animated should produce different values at t=0 vs t=5: \(r[0]) vs \(r[1])")
    }

    @Test func test_caustAudio_nonNegative() throws {
        // caust_audio should never produce negative values.
        let src = """
        kernel void test_kernel(constant float3* inputs [[buffer(10)]],
                                device   float*  outputs [[buffer(11)]],
                                uint tid [[thread_position_in_grid]]) {
            float2 uv = inputs[tid].xy;
            outputs[tid] = caust_audio(uv, 3.0, 0.0, 0.0);
        }
        """
        let pts = (0..<32).map { i in SIMD3<Float>(Float(i) * 0.07, Float(i) * 0.05, 0) }
        let results = try runNoiseKernel(kernelSource: src, inputs: pts)
        for (i, c) in results.enumerated() {
            #expect(c >= -0.001, "caust_audio should be non-negative, got \(c) at index \(i)")
        }
    }
}
